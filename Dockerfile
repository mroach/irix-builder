FROM debian:buster-slim AS builder-base

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential \
      bison \
      flex \
      automake \
      libgmp-dev \
      libmpfr-dev \
      libmpc-dev \
      texinfo  \
      gettext \
      curl \
      ca-certificates && \
    apt-get clean

WORKDIR /opt

ENV TARGET=mips-sgi-irix6.5 \
    SYSROOT=/opt/irix-root \
    X11_ROOT=/opt/motif

RUN mkdir -p /opt/src \
             /opt/src/gcc-build \
             /opt/gcc/$TARGET \
             $SYSROOT \
             /opt/src/binutils

ARG IRIX_VER=6.5.30
ARG IRIX_ROOT_URL=http://dl.mroach.com/irix/buildtools/irix-root.${IRIX_VER}.tar.xz
ARG IRIX_ROOT_SHA256=424bff47951dcdc0552495c56acff48b7bf1c40c493133896cfd9891021d6a56
RUN archive=$(basename $IRIX_ROOT_URL); \
    curl -LO $IRIX_ROOT_URL && \
    echo "$IRIX_ROOT_SHA256  $archive" | shasum -a256 -c && \
    tar xf $archive -C $SYSROOT && \
    rm $archive

# Having motif allows us to build GUI apps
ARG MOTIF_URL=http://dl.mroach.com/irix/buildtools/motif-2.1.tar.xz
ARG MOTIF_SHA256=5828d7180dc668f1ded9addef620bdc06e2c561f74c379fec838f1c9bc3da40f
RUN archive=$(basename $MOTIF_URL); \
    curl -LO $MOTIF_URL && \
    echo "$MOTIF_SHA256  $archive" | shasum -a256 -c && \
    tar xf $archive && \
    rm $archive && \
    mv Motif-2.1 /opt/motif

#ARG BINUTILS_URL=http://ftpmirror.gnu.org/gnu/binutils/binutils-2.17a.tar.bz2
#ARG BINUTILS_SHA256=b8b6363121a99aaf0309d0a6f63a18c203ddbb34f53683c9a56d568be2b6a549
ARG BINUTILS_VER=2.33.1
ARG BINUTILS_URL=http://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VER}.tar.xz
ARG BINUTILS_SHA256=ab66fc2d1c3ec0359b8e08843c9f33b63e8707efdff5e4cc5c200eae24722cbf
RUN archive=$(basename $BINUTILS_URL); \
    curl -LO $BINUTILS_URL && \
    echo "$BINUTILS_SHA256  $archive" | shasum -a256 -c && \
    tar xf $archive -C /opt/src/binutils && \
    rm $archive && \
    cd /opt/src/binutils/binutils-${BINUTILS_VER} && \
    ./configure --target=$TARGET \
                --prefix=/opt/binutils \
                --with-sysroot=$SYSROOT \
                --enable-werror=no && \
    make && make install && make clean && \
    rm -rf /opt/src/binutils

ARG GCC_URL=http://dl.mroach.com/irix/buildtools/gcc-4.7-irix.tar.xz
ARG GCC_SHA256=daa730e1ad14ea10728dfbbfa59a7bb3075005f3dcc25d755b053fdec4daaa01
RUN archive=$(basename $GCC_URL); \
    curl -LO $GCC_URL && \
    echo "$GCC_SHA256  $archive" | shasum -a256 -c && \
    tar xf $archive && \
    rm $archive && \
    mv gcc-4.7-irix /opt/src/gcc

RUN ln -s $SYSROOT/usr/include /opt/gcc/$TARGET/sys-include && \
    ln -s $SYSROOT/usr/lib32 /usr/lib32

COPY files/stdlib_core.h /opt/gcc/$TARGET/sys-include/internal/
COPY files/gcc.texi /opt/src/gcc/gcc/doc/

RUN export AS_FOR_TARGET="$TARGET-as" \
           LD_FOR_TARGET="$TARGET-ld" \
           NM_FOR_TARGET="$TARGET-nm" \
           OBJDUMP_FOR_TARGET="$TARGET-objdump" \
           RANLIB_FOR_TARGET="$TARGET-ranlib" \
           STRIP_FOR_TARGET="$TARGET-strip" \
           READELF_FOR_TARGET="$TARGET-readelf" \
           target_configargs="--enable-libstdcxx-threads=no" \
           PATH=/opt/binutils/bin:$PATH && \
    env && \
    cd /opt/src/gcc-build && \
    /opt/src/gcc/configure --enable-obsolete \
                           --disable-multilib \
                           --prefix=/opt/gcc \
                           --with-build-sysroot=$SYSROOT \
                           --target=$TARGET \
                           --disable-nls \
                           --enable-languages=c,c++ && \
    make -j $(nproc) && make install && \
    rm -rf /opt/gcc/$TARGET

RUN mkdir /opt/gcc/$TARGET && \
    ln -s /opt/binutils/$TARGET/bin /opt/gcc/$TARGET/bin && \
    ln -s $SYSROOT/usr/include /opt/gcc/$TARGET/sys-include && \
    cp /opt/src/gcc-build/$TARGET/libgcc/libgcc_s.so* \
        /opt/gcc/lib/gcc/$TARGET/4.7.4/. && \
    cp /opt/src/gcc-build/$TARGET/libgcc/libgcc_s.so* \
        $SYSROOT/lib32/. && \
    cp /opt/src/gcc-build/$TARGET/libstdc++-v3/src/.libs/libstdc++.so* \
       /opt/gcc/lib/gcc/$TARGET/4.7.4/. && \
    cp /opt/src/gcc-build/$TARGET/libstdc++-v3/src/.libs/libstdc++.a \
       /opt/gcc/lib/gcc/$TARGET/4.7.4/.

# Apply patches that should be available to every build
COPY patches/mman_map_anon.patch .
RUN patch -d/ -p0 < mman_map_anon.patch && \
    rm mman_map_anon.patch

# Install package that some packages need for for building. Adding them here
# rather than the top of the file reduces image rebuild time as we add tools.
RUN apt-get install -y --no-install-recommends \
      libtool \
      python2 \
      unzip \
      sqlite3 \
      autoconf

RUN mkdir -p /opt/pkg \
             /opt/cache \
             /opt/bin

COPY buildpkg.sh /opt/bin/buildpkg
COPY gen_index.sh /opt/bin/gen_index

ENV PATH=/opt/binutils/bin:/opt/gcc/bin:/opt/bin:$PATH \
    AR="$TARGET-ar" \
    AS="$TARGET-as" \
    CC="$TARGET-gcc" \
    CXX="$TARGET-g++" \
    RANLIB="$TARGET-ranlib" \
    STRIP="$TARGET-strip" \
    LD="$TARGET-ld" \
    CFLAGS="-B/opt/binutils/bin/$TARGET- --sysroot=$SYSROOT" \
    CXXFLAGS="-B/opt/binutils/bin/$TARGET- --sysroot=$SYSROOT"

ENV TARGET_PREFIX=$PREFIX/$TARGET

FROM builder-base AS builder-dev

RUN apt-get install -y --no-install-recommends \
      ripgrep \
      less \
      procps \
      vim && \
    apt-get clean

CMD ["bash"]
