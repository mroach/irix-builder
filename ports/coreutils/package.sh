#!/bin/bash

set -ex

name=coreutils
version=8.31
src_url=http://ftp.gnu.org/gnu/coreutils/coreutils-$version.tar.xz
sha256=ff7a9c918edce6b4f4b2725e3f9b37b0c4d193531cac49a48b56c4d0d3a9e9fd
workdir=/opt/build/$name
src_file=$(basename "$src_url")
prefix_root=/opt/local
prefix=$prefix_root/$name
arch=mips

mkdir -p $workdir
cd $workdir

curl -LO $src_url && \
  echo "$sha256  $src_file" | shasum  -a256 -c && \
  tar xf $src_file && \
  rm $src_file

cd $name-$version

./configure --prefix=$prefix --host=$TARGET && \
    make -j$(nproc)


make install

cd $workdir
mkdir package
cd package

cp -r $prefix .

cat <<EOF | tee MANIFEST
name: $name
version: $version
comment: GNU Coreutils
arch: $arch
prefix: $prefix
www: https://www.gnu.org/software/coreutils/
licenses: [GPLv3]
flatsize: $(du -s $prefix)
EOF

tar cf /opt/pkg/$name-$version-$arch.tar .
