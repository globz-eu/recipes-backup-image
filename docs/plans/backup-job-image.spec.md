# Spec: backup job image in the Scaleway registry

Ticket: [recipes-infrastructure issue #47](https://github.com/globz-eu/recipes-infrastructure/issues/47)

## Why

- The nightly backup job pulls `postgres:16-alpine` from Docker Hub and runs `apk add rclone` on every run.
- Each run depends on Docker Hub (anonymous pull limits per IP, availability) and the Alpine mirror (unpinned rclone).
- Production must not depend on either before it joins `backedUpStacks` (recipes-infrastructure issue #21).

## Goals

- Own image `rg.fr-par.scw.cloud/recipes-images/recipes-backup`, built in the new repo [recipes-backup-image](https://github.com/globz-eu/recipes-backup-image).
- `pg_dump`/`pg_restore` of major 16 (at least the Serverless SQL server's major) and a pinned rclone.
- The backup job references it by digest; nothing is installed at run time.

## Non-goals

- arm64 (Serverless Jobs run amd64).
- Automated dependency bumps (Renovate, Dependabot).
- Baking `nightly-backup.sh` into the image: it stays inline as the job's command, so script changes need no image release.
- Registry credentials for the pull: `recipes-images` is public (`docs/permissions.md`).

## Approaches (rclone)

- **Picked: copy the binary from `rclone/rclone:<version>@sha256:…`** (`COPY --from`): version and content pinned by digest, one line, Docker Hub only at build time on GitHub's runners.
- Download the release zip and check its SHA256: same pin, but needs curl/unzip and a hand-bumped checksum.
- `apk add rclone=<ver>`: rejected, Alpine drops old package revisions and the build eventually breaks.

## Design

### Part 1: recipes-backup-image (first PR)

- `Dockerfile`: `FROM postgres:16-alpine@sha256:…` plus `COPY --from=rclone/rclone:<ver>@sha256:… /usr/local/bin/rclone /usr/local/bin/rclone`; nothing else.
- Release workflow on `vX.Y.Z` tags: build linux/amd64 and push `rg.fr-par.scw.cloud/recipes-images/recipes-backup:<tag>`, logging in with secret `SCW_SECRET_KEY` (as in recipes-cms `build.yml`); write the pushed digest to the run summary.
- Branch CI (every push): build without pushing, then smoke-test the image: `pg_dump --version` reports major 16, `pg_restore --version` and `rclone version` run.
- README: purpose, the image name, how to release (tag `vX.Y.Z`, read the digest from the run summary, pin it in recipes-infrastructure), how to bump the base image or rclone, the required secret.

### Pause (user)

- Add `SCW_SECRET_KEY` (push rights on `recipes-images`) to recipes-backup-image.
- Merge the PR and tag `v1.0.0`; the release workflow pushes the image and reports its digest.

### Part 2: recipes-infrastructure (second PR)

- `src/backupJob/createBackupJob.ts`: `BACKUP_JOB_IMAGE` becomes `rg.fr-par.scw.cloud/recipes-images/recipes-backup:v1.0.0@sha256:<digest>`.
- `scripts/backup/nightly-backup.sh`: drop `apk add --no-cache rclone` and update the header comment (image name).
- Unit test: the backup job's image is in `rg.fr-par.scw.cloud/recipes-images/` and pinned by `@sha256:`; the nightly script installs nothing.
- Docs: the `apk add rclone` known risk in `docs/environments.md` (resolved), V3 in bootstrap step 11 (`docs/staging-bootstrap.md`), `CLAUDE.md` and README where they name the job image.
- PR description: `Closes globz-eu/recipes-infrastructure#47` (it is the last request for the issue).

## Constraints

- Follow each repo's rules (recipes-infrastructure `.claude/rules/`).
- Commit messages: capital imperative verb, short, granular.

## Left to the builder

- Exact base and rclone digests and rclone version (current stable at build time).
- Workflow and README layout in the new repo; action versions as in recipes-cms `build.yml`.
- Where in `tests/unit` the job image test goes (likely `program-runtime-backup.test.ts`).
