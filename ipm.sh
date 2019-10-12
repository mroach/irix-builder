#!/usr/bin/env sh

set -eu

PKG_CACHE_DIR=/var/cache/ipm
INSTALL_DIR=/opt/sw
INSTALLED_FILE=$INSTALL_DIR/installed.list
WORKDIR_ROOT=/var/ipm/work

LINK_LOCAL_DIR=/opt/local
LINK_LIB_DIR=/opt/lib32

echo_debug() {
  [ "${verbose:-no}" = "no" ] && return 0
  echo "\033[2m==> $@\033[0m" >&2
}
echo_info() {
  echo "\033[34m==>\033[0m \033[1m$@\033[0m" >&2
}
echo_warn() {
  echo "\033[33m==>\033[0m \033[1m$@\033[0m" >&2
}
echo_error() {
  echo "\033[91m==>\033[0m \033[21m$@\033[0m" >&2
}
echo_success() {
  echo "\033[92m==>\033[0m \033[1m$@\033[0m" >&2
}

ensure_env() {
  for d in $PKG_CACHE_DIR $WORKDIR_ROOT $LINK_LOCAL_DIR $INSTALL_DIR; do
    if [ ! -d $d ]; then
      echo_info "Creating $d"
      mkdir -p $d
    fi
  done

  [ -f $INSTALLED_FILE ] || touch $INSTALLED_FILE
}

fetch() {
  pkgname=$1
  pkgfile=`grep "^$pkgname," /opt/var/ipm/index.csv | cut -d, -f3`

  if [ -z "$pkgfile" ]; then
    echo_error "Could not find package '$pkgname' in the index"
    return 1
  fi

  cachefile=$PKG_CACHE_DIR/$pkgfile

  if [ -f $cachefile ]; then
    echo_info "Using cached file"
  else
    url=http://dl.mroach.com/irix/pkg/$pkgfile
    echo_info "Fetching $url"
    /opt/local/bin/curl -# -o $cachefile $url
  fi

  echo $cachefile
}

get_pkg_var() {
  (grep "^$1" .PKGINFO | cut -d= -f2 | awk '{$1=$1;print}') || :
}

mark_as_installed() {
  echo "$1,$2" >> $INSTALLED_FILE
}

installed_pkg_ver() {
  grep "^$1," $INSTALLED_FILE | tail -n1 | cut -d, -f2
}

