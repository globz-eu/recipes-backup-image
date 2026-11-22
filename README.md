# recipes-backup-image

## Purpose

The container image for the nightly backup job in recipes-infrastructure
(`src/backupJob/createBackupJob.ts`, `scripts/backup/nightly-backup.sh`). It is `postgres:16-alpine`
plus the `rclone` binary from the official rclone image, so the job installs nothing at run time.
Its `pg_dump` must be at least the database server's major version.

Both base images are pinned by digest in the `Dockerfile`.

## Image

`rg.fr-par.scw.cloud/recipes-images/recipes-backup:vX.Y.Z`, linux/amd64 only. The `recipes-images`
namespace is public, so pulls need no credentials. recipes-infrastructure pins the image by tag
and digest (`BACKUP_JOB_IMAGE`).

## Checks

Every branch push builds the image without pushing it and runs `scripts/smoke-test.sh`, which
fails unless `pg_dump` reports major 16 and `pg_restore`, `rclone` and the CA bundle are present.
Run it locally with:

```bash
docker build -t recipes-backup:local .
./scripts/smoke-test.sh recipes-backup:local
```

## Releasing

Push a `vX.Y.Z` tag on `main`:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The release workflow builds the image, runs the same smoke test, pushes
`…/recipes-backup:vX.Y.Z` and writes `IMAGE:TAG@DIGEST` to the run summary. Copy that reference
into `BACKUP_JOB_IMAGE` in recipes-infrastructure. To read it later:

```bash
docker buildx imagetools inspect rg.fr-par.scw.cloud/recipes-images/recipes-backup:v1.0.0
```

## Bumping

To move to a newer `postgres:16-alpine` or rclone release, read the new index digest:

```bash
docker buildx imagetools inspect postgres:16-alpine
docker buildx imagetools inspect rclone/rclone:<version>
```

Put the top-level `Digest:` (and the rclone version) into the `Dockerfile`, merge, then release
a new tag and update `BACKUP_JOB_IMAGE`. A new Postgres major also needs the base tag and the
`16` in `scripts/smoke-test.sh` changed.

## Secret

The release workflow needs the repository secret `SCW_SECRET_KEY`: a Scaleway API secret key
with push rights on the `recipes-images` registry namespace (username `nologin`). Branch CI needs
no secret.
