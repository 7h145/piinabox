#!/bin/bash
# vim:et:ai:sw=2:tw=0:ft=bash
#
# copyright 2026 <github.attic@typedef.net>, CC BY 4.0
#
# This is just a wrapper script for the containerized pi agent.
#
# Remark: This wrapper was build an tested using podman as container
#  runtime.  It should work just fine with other "docker lookalike"
#  runtimes, like e.g. docker.  See $C[crt] configuration below.
#  The comments in this script always refer to podman however.
#
# Usage: ${IAM} [SOURCE-VOLUME|HOST-DIR[:OPTIONS]...] [PI-ARGV...]
#
# Leading `podman run --volume` "mount specification like" arguments are
# parsed and mounted into the containers `WORKDIR`, further arguments
# are passed through to the payload executable (pi) verbatim.
#
# Examples:
#
# * Mount `~/projects/thisone` and `~/projects/anotherone` into the
#  containers `$PWD/thisone` and `$PWD/anotherone`:
#
#    ${IAM} ~/projects/thisone ~/projects/anotherone
#
# * Special case: same as before, but in addition mount the current $PWD
#  directly into the containers $PWD:
#
#    ${IAM} ~/projects/thisone ~/projects/anotherone .
#
# * Mount the current $PWD and some file directly into the containers
#  $PWD and pass some arguments to the payload executable:
#
#    cd ~/projects/thatone
#    ${IAM} . ~/some/additional/file:ro run 'explain this codebase'

#set -vx; set -o functrace

IAM="${0##*/}"; REALPWD="$(realpath -e "${PWD}")"

declare -A C=(
  # Some configuration knobs to twiddle with for the inclined

  # Container runtime: This wrapper was build an tested using podman
  # (https://github.com/containers/podman) as (high-level) container
  # runtime, but should run just fine with other "docker lookalike"
  # OCI runtimes, like e.g. docker (https://github.com/docker).
  # Default is 'podman'.
  [crt]='podman'
  #[crt]='docker'

  # The name prefix for containers and volumes: containers running with
  # the same name prefix share their runtime volumes.
  # The default name prefix is derived from the basename of this script.
  [name]="${IAM%.sh}"

  # Mount mode settings for host directories below:  Values 'ro', 'rw',
  # and 'O' mean: if a suitable host-side directory exists, mount it
  # into the container with the selected `--volume` option.
  #
  #  ro      read-only bind mount
  #  rw      read/write bind mount
  #  O       podman overlay mount: host files are visible, container
  #          writes succeed, changes are discarded with the container
  #
  # Further values are
  #
  #  volume  read/write mount a dedicated volume for this container
  #          directory (when applicable)
  #  false   do not mount this volume or directory
  #
  # Note: 'O' is podman-specific; use 'ro' or 'rw' with docker.

  # Pi coding agent configuration directory.
  # Default: 'rw', mount an existing host pi configuration directory
  # read/write into the container, if none exists, use 'volume'.
  [mount_pi_coding_agent_dir]='rw'

  # Pi coding agent session directory.
  # Default: 'rw', mount an existing host pi sessions directory
  # read/write into the container, if none exists, use 'volume'.
  [mount_pi_coding_agent_session_dir]='rw'

  # Pi coding agent $XDG_DATA_HOME/pi/agent.  Idea: you may symlink from
  # your configuration to keep unwieldy stuff in $XDG_DATA_HOME.
  # Default: 'rw', mount an existing $XDG_DATA_HOME/pi/agent read/write
  # into the container, no volume fallback.
  [mount_xdg_data_home]='rw'

  # Host vim configuration (always 'ro', no volume fallback).
  # Default: 'true', mount found vim configuration read-only.
  [use_vim_configuration]='true'

  # Host tmux configuration (always 'ro', no volume fallback).
  # Default: 'true', mount found tmux configuration read-only.
  [use_tmux_configuration]='true'
)

# XDG base directories reminder
XDG_DATA_HOME="${XDG_DATA_HOME:-"${HOME}/.local/share"}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-"${HOME}/.config"}"

# list of plausible $PI_CODING_AGENT_DIR-s in order of precedence
declare -a PI_CODING_AGENT_DIR_CANDIDATES=(
  ${PI_CODING_AGENT_DIR:+"${PI_CODING_AGENT_DIR}"}
  "${XDG_CONFIG_HOME}/pi/agent"
  "${HOME}/.pi/agent"
)

