#!/bin/bash

set -ex

name=curl
version=7.66.0
src_url=https://curl.haxx.se/download/curl-$version.tar.bz2
sha256=6618234e0235c420a21f4cb4c2dd0badde76e6139668739085a70c4e2fe7a141
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

./configure --prefix=$prefix --host=$TARGET --with-ssl=$prefix_root/openssl --without-libpsl --disable-threaded-resolver  && \
    make -j$(nproc)


make install

cd $workdir
mkdir package
cd package

cp -r $prefix .

cat <<EOF | tee MANIFEST
name: $name
version: $version
comment: curl
arch: $arch
prefix: $prefix
www: https://curl.haxx.se
licenses: [GPLv3]
flatsize: $(du -s $prefix)
EOF

tar cf /opt/pkg/$name-$version-$arch.tar .
