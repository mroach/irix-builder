# IRIX Builder and IRIX Package Manager (ipm)

This project aims to cross-compile software for IRIX and create packages
that can easily be installed on an IRIX workstation with a simple package manager.

## Up and running

### ipm on IRIX

This is the package manager to install pre-built binary packages.

Download `bootstrap.sh` to your machine. NFS, FTP, SCP, SFTP. There are ways.

```
su
chmod +x bootstrap.sh
./bootstrap.sh
```

The bootstrapper will setup the `/opt` hierarchies (see the *philosophy* section)
and install `curl` which is required for fetching packages.

Now you can start installing packages as root. For example:

```
/opt/bin/ipm install bash
/opt/bin/ipm install coreutils
```

To use binaries and `man` pages installed with ipm, you'll want to add these
to your environment config, such as appending to `.profile` or `.bash_profile`

```
PATH=$PATH:/opt/bin:/opt/local/bin
MANPATH=${MANPATH-}:/opt/local/share/man
```

### Builder

The builder is Dockerized, so the only requirement is that you have [Docker]
installed and working.

First, you'll need to build an image.

```shell
git clone https://github.com/mroach/irix-builder
cd irix-builder
docker build --target builder-dev -t irix-builder-dev .
```

It may take a while as it needs to build `gcc` from source.

```shell
docker run --rm -it \
       -v $PWD/ports:/opt/ports \
       -v $PWD/buildpkg.sh:/opt/bin/buildpkg \
       -v $PWD/pkg:/opt/pkg \
       irix-builder-dev bash
```

Once it's built, you're ready to use it. The command above will make three
mounts into the container:

* `/opt/ports`
* `/opt/bin/buildpkg`
* `/opt/pkg`

These mounts allow you to edit ports and `buildpkg.sh` on your system and have
them reflected in the container straight away. And when packages are built,
they will show up in `./pkg` locally.

Once you're at a shell, you can start building packages:

```shell
buildpkg curl
```

#### Testing ipm

It's a good idea to test changes to `bootstrap.sh` and `ipm.sh` before pushing
to a mirror. For that, use the `Dockerfile.ipmtest` image. It tries to
approximate an IRIX system.

> TODO: Install older versions of Perl, sh, openssl to be closer to IRIX

```shell
docker build -t test-server -f Dockerfile.ipmtest .

docker run --rm -it -v $PWD/pkg:/var/www/html/irix/pkg \
                    -v $PWD/ipm.sh:/var/www/html/irix/ipm.sh \
                    -v $PWD/bootstrap.sh:/root/bootstrap.sh \
                    test-server bash
```

Example of testing out a self-update and installing a package:

```shell
service nginx start

./bootstrap.sh
/opt/bin/ipm self-update
/opt/bin/ipm install bash
```

## ipm philosophy

ipm aims to be simple and non-destructive to your IRIX OS. Installing software
directly into the root file system could alter the behaviour of the OS and
destabilise the system. For example, replacing libraries and software with GNU
tools that have different behaviour is probably not a good idea.

The [Homebrew] package manager for macOS faces a similar challenge. Adding
software to the existing OS without causing nasty side effects. ipm follows
the patterns of Homebrew to aim for a non-destructive addition to your OS.

### Technical implementation

`/opt` is the root of ipm. Everything happens in there. It does not touch any
other part of IRIX.

`/opt/sw` is the installation directory for packages. Within there, packages
are installed with their name and version as prefix. For example, you would
find the `curl` binary in `/opt/sw/curl/7.66.0/bin/curl`

`/opt/local` acts as root for the "normal" hierarchy of software. Symlinks are
made here to the instals in `/opt/sw`. For example, if you looked in
`/opt/local/bin` you would see:

```
bash => /opt/sw/bash/5.0/bin/bash
curl => /opt/sw/curl/7.66.0/bin/curl
```

The same pattern repeats for the usual suspects: `etc`, `lib`, `share`, `var`
and some others.

To use the binaries, it's recommend to add `/opt/local/bin` to the *end* of your
`PATH`. If you install `coreutils` for example you will be overriding a lot of
standard IRIX binaries such as `chown`, `kill`, and even `[`.

## Credit

First and foremost, huge credit goes to [unxmaal] and his [compilertron]
which set me on the path to cross-compiling. The `Dockerfile` is pretty
much a translation of his work into Docker.

The build scripts at [irixports] were a help in understanding some of the
oddities when compiling modern software for IRIX.

[compilertron]: https://github.com/unxmaal/compilertron
[unxmaal]: https://github.com/unxmaal
[irixports]: https://github.com/larb0b/irixports
[Docker]: https://www.docker.com
[Homebrew]: https://brew.sh