# list of plausible $PI_CODING_AGENT_SESSION_DIR-s in order of precedence
declare -a PI_CODING_AGENT_SESSION_DIR_CANDIDATES=(
  ${PI_CODING_AGENT_SESSION_DIR:+"${PI_CODING_AGENT_SESSION_DIR}"}
  "${XDG_DATA_HOME}/pi/agent/sessions"
  "${PI_CODING_AGENT_DIR_CANDIDATES[@]/%//sessions}"
)

vspec() {
  # $*: VSPEC associative arrays.  Print the "default" fields of each VSPEC
  # array in podman-run(1) `--volume` argument format to stdout.

  local ARGV; for ARGV in "${@}"; do
    declare -n ARRAY="${ARGV}"

    printf '%s:%s%s' \
      "${ARRAY[source-volorpath]:?}" \
      "${ARRAY[container-dir]:?}" \
      "${ARRAY[options]}"
  done
}

volume_exists() {
  # $1: volume name.  Return 0 if the volume $1 exists or 1 otherwise.
  # This is a cross container runtime version of `podman volume exists`.

  "${C[crt]}" volume inspect "${1:?}" >/dev/null 2>&1
}

first_existing_dir() {
  # $*: directories.  Print the resolved absolute name of the first
  # existing directory in $* to stdout.

  local ARGV; for ARGV in "${@:?}"; do
    [[ -d "${ARGV}" ]] && { realpath -e "${ARGV}"; return; }
  done
}

parse_volumespec() {
  # Check if $1 is a podman-run(1) `--volume` "mount specification like
  # thing"; if so, return the `--volume` argument for this mount.
  #
  # Mount the desired volume or path into sub-directories of the
  # container `WORKDIR`; in case the desired path is $PWD or a file,
  # mount directly into the container `WORKDIR` instead.

  [[ -n "${1}" ]] || return 1

  declare -A VSPEC=(
    # everything up to the last `:` is considered a volume or a directory
    [volorpath]="${1%:*}"

    # everything after the last `:` are mount options
    [options]="$([[ "${1##*:}" != "${1}" ]] && echo ":${1##*:}")"

    [source-volorpath]=''

    # the container `WORKDIR` (i.e. payload $PWD)
    [container-dir]='/stage'
  )

  # check if $volorpath is a podman volume or a path
  if volume_exists "${VSPEC[volorpath]}"; then
    # this is a podman volume
    VSPEC[source-volorpath]="${VSPEC[volorpath]}"
    VSPEC[container-dir]+="/${VSPEC[volorpath]}"

  elif [[ -d "${VSPEC[volorpath]}" || -f "${VSPEC[volorpath]}" ]]; then
    # this is a directory or a file
    VSPEC[volorpath]="$(realpath -e "${VSPEC[volorpath]}")"
    VSPEC[source-volorpath]="${VSPEC[volorpath]}"
    # the "path is $PWD" exception
    [[ "${VSPEC[volorpath]}" != "${REALPWD}" ]] &&
      VSPEC[container-dir]+="/${VSPEC[volorpath]##*/}"

  else
    # it's neither a volume nor a directory or file
    return 1
  fi

  vspec VSPEC
}

# check positional parameters for podman-run(1) `--volume` "mount
# specification like things", prepare the `--volume` options
declare -a PMARGS_PRJVOLUMES
while [[ "${#}" -gt '0' && "${1:0:1}" != '-' ]]; do
  VOLUMESPEC="$(parse_volumespec "${1}")" || break
  PMARGS_PRJVOLUMES+=( '--volume' "${VOLUMESPEC}" )
shift; done

if (( ${#PMARGS_PRJVOLUMES[@]} )); then
  # show what will be mounted
  echo "${IAM}: [notice] will mount:" >&2
  for i in "${PMARGS_PRJVOLUMES[@]/#${HOME}/'~'}"; do
    [[ "${i}" != '--volume' ]] && echo "  ${i}"
  done |sort -t: -k1dr >&2
else
  # no plan to mount something in(to) the containers `WORKDIR`?
  echo "${IAM}: [warning] no persistent project directory mount given" >&2
fi


PMARGS_VOLUMES=(
  # static volumes, runtime data.  nothing for pi yet
  #'--volume' "${C[name]}-something:/something"
)

# pi agent $XDG_DATA_HOME: mount an existing $XDG_DATA_HOME/pi/agent
# directory into the container.
if [[ -v C[mount_xdg_data_home] ]] &&
  [[ ! "${C[mount_xdg_data_home]}" =~ ^(false|no|0)$ ]]; then

  declare -A VSPEC=(
    #[source-volorpath]="${C[name]}-xdgdata"
    [container-dir]='/root/.local/share/pi/agent'
  )

  [[ "${C[mount_xdg_data_home]}" =~ ^(ro|rw|O)$ ]] && {
    HOSTPIXDGDATADIR="$(
      first_existing_dir "${XDG_DATA_HOME}/pi/agent")" && {

      VSPEC[source-volorpath]="${HOSTPIXDGDATADIR}"
      VSPEC[options]=":${BASH_REMATCH[0]}"

      PMARGS_VOLUMES+=( '--volume' "$(vspec VSPEC)" )
    }
  }
fi

# pi agent configuration: use a dedicated volume or mount an existing pi
# configuration directory into the container.
if [[ -v C[mount_pi_coding_agent_dir] ]] &&
  [[ ! "${C[mount_pi_coding_agent_dir]}" =~ ^(false|no|0)$ ]]; then

  declare -A VSPEC=(
    [source-volorpath]="${C[name]}-config"
    [container-dir]='/root/.config/pi/agent'
  )

  [[ "${C[mount_pi_coding_agent_dir]}" =~ ^(ro|rw|O)$ ]] && {
    HOSTPICONFIGDIR="$(
      first_existing_dir "${PI_CODING_AGENT_DIR_CANDIDATES[@]}")" && {

      VSPEC[source-volorpath]="${HOSTPICONFIGDIR}"
      VSPEC[options]=":${BASH_REMATCH[0]}"
    }
  }

  PMARGS_VOLUMES+=( '--volume' "$(vspec VSPEC)" )
