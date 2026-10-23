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
# pypy3 backs DE 510 (PyPy 3). bubblewrap is for cmd/sp-sandbox. The libraries
# are python3.15's runtime deps.
# The host's cats-judge/config/autodetect.xml points #python (DE 502) at
# /opt/python3.15/bin/python3.15 and enables DE 510; Go (DE 404) is below.
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

# Bake the same DE settings into the image's own config, for judges that run
# it without bind-mounting /app (prod's judge mounts /app, so this is unused there).
RUN sed -i \
        -e 's|<define name="#python" de_code_autodetect="502" value="[^"]*" />|<define name="#python" de_code_autodetect="502" value="/opt/python3.15/bin/python3.15" />|' \
        -e 's|<define name="#pypy" de_code_autodetect="510" value="[^"]*" />|<define name="#pypy" de_code_autodetect="510" value="/usr/bin/pypy3" />|' \
        -e 's|<de code="510" enabled="0" />|<de code="510" enabled="1" />|' \
        -e 's|<define name="#go" de_code_autodetect="404" value="[^"]*" />|<define name="#go" de_code_autodetect="404" value="/usr/local/go/bin/go" />|' \
        -e 's|<de code="404" enabled="0" />|<de code="404" enabled="1" />|' \
        /app/config/autodetect.xml \
    && grep -q 'value="/opt/python3.15/bin/python3.15"' /app/config/autodetect.xml \
    && grep -q '<de code="510" enabled="1" />' /app/config/autodetect.xml \
    && grep -q 'value="/usr/local/go/bin/go"' /app/config/autodetect.xml \
    && grep -q '<de code="404" enabled="1" />' /app/config/autodetect.xml
