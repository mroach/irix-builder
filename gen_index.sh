#!/bin/bash

for f in pkg/*pkg.tar.gz; do
  pkgfile=$(basename $f)
  barepkgname=$(basename $pkgfile .pkg.tar.gz)
  parts=(${barepkgname//-/ })

  ix_version=${#parts[@]}-4
  pkgver="${parts[$ix_version]}"
  pkgname=$(echo "${parts[@]:0:$ix_version}" | sed 's/ /-/')

  sha1=$(shasum -a1 $f | awk '{print $1}')

  echo "$pkgname,$pkgver,$pkgfile,$sha1"
done
