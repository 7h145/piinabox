# syntax=docker/dockerfile:1
# copyright 2026 <github.attic@typedef.net>, CC BY 4.0

FROM node:current-trixie-slim AS base

ARG TZ="Europe/Berlin"
ENV TZ=${TZ}

RUN true \
  && echo 'debconf debconf/frontend select Noninteractive' |debconf-set-selections \
  && dpkg-reconfigure --frontend noninteractive debconf \
  && apt-get update && apt-get -y upgrade \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    iproute2 \
    procps

# basic tooling
RUN true \
  && apt-get install -y --no-install-recommends \
    curl \
    entr \
    fd-find \
    fzf \
    gh \
    git \
    jq \
    less \
    make \
    man-db \
    pkgconf \
    ripgrep \
    sqlite3 \
    tree \
    yq \
    zip unzip

# additional tooling, YMMV
RUN true \
  && apt-get install -y --no-install-recommends \
    bind9-dnsutils \
    build-essential \
    git-lfs \
    netcat-openbsd \
    openssh-client \
    rsync

# interactive tooling
RUN true \
  && apt-get install -y --no-install-recommends \
    vim

# languages/compilers/interpreters
RUN true \
  && apt-get install -y --no-install-recommends \
    lua5.1 \
    pipx \
    python3 \
    python3-pip \
    python3-venv

# https://docs.astral.sh/uv/
ENV PATH=${PATH}:/root/.local/bin
RUN true \
  && pipx install uv

RUN true \
  && apt-get -y remove --purge --auto-remove && apt-get -y clean \
  && rm -rf /var/lib/apt/lists/*


FROM base AS payload

# invalidate the build cache on payload version change
ARG PAYLOAD="@earendil-works/pi-coding-agent"
ARG PAYLOADVERSION

# see https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/usage.md#environment-variables

# config in $XDG_CONFIG_HOME/pi/agent
ARG PI_CODING_AGENT_DIR="/root/.config/pi/agent"
ENV PI_CODING_AGENT_DIR=${PI_CODING_AGENT_DIR}

# data in $XDG_DATA_HOME/pi/agent
ARG PI_CODING_AGENT_SESSION_DIR="/root/.local/share/pi/agent/sessions"
ENV PI_CODING_AGENT_SESSION_DIR=${PI_CODING_AGENT_SESSION_DIR}

RUN true \
  && mkdir -vp "${PI_CODING_AGENT_DIR}" \
  && mkdir -vp "${PI_CODING_AGENT_SESSION_DIR}"

# there can be only one $EDITOR
ARG EDITOR="vim"
ENV EDITOR=${EDITOR}

ENV WORKDIR="/stage"
WORKDIR $WORKDIR

RUN true \
  && echo "payload: ${PAYLOAD}${PAYLOADVERSION:+@${PAYLOADVERSION}}" \
  && npm install -g "${PAYLOAD}${PAYLOADVERSION:+@${PAYLOADVERSION}}" \
  && npm cache clean --force

ENTRYPOINT [ "/usr/local/bin/pi" ]
#CMD ["--verbose"]

VOLUME $WORKDIR

