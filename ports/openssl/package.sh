#!/bin/bash

set -ex

name=openssl
version=1.0.2t
src_url=https://www.openssl.org/source/openssl-$version.tar.gz
sha256=14cb464efe7ac6b54799b34456bd69558a749a4931ecfd9cf9f71d7881cac7bc
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

./Configure irix-mips3-gcc shared --prefix=$prefix && \
    make -j$(nproc)

make install

cd $workdir
mkdir package
cd package

cp -r $prefix .

cat <<EOF | tee MANIFEST
name: $name
version: $version
comment: $name
arch: $arch
prefix: $prefix
www: https://www.openssl.org
licenses: [Apache]
flatsize: $(du -s $prefix)
EOF

tar cf /opt/pkg/$name-$version-$arch.tar .
