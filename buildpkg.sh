#!/bin/bash
# vim

set -euo pipefail

SCRIPTPATH="$( realpath $0 )"

WORKDIR_ROOT=/opt/workdir
PKG_OUT_ROOT=/opt/pkg
STAGE_ROOT=/opt/stage
PREFIX_ROOT=/opt/sw
CACHE_DIR=/opt/cache
PORTS_DIR=${PORTS_DIR:-/opt/ports}

export MAKEFLAGS="-j$(nproc)"
export STRIPPROG="$TARGET-strip"

echo_info() {
	echo -e "\e[34m==>\e[0m \e[1m$@\e[0m" >&2
}
echo_debug() {
	echo -e "\e[2m==> $@\e[0m" >&2
}
echo_warn() {
  echo -e "\e[33m==>\e[0m \e[1m$@\e[0m" >&2
}
echo_error() {
	echo -e "\e[91m==>\e[0m \e[21m$@\e[0m" >&2
}
echo_success() {
	echo -e "\e[92m==>\e[0m \e[1m$@\e[0m" >&2
}

pkg=$1; shift
verbose=false
raw_opts="$@"
remaining_args=()

for arg in "$@"; do
	case $arg in
		--verbose|-v)
			verbose=true
			shift
			;;
		*)
			remaining_args+=($1)
			shift
			;;
	esac
done

if [ ${#remaining_args[@]} -gt 0 ]; then
	echo_warn "Unused arguments: ${remaining_args[*]}"
fi

usage() {
	cat <<-EOF
	Usage: $0 <pkgname>
	EOF
}

[ -z "$pkg" ] && (usage; exit 1)

pkgbuild_file=$PORTS_DIR/$pkg/PKGBUILD

if [ ! -f "$pkgbuild_file" ]; then
	echo_error "Could not find build script for '$pkg' at $pkgbuild_file"
	exit 1
fi

prepare() { return 0; }
check() { return 0; }
depends=()
broken=""

echo_info "Loading $pkgbuild_file"
source $pkgbuild_file

if [ -n "$broken" ]; then
	echo_info "Package is marked as broken. Aborting build. Reason:"
	echo
	echo "$broken" | sed 's/^/    /'
	exit 0
fi

workdir=$WORKDIR_ROOT/$pkgname/$pkgver
pkgpath=$PKG_OUT_ROOT/$pkgname-$pkgver-$TARGET.pkg.tar.gz
pkgprefix=$PREFIX_ROOT/$pkgname/$pkgver
pkgdir=$STAGE_ROOT/$pkgname
pkgcache=$CACHE_DIR/$pkgname

find_dep_path() {
	find $STAGE_ROOT/$1$PREFIX_ROOT/$1 -maxdepth 1 -type d 2>/dev/null | tail -n 1 || :
}

whereis_dep() {
	path=$(find_dep_path $1)
	if [ -z "$path" ]; then
		echo_error "Unable to find path for dependency '$1'"
		return 1
	fi
	echo $path
}

is_dep_installed() {
	[ -n "$(find_dep_path $1)" ] && echo "yes" || echo "no"
}

[ -d $workdir ] && rm -rf $workdir

# always purge the staging dir, otherwise multiple builds of the same package
# could produce unexpected files, such as if you enable or disable features
[ -d $pkgdir ] && rm -rf $pkgdir

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
			echo_debug "Not extracting unknown archive type $1" ;;
	esac
}

verify_source() {
	local sum=""
	local index=$1
	local filename=$2

	echo_debug "Verifying source index=$index filename=$filename"

	for type in sha{1,256,512} md5; do
		local varname=${type}sums
		if [ -v $varname ]; then
			sums="${varname}[@]"
			sums=(${!sums})
			sum=${sums[$index]}
			break
		fi
	done

	if [ -z "$sum" ]; then
		echo_warn "No checksums found"
		return 0
	elif [ "$sum" = "SKIP" ]; then
		echo_info "Skipping validation of $filename"
		return 0
	fi

	echo_info "Verifying $type checksum $sum for $filename"
	echo "$sum  $filename" | ${type}sum --check --quiet
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
		("$@")
	else
		logfile=$(tempfile)
		("$@") >>$logfile 2>&1 || {
			echo "command failed: $@"
			echo "Last lines of log $logfile:"
			echo "--------------------------------------------------"
			echo "... [$(wc -l $logfile | awk '{print $1}') lines]"
			tail -n20 $logfile
			return 1
		}
	fi
}

DEP_CPPFLAGS=()
DEP_LDFLAGS=()

if [ -v depends ]; then
	for dep in "${depends[@]}"; do
		dep_installed=$(is_dep_installed $dep)
		if [ "$dep_installed" == "yes" ]; then
			echo_debug "Dependency '$dep' is already built"
		else
			echo_info "Building dependency '$dep'"
			$SCRIPTPATH $dep $raw_opts
		fi

		# assume the dependency is needed for build time, so add its include and
		# lib dirs to the compiler flags so it can find them
		DEP_CPPFLAGS+=("-I$(whereis_dep $dep)/include")
		DEP_LDFLAGS+=("-L$(whereis_dep $dep)/lib")
	done
fi

for findex in "${!sources[@]}"; do
	source="${sources[$findex]}"
	archive=$(basename "$source")
	archive_path=$pkgcache/$archive
	do_download="yes"

	if [ -f $archive_path ]; then
		verify_source $findex $archive_path && do_download="no" || :
		[ $do_download == "no" ] && echo_info "Using cached file $archive"
	fi

	if [ $do_download == "yes" ]; then
		case "$source" in
			http://*|https://*|ftp://*)
				echo_info "Fetching source $source"
				curl -# -L -o $archive_path "$source"
				;;
			*)
				echo_info "Copying local file $source"
				cp $PORTS_DIR/$pkgname/$source $workdir/.
				;;
		esac

		verify_source $findex $archive_path
	fi

	extract $archive_path
done

echo_info "Preparing"
(quiet_run "prepare")

echo_info "Building"
(
	export CPPFLAGS="${DEP_CPPFLAGS[@]} ${CPPFLAGS-}"
	export LDFLAGS="${DEP_LDFLAGS[@]} ${LDFLAGS-}"

	quiet_run "build"
)

echo_info "Staging install to $pkgdir"
(quiet_run "package")

echo_info "Creating archive $pkgpath"
mk_pkginfo > $pkgdir/.PKGINFO

# the xform arg strips the leading ./ from paths in the archive
tar -czf $pkgpath --xform s:'./':: -C $pkgdir .

echo_success "Built $pkgname!"
echo_success "Done"
