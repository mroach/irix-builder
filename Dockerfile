FROM debian:buster-slim AS builder-base

ARG IRIX_VER=6.5.30
ARG GCC_URL=http://dl.mroach.com/irix/buildtools/gcc-4.7-irix.tar.xz
ARG IRIX_ROOT_URL=http://dl.mroach.com/irix/buildtools/irix-root.${IRIX_VER}.tar.xz
ARG BINUTILS_URL=http://dl.mroach.com/irix/buildtools/binutils-2.17a.tar.xz
ARG MOTIF_URL=http://dl.mroach.com/irix/buildtools/motif-2.1.tar.xz

ARG GCC_SHA256=daa730e1ad14ea10728dfbbfa59a7bb3075005f3dcc25d755b053fdec4daaa01
ARG IRIX_ROOT_SHA256=424bff47951dcdc0552495c56acff48b7bf1c40c493133896cfd9891021d6a56
ARG BINUTILS_SHA256=e4be18fec00212f187c4423088faf4fe99aee87f040068f4c1fe75b7176adc46
ARG MOTIF_SHA256=5828d7180dc668f1ded9addef620bdc06e2c561f74c379fec838f1c9bc3da40f

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
      autoconf \
      gettext \
      curl \
      ca-certificates && \
    apt-get clean

WORKDIR /opt

RUN mkdir /opt/src

RUN mkdir -p /opt/src/gcc-build \
             /opt/gcc/mips-sgi-irix6.5 \
             /opt/irix-root \
             /opt/src/binutils

RUN archive=$(basename $IRIX_ROOT_URL); \
    curl -LO $IRIX_ROOT_URL && \
    echo "$IRIX_ROOT_SHA256  $archive" | shasum -a256 -c && \
    tar xf $archive -C /opt/irix-root && \
    rm $archive

RUN archive=$(basename $MOTIF_URL); \
    curl -LO $MOTIF_URL && \
    echo "$MOTIF_SHA256  $archive" | shasum -a256 -c && \
    tar xf $archive && \
    rm $archive && \
    mv Motif-2.1 /opt/motif

RUN archive=$(basename $GCC_URL); \
    curl -LO $GCC_URL && \
    echo "$GCC_SHA256  $archive" | shasum -a256 -c && \
    tar xf $archive && \
    rm $archive && \
    mv gcc-4.7-irix /opt/src/gcc

RUN ln -s /opt/irix-root/usr/include /opt/gcc/mips-sgi-irix6.5/sys-include && \
    ln -s /opt/irix-root/usr/lib32 /usr/lib32

COPY files/stdlib_core.h /opt/gcc/mips-sgi-irix6.5/sys-include/internal/
COPY files/gcc.texi /opt/src/gcc/gcc/doc/

RUN archive=$(basename $BINUTILS_URL); \
    curl -LO $BINUTILS_URL && \
    echo "$BINUTILS_SHA256  $archive" | shasum -a256 -c && \
    tar xf $archive -C /opt/src/binutils && \
    rm $archive && \
    cd /opt/src/binutils/binutils-2.17 && \
    ./configure --target=mips-sgi-irix6.5 \
                --prefix=/opt/binutils \
                --with-sysroot=/opt/irix-root \
                --enable-werror=no && \
    make && make install && make clean && \
    rm -rf /opt/src/binutils

RUN export AS_FOR_TARGET="mips-sgi-irix6.5-as" \
           LD_FOR_TARGET="mips-sgi-irix6.5-ld" \
           NM_FOR_TARGET="mips-sgi-irix6.5-nm" \
           OBJDUMP_FOR_TARGET="mips-sgi-irix6.5-objdump" \
           RANLIB_FOR_TARGET="mips-sgi-irix6.5-ranlib" \
           STRIP_FOR_TARGET="mips-sgi-irix6.5-strip" \
           READELF_FOR_TARGET="mips-sgi-irix6.5-readelf" \
           target_configargs="--enable-libstdcxx-threads=no" \
           PATH=/opt/binutils/bin:$PATH && \
    env && \
    cd /opt/src/gcc-build && \
    /opt/src/gcc/configure --enable-obsolete \
                           --disable-multilib \
                           --prefix=/opt/gcc \
                           --with-build-sysroot=/opt/irix-root \
                           --target=mips-sgi-irix6.5 \
                           --disable-nls \
                           --enable-languages=c,c++ && \
    make -j $(nproc) && make install && \
    rm -rf /opt/src/gcc && \
    rm -rf /opt/gcc/mips-sgi-irix6.5

RUN mkdir /opt/gcc/mips-sgi-irix6.5 && \
    ln -s /opt/binutils/mips-sgi-irix6.5/bin /opt/gcc/mips-sgi-irix6.5/bin && \
    ln -s /opt/irix-root/usr/include /opt/gcc/mips-sgi-irix6.5/sys-include && \
    ln -s /opt/src/gcc-build/mips-sgi-irix6.5/libgcc/libgcc_s.so \
          /opt/gcc/lib/gcc/mips-sgi-irix6.5/4.7.4/libgcc_s.so && \
    cp /opt/src/gcc-build/mips-sgi-irix6.5/libstdc++-v3/src/.libs/libstdc++.so* \
       /opt/gcc/lib/gcc/mips-sgi-irix6.5/4.7.4/. && \
    cp /opt/src/gcc-build/mips-sgi-irix6.5/libstdc++-v3/src/.libs/libstdc++.a \
       /opt/gcc/lib/gcc/mips-sgi-irix6.5/4.7.4/.

COPY patches/mman_map_anon.patch .
RUN patch -d/ -p0 < mman_map_anon.patch && \
    rm mman_map_anon.patch

# Install package that some packages need for for building. Adding them here
# rather than the top of the file reduces image rebuild time as we add tools.
RUN apt-get install -y --no-install-recommends \
      libtool \
      python2 \
      unzip

RUN mkdir -p /opt/pkg \
             /opt/cache

ENV PATH=/opt/binutils/bin:/opt/gcc/bin:/opt/bin:$PATH \
    CC="/opt/gcc/bin/mips-sgi-irix6.5-gcc" \
    CXX="/opt/gcc/bin/mips-sgi-irix6.5-g++" \
    CFLAGS="-B/opt/binutils/bin/mips-sgi-irix6.5- --sysroot=/opt/irix-root" \
    CXXFLAGS="-B/opt/binutils/bin/mips-sgi-irix6.5- --sysroot=/opt/irix-root" \
    TARGET=mips-sgi-irix6.5 \
    PREFIX=/opt/gcc \
    X11_PATH=/opt/motif

ENV TARGET_PREFIX=$PREFIX/$TARGET


FROM builder-base AS builder-dev

RUN apt-get install -y --no-install-recommends \
      ripgrep \
      less \
      procps \
      vim && \
    apt-get clean

CMD ["bash"]
