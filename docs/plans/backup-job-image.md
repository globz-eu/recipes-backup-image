# Plan: backup job image in the Scaleway registry

Ticket: [recipes-infrastructure issue #47](https://github.com/globz-eu/recipes-infrastructure/issues/47).
Spec: [backup-job-image.spec.md](backup-job-image.spec.md).

## Context and goal

- The backup job runs `docker.io/library/postgres:16-alpine@sha256:…` (`src/backupJob/createBackupJob.ts:30`).
- `scripts/backup/nightly-backup.sh:15` runs `apk add --no-cache rclone` on every run.
- Goal: own image `rg.fr-par.scw.cloud/recipes-images/recipes-backup`, built in recipes-backup-image.
- The job pins it by tag and digest and installs nothing at run time.
- Needed before production joins `backedUpStacks` ([recipes-infrastructure issue #21](https://github.com/globz-eu/recipes-infrastructure/issues/21)).

## Acceptance criteria

1. recipes-backup-image `Dockerfile` has a digest-pinned `FROM postgres:16-alpine` and a digest-pinned rclone `COPY --from`, nothing else.
2. Branch CI builds without pushing and fails unless `pg_dump --version` reports major 16.
3. Branch CI also fails unless `pg_restore --version` and `rclone version` run.
4. A `vX.Y.Z` tag pushes `…/recipes-backup:vX.Y.Z` (linux/amd64) and writes its digest to the run summary.
5. The release runs the same smoke test before pushing.
6. recipes-backup-image README covers purpose, image name, release, bumps and the `SCW_SECRET_KEY` secret.
7. `BACKUP_JOB_IMAGE` is `rg.fr-par.scw.cloud/recipes-images/recipes-backup:v1.0.0@sha256:<digest>`.
8. Unit test: the job image matches `^rg\.fr-par\.scw\.cloud/recipes-images/recipes-backup:v\d+\.\d+\.\d+@sha256:[0-9a-f]{64}$`.
9. Unit test: `nightly-backup.sh` calls no `apk` (call list starts with `pg_dump`).
10. No doc in recipes-infrastructure still says the backup job uses Docker Hub or `apk add rclone`; the restore runbook uses `recipes-backup`.
11. `npm run lint`, `npm run typecheck`, `npm run test:unit` pass.

## Design

### Part 1: recipes-backup-image

- `Dockerfile`: two lines, `FROM postgres:16-alpine@sha256:<base>` and `COPY --from=rclone/rclone:<ver>@sha256:<rclone> /usr/local/bin/rclone /usr/local/bin/rclone`.
- Digests read on 2026-11-22 from the Docker Hub API (confirm before use):
  - `postgres:16-alpine` index: `sha256:f2f98726820d0342055351c6e9d36e705f5bfffb3dd53ff556325114b08afb6d`.
  - rclone `1.76.0` (current stable, released 2026-11-06) index: `sha256:7cbeec24a44f206067597c0368be4de90ae19a64d5113c7d1938bd737a81e466`.
  - Confirm with `docker buildx imagetools inspect postgres:16-alpine` and `docker buildx imagetools inspect rclone/rclone:1.76.0` (top-level `Digest:`).
- `scripts/smoke-test.sh IMAGE`: `docker run --rm IMAGE pg_dump --version | grep -q 'PostgreSQL) 16\.'`, then `pg_restore --version`, `rclone version`.
  - Shared by both workflows, so release and branch CI test the same things.
- `.github/workflows/ci.yml`: `on: push` (branches); checkout, buildx, `build-push-action` with `load: true`, `push: false`, tag `recipes-backup:ci`; run the smoke script.
- `.github/workflows/release.yml`: copy of the amd64 job of recipes-cms `.github/workflows/build.yml` (`on: push: tags: v[0-9]+.[0-9]+.[0-9]+`).
  - Same action versions: `checkout@v4`, `setup-buildx-action@v3`, `login-action@v3` (`nologin`, `secrets.SCW_SECRET_KEY`), `build-push-action@v6`.
  - Build with `load: true`, smoke-test, then a second `build-push-action` with `push: true` (cached layers).
  - Step `echo "Digest: \`$IMAGE:$GITHUB_REF_NAME@${{ steps.push.outputs.digest }}\`" >> "$GITHUB_STEP_SUMMARY"`.
  - `permissions: contents: read`; no registry cache, GitHub release or e2e dispatch (YAGNI).
- `README.md`: sections Purpose, Image, Releasing, Bumping (base or rclone digest, then tag), Secret.
- Trade-off: no hadolint/actionlint; a two-line Dockerfile and two workflows are covered by the branch run.

### Part 2: recipes-infrastructure

- `src/backupJob/createBackupJob.ts:29-31`: new `BACKUP_JOB_IMAGE`; keep the "at least the server's major" comment, naming the image.
- `scripts/backup/nightly-backup.sh:2,15`: header says `recipes-backup` image (pg_dump 16 and rclone); drop the `apk` line.
- `tests/unit/program-runtime-backup.test.ts:55,64`: new regex (AC 8); test name says "pinned backup image".
- `tests/unit/backup-nightly-script.test.ts:7,32-36`: keep the `apk` stub so a call would be recorded; expect calls `["pg_dump", "pg_restore", "rclone", "rclone", "rclone"]`; shift the `calls[n]` indices by one.
- `docs/environments.md:36` (image), `:115-117` (remove the resolved risk), `:135-136` (V3: note the job now uses `recipes-backup`).
- Restore runbook in `docs/environments.md` (`:174`, `:207`, `:216`, `:262`): use `rg.fr-par.scw.cloud/recipes-images/recipes-backup:v1.0.0` instead of `postgres:16-alpine` and `rclone/rclone:1.69.1`.
  - The rclone call becomes `… recipes-backup:v1.0.0 rclone copy …` (the postgres entrypoint runs other commands as-is); same for the `check --one-way` hint after it.
  - Restores then use the same `pg_restore`/`rclone` as the dumps and need no Docker Hub.
- `docs/staging-bootstrap.md:664`: reword "Docker Hub pulls" in the V1 to V5 summary.
- `CLAUDE.md:42` (Image: the backup job runs `recipes-backup`, not `containerImage`), `:52` (Backups: name the image).
- `README.md:435` "Container image" and `docs/permissions.md:28`: mention `recipes-backup` in `recipes-images`.

## Implementation steps

### Part 1 (recipes-backup-image, clone to `/home/golg/Development/recipes/recipes-backup-image`)

1. Add `Dockerfile` with the confirmed digests.
2. Add `scripts/smoke-test.sh` (executable, `set -eu`).
3. Add `.github/workflows/ci.yml`; push the branch and check the run is green.
4. Add `.github/workflows/release.yml`.
5. Add `README.md`.
6. Open the PR; stop for the user.

### Pause (user)

- Add secret `SCW_SECRET_KEY` (push rights on `recipes-images`), merge, tag `v1.0.0`.
- Read the digest: run summary (`gh run view <id> | cat`), or `docker buildx imagetools inspect rg.fr-par.scw.cloud/recipes-images/recipes-backup:v1.0.0`.

### Part 2 (recipes-infrastructure)

7. Pin `BACKUP_JOB_IMAGE` (placeholder `<digest>` from the pause) and update the image test.
8. Drop `apk add` from `nightly-backup.sh` and update its test.
9. Update `docs/environments.md` (incl. the restore runbook) and `docs/staging-bootstrap.md`.
10. Update `CLAUDE.md`, `README.md` and `docs/permissions.md`.
11. Open the PR with `Closes globz-eu/recipes-infrastructure#47`.

## Test plan

- Part 1: branch CI green; release run green with the digest in its summary.
- After the release: anonymous `docker pull rg.fr-par.scw.cloud/recipes-images/recipes-backup:v1.0.0@sha256:<digest>` works (public namespace).
- Then `./scripts/smoke-test.sh` against the pulled image passes locally.
- Part 2: `npm run lint`, `npm run typecheck`, `npm run test:unit`.
- No `pulumi preview` diff expected: no stack has `enableBackups`.

## Risks and open questions

- The postgres alpine base must have `/etc/ssl/certs/ca-certificates.crt` for rclone's HTTPS.
  - `apk add rclone` pulled `ca-certificates` before; alpine ships `ca-certificates-bundle`.
  - Add `test -s /etc/ssl/certs/ca-certificates.crt` to the smoke test.
- The first real job run with the new image only happens with production (issue #21 above); no staging trial is planned.
- `build-push-action@v6` adds a provenance attestation, so the digest is an index; pin that digest as-is (Scaleway Jobs already pull recipes-cms the same way).
- Decided: the restore runbook switches to `recipes-backup` too (user, at plan approval).
