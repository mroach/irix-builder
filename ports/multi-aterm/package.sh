#!/bin/bash

set -ex

name=multi-aterm
version=0.2.1
src_url=http://www.nongnu.org/materm/multi-aterm-0.2.1.tar.gz
sha256=de12604e29dabd0157ce061c785b482ad8c9721027ec31f60609dc9f647bd5fb
workdir=/opt/build/$name
src_file=$(basename "$src_url")
prefix_root=/opt/local
prefix=$prefix_root/$name
arch=mips

test -d $workdir && rm -rf $workdir
mkdir -p $workdir
cd $workdir

curl -LO $src_url && \
  echo "$sha256  $src_file" | shasum  -a256 -c && \
  tar xf $src_file && \
  rm $src_file

cd $name-$version

# comment-out aborts caused by cross-compiling checks
sed -i'' '3529,3535 {s/^/#/};3541 {s/^/#/}' configure
sed -i'' '7684,7688 {s/^/#/};7733 {s/^/#/}' configure

./configure --prefix=$prefix --host=$TARGET --with-xpm=/opt/src/Motif-2.1
make -j$(nproc)
make install

cd $workdir
mkdir package
cd package

cp -r $prefix .

cat <<EOF | tee MANIFEST
name: $name
version: $version
comment: multi-aterm
arch: $arch
prefix: $prefix
www: http://www.nongnu.org/materm/materm.html
licenses: []
flatsize: $(du -s $prefix)
EOF

tar cf /opt/pkg/$name-$version-$arch.tar .
