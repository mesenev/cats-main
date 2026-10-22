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
# pypy3 backs DE 510 (PyPy 3). The libraries are python3.15's runtime deps.
# The host's cats-judge/config/autodetect.xml points #python (DE 502) at
# /opt/python3.15/bin/python3.15 and enables DE 510.
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3-requests pypy3 \
        libssl3 libffi8 zlib1g libbz2-1.0 liblzma5 libsqlite3-0 libreadline8 \
        libncursesw6 libgdbm6 libuuid1 \
    && rm -rf /var/lib/apt/lists/*

# Built from python-jit.dockerfile; see there for how to build and ship it.
COPY --from=python-jit:3.15.1 /opt/python3.15 /opt/python3.15
RUN /opt/python3.15/bin/python3.15 -c 'import sys, ssl, sqlite3, numpy, scipy, requests; assert sys._jit.is_enabled()'
