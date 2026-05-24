# Pi in a Box

This is about running the [pi coding agent](https://pi.dev/) ([GitHub](https://github.com/earendil-works/pi/tree/main/packages/coding-agent), [npm](https://www.npmjs.com/package/@earendil-works/pi-coding-agent)) in an isolated containerized environment.  This is a sibling of [OpenCode in a Box](https://github.com/7h145/ocinabox), just barely different enough to justifiy it's own project as time of writing.  See [Opinions](#opinions) below if you want my rational why this exists.

These days, coding and general-purpose AI agents do things on your computer. While I appreciate the help, I have serious trust issues with someone or something other than me having access to my system and, in turn, to my data.

This issue is only partially alleviated by the fact that many agents use some internal mechanism to limit access to certain parts of the system running the agent (because I don't trust these either).  On the other hand, such agents need access to some of your data in order to be helpful, e.g. a bunch of files or the git repository of the project you are working on.

There are several ways to address this problem, typically involving physically separate systems, virtual machines, or containers.  This project is about the [pi agent](https://pi.dev/) agent running in a container with selective access to just the data you allow it to see, for example:

    piinabox.sh ~/myprojects/thisproject ~/myprojects/thatfile

This will spawn a containerized `pi` agent with just the specified files or directories from the host visible inside the container.

Security note: This is a containerized setup, but not magic.  Anything you mount into the container is visible to code running there, and it uses the host network namespace (`--network=host`) by default.  Only mount what you actually want to share, use `:ro` where possible.

## Just a container and a `pi` stand-in script

This project comes in two parts: the container with `pi` and some tooling inside, and a script for running the containerized `pi` executable with some of the host files or directories mounted inside the container for the agent to work with.

### The Pi container

A [Containerfile](Containerfile) and a small [build script](build.sh) build a [Debian trixie](https://www.debian.org/releases/trixie/) based [Node.js](https://nodejs.org/) runtime environment with the [pi-coding-agent npm package](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) and a somewhat sane set of tools for the agent pre-installed (but YMMV).

You can easily adjust the tooling in the container image for your needs (by editing the Containerfile and running `build.sh` again) or even let the agent itself install new tools at runtime (but be aware that the containers are not persistent by default).

Running the `build.sh` build script will build (or re-build) the container image, using the [latest version of the pi coding agent](https://github.com/earendil-works/pi/releases) by default.  This is fairly efficient due to the layer caching of your container runtime. To update to the latest version, run `build.sh` and restart your agents.

Tip: to rebuild the image from scratch using a fresh base image, run:

    build.sh --no-cache --pull=always

### The `pi` stand-in script

The [`piinabox.sh` script](piinabox.sh) is the containerized stand-in for the usual `pi` command. It does the same basic thing as plain `pi`, but in its own container and with one extra feature: it allows you to specify which files or directories should be visible inside the container for the agent to work on. The wrapper script takes arguments of the form

    piinabox.sh [SOURCE-VOLUME|HOST-DIR[:OPTIONS]...] [PI-ARGV...]

Each leading argument is treated like a `podman run --volume` argument without the usual `:CONTAINER-DIR` part.  You can mount arbitrary files and directories in the `$PWD` of the `pi` process running in the container, i.e. the container's `WORKDIR`, this way.

* Files are always mounted directly into `WORKDIR`, e.g.

      piinabox.sh ~/some/file/myfile:ro

  leads to the read-only file `WORKDIR/myfile` in the container.

* Directories are always mounted as subdirectories of `WORKDIR`, e.g.

      piinabox.sh ~/some/directory/mydirectory

  leads to the directory `WORKDIR/mydirectory` in the container.

* Special case `$PWD`: if the specified directory happens to be the current `$PWD` (e.g. `.`), it is mounted directly in `WORKDIR`, e.g.

      cd ~/projects/myproject; piinabox.sh .

  leads to the contents of `~/projects/myproject` directly visible in `WORKDIR`.

You can of course freely mix and match, e.g.

    cd ~/projects/this; piinabox.sh . ~/projects/that:ro ~/some/file:ro

will mount `~/projects/this` (i.e. `$PWD`) in `WORKDIR`, `~/projects/that` read-only in `WORKDIR/that`, and the file `~/some/file` in `WORKDIR/file`.

Further command line arguments are passed through to `pi` after the leading mount specifications, e.g.

    piinabox.sh .:ro run 'explain this codebase'

## Notes

One advertised use case of `pi` is its ability to modify itself by writing an extension into its configuration directory and then using `/reload` to load the new code.  A read-only host configuration is safest but breaks such use cases; the default is to mount read/write.

## The Container Runtime

This thing is developed with [rootless](https://rootlesscontaine.rs/) [Podman](https://github.com/containers/podman/) in mind. [`build.sh`](build.sh) and [`piinabox.sh`](piinabox.sh) use Podman as the default high-level container runtime, but nothing really special happens here; any "docker lookalike" container runtime should do, e.g. [Docker](https://github.com/docker).

Both scripts are already set up to switch the container runtime from `podman` to `docker`; it's a matter of changing two comments in each file (search for `docker`).

You should really use [rootless](https://rootlesscontaine.rs/) containers, not only but especially if you care for adversarial isolation (which is the point in this case), but it will of course run rootful just fine.

## Opinions

After a couple of hours of familiarization, I switched to `pi` without even noticing, by just not starting my venerable [OpenCode](https://opencode.ai/) anymore.  I could try to elaborate, but I think [Mario](https://mariozechner.at/) does a better job:
* https://mariozechner.at/posts/2025-11-30-pi-coding-agent/
* https://mariozechner.at/posts/2026-03-25-thoughts-on-slowing-the-fuck-down/

In addition, ["How to Build an Agent" by Thorsten Ball on ampcode.com](https://ampcode.com/notes/how-to-build-an-agent) is worth a read to get some perspective on what the software we are talking about is at its core.

