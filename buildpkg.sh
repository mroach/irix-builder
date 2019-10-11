#!/bin/bash
# vim

set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
WORKDIR_ROOT=/opt/workdir
PKG_OUT_ROOT=/opt/pkg
STAGE_ROOT=/opt/stage
CACHE_DIR=/opt/cache
PORTS_DIR=${PORTS_DIR:-/opt/ports}

export MAKEFLAGS="-j$(nproc)"
export STRIPPROG="$TARGET-strip"

pkg=$1; shift
clean=false
verbose=false

for arg in "$@"; do
	case $arg in
		--clean)
			clean=true
			shift ;;
		--verbose|-v)
			verbose=true
			shift ;;
		*)
			echo "Discarded arguments: $@" ;;
	esac
done

usage() {
	cat <<-EOF
	Usage: $0 <pkgname>
	EOF
}

echo_info() {
	echo -e "\e[34m==>\e[0m \e[1m$@\e[0m"
}
echo_debug() {
	echo -e "\e[2m==> $@\e[0m"
}
echo_error() {
	echo -e "\e[91m==>\e[0m \e[21m$@\e[0m"
}

[ -z "$pkg" ] && (usage; exit 1)

pkginfo_path=$PORTS_DIR/$pkg/PKGINFO

if [ ! -f "$pkginfo_path" ]; then
	cat <<-EOF
		Could not find build script for '$pkg'
		Looked for: $pkginfo_path
	EOF
	exit 1
fi

prepare() { return 0; }
check() { return 0; }
depends=()

echo_info "Loading $pkginfo_path"
source $pkginfo_path

workdir=$WORKDIR_ROOT/$pkgname/$pkgver
pkgdir=$STAGE_ROOT/$pkgname/$pkgver
pkgpath=$PKG_OUT_ROOT/$pkgname-$pkgver-$TARGET.pkg.tar.gz
pkgcache=$CACHE_DIR/$pkgname

whereis_dep() {
	path=$(find $STAGE_ROOT/$1 -maxdepth 1 -type d | tail -n 1)
	if [ -z "$path" ]; then
		echo_error "Unable to find path for dependency '$1'"
		return 1
	fi
	echo $path
}

if [ "$clean" = true ]; then
	echo_info "Cleaning $workdir and $pkgdir"
	[ -d $workdir ] && rm -rf $workdir
	[ -d $pkgdir ] && rm -rf $pkgdir
fi

[ -d $workdir ] || mkdir -p $workdir
[ -d $pkgdir ] || mkdir -p $pkgdir
[ -d $pkgcache ] || mkdir -p $pkgcache

cd $workdir
echo_debug "Working in $workdir"

extract() {
	case "$1" in
		*.tar|*.tar.gz|*tar.bz2|*.tar.xz)
			tar xf $1 ;;
		*.zip)
			unzip $1 ;;
		*)
			echo_error "Don't know how to extract $1"
			return 1 ;;
	esac
}

verify_source() {
	local sum=""
	local filename=$2
	if [ -v sha512sums ]; then
		sum="${sha512sums[$1]}"
		echo_debug "Verifying SHA-512 checksum $sum for $filename"
		echo "$sum  $filename" | shasum -a512 -c
	elif [ -v sha256sums ]; then
		sum="${sha256sums[$1]}"
		echo_debug "Verifying SHA-256 checksum $sum for $filename"
		echo "$sum  $filename" | shasum -a256 -c
	elif [ -v sha1sums ]; then
		sum="${sha1sums[$1]}"
		echo_debug "Verifying SHA-1 checksum $sum for $filename"
		echo "$sum  $filename" | shasum -a1 -c
	elif [ -v md5sums ]; then
		sum="${md5sums[$1]}"
		echo_debug "Verifying MD5 checksum $sum for $filename"
		echo "$sum  $filename" | md5sum -c
	else
		echo_error "No checksums defined?"
		return 1
	fi
}

stage_size() {
	du -sb $pkgdir | awk '{print $1}'
}

mk_pkginfo() {
	cat <<-EOF
	pkgname = $pkgname
	pkgver = $pkgver
	pkgdesc = $pkgdesc
	url = $url
	builddate = $(date +%s)
	size = $(stage_size)
	packager = $0
	arch = $TARGET
	EOF
	for f in "${depends[@]}"; do
		echo "depend = $f";
	done
}

quiet_run() {
	if [ "$verbose" = true ]; then
		"$@"
	else
		logfile=$(tempfile)
		"$@" >>$logfile 2>&1 || {
			echo "command failed: $@"
			echo "Last lines of log $logfile:"
			echo "--------------------------------------------------"
			echo "... [$(wc -l $logfile | awk '{print $1}') lines]"
			tail -n10 $logfile
			return 1
		}
	fi
}

for findex in "${!sources[@]}"; do
	url="${sources[$findex]}"
	archive=$(basename "$url")
	archive_path=$pkgcache/$archive
	do_download="yes"

	if [ -f $archive_path ]; then
		verify_source $findex $archive_path && do_download="no" || :
		[ $do_download == "no" ] && echo_info "Using cached file $archive"
	fi

	if [ $do_download == "yes" ]; then
		echo_info "Fetching source $url"
		curl -# -L -o $archive_path "$url"
		verify_source $findex $archive_path
	fi

	extract $archive_path
done

echo_info "Preparing"
quiet_run "prepare"; cd $workdir

echo_info "Building"
quiet_run "build"; cd $workdir

echo_info "Staging install to $pkgdir"
quiet_run "package"; cd $workdir

echo_info "Creating archive $pkgpath"
mk_pkginfo > $pkgdir/.PKGINFO

# the xform arg strips the leading ./ from paths in the archive
tar -czf $pkgpath --xform s:'./':: -C $pkgdir .

echo_info "Done!"
