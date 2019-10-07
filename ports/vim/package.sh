#!/bin/bash

set -ex

name=vim
version=8.1.2118
src_url=https://github.com/vim/vim/archive/v$version.tar.gz
sha256=ad862642452dd32ff8290019fbe559c6108dadfab602a96a6568070fe7cb61e6
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

./configure --prefix=$prefix --host=$TARGET --with-features=huge
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
www: https://www.vim.org
licenses: [vim]
flatsize: $(du -s $prefix)
EOF

tar cf /opt/pkg/$name-$version-$arch.tar .