link() {
  pkgname=$1
  pkgver=`installed_pkg_ver $pkgname`
  quiet="no"

  if [ -z "$pkgver" ]; then
    echo_error "Package '$pkgname' is not installed"
    return 1
  fi

  for arg in "$@"; do
    case $arg in
      --quiet|-q)
        quiet="yes"
        shift ;;
      *)
        echo_debug "Discarded arguments $@"
    esac
  done

  pkgdir=$INSTALL_DIR/$pkgname/$pkgver

  echo_debug "Looking for libraries in $pkgdir/lib"

  if [ -d $pkgdir/lib ]; then
    echo_info "Linking lib files into $LINK_LIB_DIR"

    find $pkgdir/lib -type f | while read f; do
      stub=${f#"$pkgdir/lib/"}
      source=$f
      target=$LINK_LIB_DIR/$stub
      if [ -e $target ]; then
        echo_debug "Link already exists $target; skipping."
      else
        dir=`dirname $target`
        if [ ! -d $dir ]; then
          echo_debug "Creating $dir"
          mkdir -p $dir
        fi
        echo_debug "Linking $source => $target"
        ln -s $source $target
      fi
    done
  fi

  for topdir in bin etc run libexec sbin share var; do
    if [ -d $pkgdir/$topdir ]; then
      echo_info "Linking $topdir files into $LINK_LOCAL_DIR/$topdir"

      find $pkgdir/$topdir -type f | while read f; do
        stub=${f#"$pkgdir/"}
        source=$f
        target=$LINK_LOCAL_DIR/$stub
        if [ -e $target ]; then
          echo_debug "link already exists $target"
        else
          dir=`dirname $target`
          if [ ! -d $dir ]; then
            echo_debug "Creating $dir"
            mkdir -p $dir
          fi
          echo_debug "Linking $source => $target"
          ln -s $source $target
        fi
      done
    fi
  done

  echo_success "Done linking $pkgname $pkgver"
}

unlink() {
  pkgname=$1
  pkgdir=$INSTALL_DIR/$pkgname

  (find $LINK_LOCAL_DIR $LINK_LIB_DIR -type l || :) | while read link; do
    # TODO: no readlink on irix
    target=`readlink -f "$link"`
    case $target in
      $pkgdir/*)
        echo_info "Removing link $link => $target"
        rm $link
        ;;
      *)
        ;;
    esac
  done

  echo_success "Done unlinking $pkgname"
}

uninstall() {
  pkgname=$1
  pkgver=`installed_pkg_ver $pkgname`

  if [[ -z "$pkgver" && "$force" = "no" ]]; then
    echo_error "$pkgname doesn't appear to be installed"
    exit 1
  fi

  unlink $pkgname

  echo_info "Removing $INSTALL_DIR/$pkgname"
  rm -rf $INSTALL_DIR/$pkgname

  grep -v "^$pkgname," $INSTALLED_FILE > $INSTALLED_FILE.new
  mv $INSTALLED_FILE.new $INSTALLED_FILE

  echo_success "Uninstalled $pkgname"
}

install() {
  pkgname=$1
  pkgpath=`fetch $pkgname`
  workdir=$WORKDIR_ROOT/$pkgname
  installed_ver=`installed_pkg_ver $pkgname`

  if [ -n "$installed_ver" ] && [ "$force" = "no" ]; then
    echo_debug "installed_ver=$installed_ver force=$force"
    echo_warn "$pkgname is already installed"
    return 0
  fi

  echo_info "Installing $pkgname"

  [ -d $workdir ] || mkdir $workdir
  cd $workdir

  echo_info "Unpacking $pkgpath in $PWD"

  gzcat $pkgpath | tar -xf -

  pkgver=`get_pkg_var pkgver`
  echo_debug "Found version $pkgver"

  depends=`get_pkg_var depend`
  if [ -n "$depends" ]; then
    for dep in $depends; do
      echo_info "Resolving dependency $dep"
      (install $dep)
    done
  fi

  mv opt/sw/$pkgname /opt/sw/
  mark_as_installed $pkgname $pkgver
  link $pkgname --quiet
  echo_success "Installed $pkgname $pkgver"
}

usage() {
cat <<EOF
usage: ipm <command> [args]

commands:
  install <pkgname>        install a package and its dependencies
  fetch <pkgname>          only fetch a package tarball
  link <pkgname>           find files provided by the package and link into common dirs
  doctor                   ensure the environment is ok (dirs exist, etc)
  installed-ver <pkgname>  get info about installed package
EOF
}

if [ -z "${*-}" ]; then
  usage
  exit 1
fi

ensure_env
command=$1; shift
verbose="no"
force="no"

for arg in "${@-}"; do
  case $arg in
    "--verbose")
      verbose="yes"
      ;;
    "--force")
      force="yes"
      ;;
    *)
      ;;
  esac
done

cd $WORKDIR_ROOT

case "$command" in
  help|--help)
    usage
    ;;
  fetch)
    fetch $1
    ;;
  install)
    pkgname=$1; shift
    install $pkgname
    ;;
  uninstall)
    pkgname=$1; shift
    uninstall $pkgname
    ;;
  link)
    link $1
    ;;
  unlink)
    unlink $1
    ;;
  doctor)
    ensure_env
    echo_success "Done"
    ;;
  show-installed)
    installed_pkg_ver $1 ;;
  *)
    echo "Invalid command '$command'"
    exit 1
esac
