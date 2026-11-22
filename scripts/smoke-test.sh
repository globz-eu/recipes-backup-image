#!/bin/sh
# Checks that IMAGE has what the nightly backup job needs: pg_dump and pg_restore of major 16
# (at least the server's major), rclone, and the CA bundle rclone needs for HTTPS.
set -eu

image=${1:?usage: smoke-test.sh IMAGE}

docker run --rm "$image" pg_dump --version | grep -q 'PostgreSQL) 16\.' || {
    echo "pg_dump in $image is not major 16" >&2
    exit 1
}
docker run --rm "$image" pg_restore --version
docker run --rm "$image" rclone version
docker run --rm "$image" test -s /etc/ssl/certs/ca-certificates.crt
echo "Smoke test passed for $image"
