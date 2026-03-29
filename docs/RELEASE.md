# Release Process

## Versioning
Use semantic tags: `vMAJOR.MINOR.PATCH`.

Release automation treats the git tag as the source of truth for `MARKETING_VERSION`.
GitHub Actions injects a numeric `CURRENT_PROJECT_VERSION` from `GITHUB_RUN_NUMBER`.
Do not manually bump app version metadata in `project.yml` just to cut a release tag.

## Pre-release checklist
1. PR description and commits reflect the release changes accurately.
2. `./scripts/doctor.sh` passes.
3. `./scripts/e2e_preflight.sh` passes.
4. `./scripts/e2e_smoke.sh` passes.
5. `./scripts/package_release.sh --version <version> --build-number <number>` runs locally.
6. `./scripts/verify_release.sh --dist-dir dist --version <version>` passes.
7. Third-party license/redistribution verification completed (`THIRD_PARTY_NOTICES.md`).

## Publish
1. Create and push tag:
```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```
2. GitHub Actions `release.yml` injects the tag version plus `GITHUB_RUN_NUMBER`, builds artifacts, and creates the release.

## Artifacts
- `Suniye.dmg`
- `Suniye.app.zip`
- `SHA256SUMS.txt`

## Update contract
Manual updater behavior depends on release artifact names and checksums:
- Preferred install artifact: `Suniye.dmg`
- Fallback install artifact: `Suniye.app.zip`
- Checksum manifest: `SHA256SUMS.txt`

`SHA256SUMS.txt` must include checksum lines for published artifacts, especially `Suniye.dmg`.
