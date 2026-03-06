# Release Process

## Versioning
Use semantic tags: `vMAJOR.MINOR.PATCH`.

## Pre-release checklist
1. `CHANGELOG.md` updated.
2. `./scripts/doctor.sh` passes.
3. `./scripts/e2e_preflight.sh` passes.
4. `./scripts/e2e_smoke.sh` passes.
5. `./scripts/package_release.sh --version <version>` runs locally.
6. `./scripts/verify_release.sh --dist-dir dist --version <version>` passes.
7. Third-party license/redistribution verification completed (`THIRD_PARTY_NOTICES.md`).

## Publish
1. Commit release prep changes.
2. Create and push tag:
```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```
3. GitHub Actions `release.yml` builds artifacts and creates release.

## Artifacts
- `Suniye.dmg`
- `Suniye.app.zip`
- `SHA256SUMS.txt`
