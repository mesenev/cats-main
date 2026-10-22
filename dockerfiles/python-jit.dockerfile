# CPython with the experimental JIT, packaged as an image holding only
# /opt/python3.15, for the judge to COPY from. Compiling it takes 15 min to
# well over an hour depending on the machine (PGO runs the test suite, and
# GCC's LTO links serially), so build it once per Python release:
#
#   docker build -f dockerfiles/python-jit.dockerfile -t python-jit:3.15.1 dockerfiles
#
# then `docker save python-jit:3.15.1 | gzip | ssh <host> 'gunzip | docker load'`
# to ship it, rather than rebuilding on a slow host.

# CPython 3.15 with the experimental JIT, for DE 502 (Python). Built in its own stage on
# the same Debian release as the judge image so the result runs there as-is;
# the JIT's build step needs LLVM 21, which bookworm only gets from apt.llvm.org.
FROM debian:bookworm AS python-jit
ARG PY_VERSION=3.15.1
ARG PY_SHA256=673ae7232d84c894729882c8257d300ef2d26523911bfd3917ec8ce7f526f99b
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential ca-certificates wget gnupg xz-utils python3 \
        libssl-dev libffi-dev zlib1g-dev libbz2-dev liblzma-dev libsqlite3-dev \
        libreadline-dev libncurses-dev libgdbm-dev uuid-dev \
    && wget -qO /etc/apt/trusted.gpg.d/apt.llvm.org.asc https://apt.llvm.org/llvm-snapshot.gpg.key \
    && echo "deb http://apt.llvm.org/bookworm/ llvm-toolchain-bookworm-21 main" > /etc/apt/sources.list.d/llvm.list \
    && apt-get update && apt-get install -y --no-install-recommends clang-21 llvm-21
WORKDIR /src
RUN wget -q https://www.python.org/ftp/python/${PY_VERSION}/Python-${PY_VERSION}.tar.xz \
    && echo "${PY_SHA256}  Python-${PY_VERSION}.tar.xz" | sha256sum -c - \
    && tar xJf Python-${PY_VERSION}.tar.xz
# --enable-experimental-jit=yes builds the JIT and turns it on by default;
# PGO + LTO make the interpreter itself faster, at the cost of a slow build.
RUN cd Python-${PY_VERSION} \
    && ./configure --prefix=/opt/python3.15 --enable-experimental-jit=yes \
        --enable-optimizations --with-lto \
    && make -j"$(nproc)" && make install
# Fail the build rather than ship an interpreter whose JIT is off.
RUN /opt/python3.15/bin/python3.15 -c 'import sys; assert sys._jit.is_enabled(), "JIT not enabled"' \
    && /opt/python3.15/bin/python3.15 -m pip install --no-cache-dir --only-binary=:all: numpy scipy requests

FROM scratch
COPY --from=python-jit /opt/python3.15 /opt/python3.15
