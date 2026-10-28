# Prod's judge image, built locally. The registry image was built by a CI
# workflow in the old cats-judge repo, which no longer exists, so extend the
# exact image prod was running (pinned by digest, so a later push to :latest
# can't silently change the judge) with what it was missing.
#
# Replace this with a from-scratch build once cats-judge/Dockerfile reproduces
# prod's judge (it currently differs: render.py-baked config, no numpy/scipy).

FROM registry.mesenev.ru/mesenev/cats-judge@sha256:c8e707f42acec4a73a85cebea51ff22c08dac5bff9b35396dce10c902dcafbe3

# Problem lint/check scripts run under #python, so python3.15 carries numpy,
# scipy and requests (problem 43442's lint_repo.py verifies a submitted GitHub
# commit URL through the GitHub API). The system python3 gets requests too, so
# pointing #python back at /usr/bin/python3 remains a working rollback.
# Debian's pypy3 (Python 3.9) backed DE 510 before PyPy 3.11 (below) and stays
# for rollback. bubblewrap is for cmd/sp-sandbox. The libraries are
# python3.15's runtime deps.
# The host's cats-judge/config/autodetect.xml points #python (DE 502) at
# /opt/python3.15/bin/python3.15, #pypy (DE 510) at /opt/pypy3.11/bin/pypy3.11
# and enables DE 510; Go (DE 404) is below.
# When a compiler or interpreter version changes, update the DE names users
# see (default_de.description, see sql/migrations/20261028-de-versions.sql).
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3-requests pypy3 bubblewrap \
        libssl3 libffi8 zlib1g libbz2-1.0 liblzma5 libsqlite3-0 libreadline8 \
        libncursesw6 libgdbm6 libuuid1 \
    && rm -rf /var/lib/apt/lists/*

# Built from python-jit.dockerfile; see there for how to build and ship it.
COPY --from=python-jit:3.15.1 /opt/python3.15 /opt/python3.15
RUN /opt/python3.15/bin/python3.15 -c 'import sys, ssl, sqlite3, numpy, scipy, requests; assert sys._jit.is_enabled()'

# Go backs DE 404. Judges used to get it from a hand-installed golang package
# in the container's writable layer, which every recreate wiped. The official
# tarball, pinned by checksum. Solutions build offline with whatever is in the
# image (GOTOOLCHAIN=local).
# The standard library is precompiled into GOCACHE here: a cold build writes
# more than the compile write_limit (128M), and under sp-sandbox the cache is
# read-only, which Go tolerates, so every sandboxed compile would start cold.
# GOMAXPROCS=1 keeps a solution's thread count and CPU time predictable; the
# DE's run_processes in devenv.xml covers the runtime's own threads.
ARG GO_VERSION=1.27.3
ARG GO_SHA256=65efbc80fdc1fa2cd2631cad5b481777a68e8725f34e89f50fc6ac714e379b40
RUN wget -q -O /tmp/go.tgz https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz \
    && echo "${GO_SHA256}  /tmp/go.tgz" | sha256sum -c - \
    && tar -C /usr/local -xzf /tmp/go.tgz \
    && rm /tmp/go.tgz
ENV GOTOOLCHAIN=local GOCACHE=/opt/go-cache GOPATH=/tmp/go GOFLAGS=-buildvcs=false GOMAXPROCS=1
RUN /usr/local/go/bin/go telemetry off \
    && GOMAXPROCS= /usr/local/go/bin/go build std \
    && cd /tmp && printf 'package main\nimport "fmt"\nfunc main() { fmt.Println("ok") }\n' > t.go \
    && /usr/local/go/bin/go build -o t.exe t.go && ./t.exe | grep -qx ok \
    && rm -rf t.go t.exe /tmp/go

# numpy for pypy3 (DE 510), so numpy solutions work under PyPy as under
# python3.15. Without it pypy3 finds Debian's CPython-only numpy in
# /usr/lib/python3/dist-packages and fails at import. Debian's pypy3 has no pip
# (ensurepip is stripped), so the wheel is unpacked into
# /usr/local/lib/pypy3.9/dist-packages, which comes first on pypy3's sys.path.
# Bytecode is compiled here because the sandbox's filesystem is read-only.
ARG PYPY_NUMPY_WHL=numpy-1.26.4-pp39-pypy39_pp73-manylinux_2_17_x86_64.manylinux2014_x86_64.whl
ARG PYPY_NUMPY_URL=https://files.pythonhosted.org/packages/8e/02/570545bac308b58ffb21adda0f4e220ba716fb658a63c151daecc3293350/${PYPY_NUMPY_WHL}
ARG PYPY_NUMPY_SHA256=95a7476c59002f2f6c590b9b7b998306fba6a5aa646b1e22ddfeaf8f78c3a29c
RUN wget -q -O /tmp/${PYPY_NUMPY_WHL} ${PYPY_NUMPY_URL} \
    && echo "${PYPY_NUMPY_SHA256}  /tmp/${PYPY_NUMPY_WHL}" | sha256sum -c - \
    && mkdir -p /usr/local/lib/pypy3.9/dist-packages \
    && unzip -q /tmp/${PYPY_NUMPY_WHL} -d /usr/local/lib/pypy3.9/dist-packages \
    && rm /tmp/${PYPY_NUMPY_WHL} \
    && pypy3 -m compileall -q /usr/local/lib/pypy3.9/dist-packages > /dev/null; \
    cd /tmp && pypy3 -c 'import numpy, requests; assert numpy.__version__ == "1.26.4"; assert numpy.arange(4).sum() == 6'

# PyPy 3.11 backs DE 510. Debian's pypy3 is Python 3.9, so solutions using
# `int | None` annotations or itertools.pairwise failed there with a runtime
# error. The official pypy.org build and numpy's wheel, both pinned by
# checksum. PyPy 7.3.x, not 8.0: PyPy 8.0 changed the ABI tag to pp80 and numpy
# publishes no wheels for it. Bytecode is compiled here because the sandbox's
# filesystem is read-only.
ARG PYPY_VERSION=7.3.23
ARG PYPY_SHA256=2bcab031cef7a37fe1930b51f7091e78a191ae63f80eca00a265d3378c3a645b
ARG PYPY311_NUMPY_WHL=numpy-2.4.6-pp311-pypy311_pp73-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl
ARG PYPY311_NUMPY_URL=https://files.pythonhosted.org/packages/1a/b0/413077f6b1153ed3cba361401c6783bbad6114804a000cc22eb71c13e190/${PYPY311_NUMPY_WHL}
ARG PYPY311_NUMPY_SHA256=8ad03c0965fb3c692200e74d458ca28c1dbb4ce96f9a479a8aa041ad5fabca02
RUN wget -q -O /tmp/pypy.tgz https://downloads.python.org/pypy/pypy3.11-v${PYPY_VERSION}-linux64.tar.gz \
    && echo "${PYPY_SHA256}  /tmp/pypy.tgz" | sha256sum -c - \
    && mkdir /opt/pypy3.11 \
    && tar -C /opt/pypy3.11 --strip-components=1 -xzf /tmp/pypy.tgz \
    && rm /tmp/pypy.tgz \
    && wget -q -O /tmp/${PYPY311_NUMPY_WHL} ${PYPY311_NUMPY_URL} \
    && echo "${PYPY311_NUMPY_SHA256}  /tmp/${PYPY311_NUMPY_WHL}" | sha256sum -c - \
    && unzip -q /tmp/${PYPY311_NUMPY_WHL} -d /opt/pypy3.11/lib/pypy3.11/site-packages \
    && rm /tmp/${PYPY311_NUMPY_WHL} \
    && /opt/pypy3.11/bin/pypy3.11 -m compileall -q /opt/pypy3.11/lib/pypy3.11 > /dev/null; \
    cd /tmp && /opt/pypy3.11/bin/pypy3.11 -c 'import sys, sqlite3, ssl, numpy; from itertools import pairwise; assert sys.version_info[:2] == (3, 11); assert numpy.__version__ == "2.4.6"; assert numpy.arange(4).sum() == 6'

# Bake the same DE settings into the image's own config, for judges that run
# it without bind-mounting /app (prod's judge mounts /app, so this is unused there).
RUN sed -i \
        -e 's|<define name="#python" de_code_autodetect="502" value="[^"]*" />|<define name="#python" de_code_autodetect="502" value="/opt/python3.15/bin/python3.15" />|' \
        -e 's|<define name="#pypy" de_code_autodetect="510" value="[^"]*" />|<define name="#pypy" de_code_autodetect="510" value="/opt/pypy3.11/bin/pypy3.11" />|' \
        -e 's|<de code="510" enabled="0" />|<de code="510" enabled="1" />|' \
        -e 's|<define name="#go" de_code_autodetect="404" value="[^"]*" />|<define name="#go" de_code_autodetect="404" value="/usr/local/go/bin/go" />|' \
        -e 's|<de code="404" enabled="0" />|<de code="404" enabled="1" />|' \
        /app/config/autodetect.xml \
    && grep -q 'value="/opt/python3.15/bin/python3.15"' /app/config/autodetect.xml \
    && grep -q 'value="/opt/pypy3.11/bin/pypy3.11"' /app/config/autodetect.xml \
    && grep -q '<de code="510" enabled="1" />' /app/config/autodetect.xml \
    && grep -q 'value="/usr/local/go/bin/go"' /app/config/autodetect.xml \
    && grep -q '<de code="404" enabled="1" />' /app/config/autodetect.xml
