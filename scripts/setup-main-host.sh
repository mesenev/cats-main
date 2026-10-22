#!/usr/bin/env bash
# One-time host-side setup for the bind-mounted `main` service, run once
# after cloning the repo and before `docker compose up`. Re-run is safe.
#
# Populates generated assets that used to be produced at image-build time
# (back when the image baked in a COPY of the app source) and fixes up
# permissions on the few directories Apache needs to write into, using the
# www-data GID (33) matching the main container's base image rather than
# a host group name, since this host doesn't necessarily have Apache
# installed at all.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

./deploy.bash --step 4,6

# deploy.bash has no `set -e` and reports "ok" even when install_js.pl dies,
# so check the result directly rather than trusting its exit status.
for f in jquery.min.js ace MathJax; do
    [[ -e js/lib/$f ]] || { echo "js/lib/$f missing: JS install failed" >&2; exit 1; }
done

chgrp -R 33 cgi-bin css download images static tt
chmod -R g+r cgi-bin
chmod g+rw static tt download/{,att,f,img,pr,vis} cgi-bin/rank_cache{,/r} cgi-bin/repos
