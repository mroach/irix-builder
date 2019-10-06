ARG IRIX_VER=6.5.30

FROM debian:buster-slim AS irix-builder:${IRIX_VER}

ARG GCC_URL=http://dl.mroach.com/irix/buildtools/gcc-4_7-irix.zip
ARG IRIX_ROOT_URL=http://dl.mroach.com/irix/buildtools/irix-root.${IRIX_VER}.tar.bz2
ARG BINUTILS_URL=http://dl.mroach.com/irix/buildtools/binutils-2.17a.tar.bz2

ARG GCC_SHA256=51bf0ad1ba717ec186d9e1a6fe91367b128c71e82e66624cff3287c823b4e45f
ARG IRIX_ROOT_SHA256=b8b6363121a99aaf0309d0a6f63a18c203ddbb34f53683c9a56d568be2b6a549
ARG BINUTILS_SHA256=547355f0abb865995ad340e0383181d0cfef52d5cce2fd7e10a8a7db371a276a

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential \
      bison \
      flex \
      libgmp-dev \
      libmpfr-dev \
      libmpc-dev \
      texinfo  \
      unzip \
      autoconf \
      gettext \
      curl \
      ca-certificates \
      vim \
    apt-get clean

WORKDIR /opt

RUN mkdir /opt/src

RUN mkdir -p /opt/src/gcc-build \
             /opt/gcc/mips-sgi-irix6.5 \
             /opt/irix-root \
             /opt/src/binutils

RUN curl -LO $IRIX_ROOT_URL && \
    echo "$IRIX_ROOT_SHA256 gcc-4_7-irix.zip" | shasum -a256 -c && \
    tar xf irix-root.${IRIX_VER}.tar.bz2 -C /opt/irix-root && \
    rm irix-root.${IRIX_VER}.tar.bz2

RUN curl -LO $GCC_URL && \
    echo "$GCC_SHA256 gcc-4_7-irix.zip" | shasum -a256 -c && \
    unzip gcc-4_7-irix.zip -d /opt/src && \
    rm gcc-4_7-irix.zip && \
    mv /opt/src/gcc-gcc-4_7-irix /opt/src/gcc

RUN ln -s /opt/irix-root/usr/include /opt/gcc/mips-sgi-irix6.5/sys-include && \
    ln -s /opt/irix-root/usr/lib32 /usr/lib32

COPY files/stdlib_core.h /opt/gcc/mips-sgi-irix6.5/sys-include/internal/
COPY files/gcc.texi /opt/src/gcc/gcc/doc/

RUN curl -LO $BINUTILS_URL && \
    echo "$BINUTILS_SHA256 binutils-2.17a.tar.bz2" | shasum -a256 -c && \
    tar xf binutils-2.17a.tar.bz2 -C /opt/src/binutils && \
    rm binutils-2.17a.tar.bz2 && \
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
    ln -s /opt/irix-root/usr/include /opt/gcc/mips-sgi-irix6.5/sys-include

ENV PATH=/opt/binutils/bin:/opt/gcc/bin:$PATH \
    CC="/opt/gcc/bin/mips-sgi-irix6.5-gcc" \
    CXX="/opt/gcc/bin/mips-sgi-irix6.5-g++" \
    CFLAGS="-B/opt/binutils/bin/mips-sgi-irix6.5- --sysroot=/opt/irix-root" \
    CXXFLAGS="-B/opt/binutils/bin/mips-sgi-irix6.5- --sysroot=/opt/irix-root" \
    TARGET=mips-sgi-irix6.5 \
    PREFIX=/opt/gcc \
    TARGET_PREFIX=$PREFIX/$TARGET
