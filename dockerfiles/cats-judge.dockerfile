# Prod's judge image, built locally. The registry image was built by a CI
# workflow in the old cats-judge repo, which no longer exists, so extend the
# exact image prod was running (pinned by digest, so a later push to :latest
# can't silently change the judge) with what it was missing.
#
# Replace this with a from-scratch build once cats-judge/Dockerfile reproduces
# prod's judge (it currently differs: render.py-baked config, no numpy/scipy).
FROM registry.mesenev.ru/mesenev/cats-judge@sha256:c8e707f42acec4a73a85cebea51ff22c08dac5bff9b35396dce10c902dcafbe3

# Problem lint/check scripts run under the system python3. numpy and scipy are
# already in the base image; requests is not (problem 43442's lint_repo.py
# verifies a submitted GitHub commit URL through the GitHub API).
# pypy3 backs DE 510 (PyPy 3); enable it in the host's config/autodetect.xml.
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3-requests pypy3 \
    && rm -rf /var/lib/apt/lists/*