fi

# pi agent sessions: use a dedicated volume or mount an existing pi
# sessions directory into the container.
if [[ -v C[mount_pi_coding_agent_session_dir] ]] &&
  [[ ! "${C[mount_pi_coding_agent_session_dir]}" =~ ^(false|no|0)$ ]]; then

  declare -A VSPEC=(
    [source-volorpath]="${C[name]}-sessions"
    [container-dir]='/root/.local/share/pi/agent/sessions'
  )

  [[ "${C[mount_pi_coding_agent_session_dir]}" =~ ^(ro|rw|O)$ ]] && {
    HOSTPISESSIONDIR="$(
      first_existing_dir "${PI_CODING_AGENT_SESSION_DIR_CANDIDATES[@]}")" && {

      VSPEC[source-volorpath]="${HOSTPISESSIONDIR}"
      VSPEC[options]=":${BASH_REMATCH[0]}"
    }
  }

  PMARGS_VOLUMES+=( '--volume' "$(vspec VSPEC)" )
fi

# vim configuration: if some vim configuration can be found, mount it
# into the container.
[[ "${C[use_vim_configuration]}" = 'true' ]] && {
  [[ -f "${HOME}/.vimrc" ]] &&
    PMARGS_VOLUMES+=( '--volume' "${HOME}/.vimrc:/root/.vimrc:ro" )

  if [[ -d "${HOME}/.vim" ]]; then
    PMARGS_VOLUMES+=( '--volume' "${HOME}/.vim:/root/.vim:ro" )
  else
    [[ -d "${XDG_CONFIG_HOME}/vim" ]] &&
      PMARGS_VOLUMES+=( '--volume' "${XDG_CONFIG_HOME}/vim:/root/.vim:ro" )
  fi
}

# tmux configuration: if some tmux configuration can be found, mount it
# into the container.
[[ "${C[use_tmux_configuration]}" = 'true' ]] && {
  [[ -f "${HOME}/.tmux.conf" ]] &&
    PMARGS_VOLUMES+=( '--volume' "${HOME}/.tmux.conf:/root/.tmux.conf:ro" )

  [[ -d "${XDG_CONFIG_HOME}/tmux" ]] &&
    PMARGS_VOLUMES+=( '--volume'
      "${XDG_CONFIG_HOME}/tmux:/root/.config/tmux:ro" )
}

# pass PI_ environment variables trough into the container.
declare -a PMARGS_PIENV; while read -r PIENV; do
  [[ "${PIENV}" =~ ^PI_.*_DIR$ ]] && continue
  PMARGS_PIENV+=( '--env' "${PIENV}" )
done < <(compgen -e 'PI_')

PMARGV=(
  '--name' "${C[name]}-${SRANDOM}"
  '--interactive' '--tty' '--rm'
  '--network=host'
  ${PMARGS_PIENV:+"${PMARGS_PIENV[@]}"}
  ${PMARGS_VOLUMES:+"${PMARGS_VOLUMES[@]}"}
  ${PMARGS_PRJVOLUMES:+"${PMARGS_PRJVOLUMES[@]}"}
)

#echo '# debug:' "${C[crt]}" run "${PMARGV[@]}" pi "${@}" >&2
"${C[crt]}" run "${PMARGV[@]}" pi "${@}"
