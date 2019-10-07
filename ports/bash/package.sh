#!/bin/bash

set -ex

name=bash
version=5.0
src_url=http://ftpmirror.gnu.org/gnu/bash/bash-$version.tar.gz
sha256=b4a80f2ac66170b2913efbfb9f2594f1f76c7b1afd11f799e22035d63077fb4d
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

# Remove loadables that don't compile
# fdflags: uses O_CLOEXEC which is not defined
# seq: uses PRIdMAX which is not defined
# push: something
sed -i -r '/^ALLPROG =/,/^OTHERPROG/ s/\bfdflags\b//;s/\bpush\b//;s/\bseq\b//' \
    examples/loadables/Makefile

make install

cd $workdir
mkdir package
cd package

cp -r $prefix .

cat <<EOF | tee MANIFEST
name: $name
version: $version
comment: Bourne Again Shell
arch: $arch
prefix: $prefix
www: https://tiswww.case.edu/php/chet/bash/bashtop.html
licenses: [GPLv3]
flatsize: $(du -s $prefix)
EOF

tar cf /opt/pkg/$name-$version-$arch.tar .
