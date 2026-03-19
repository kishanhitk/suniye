# Release Process

## Versioning
Use semantic tags: `vMAJOR.MINOR.PATCH`.

## Pre-release checklist
1. `./scripts/doctor.sh` passes.
2. `./scripts/e2e_preflight.sh` passes.
3. `./scripts/e2e_smoke.sh` passes.
4. `./scripts/package_release.sh --version <version>` runs locally.
5. `./scripts/verify_release.sh --dist-dir dist --version <version>` passes.
6. Third-party license/redistribution verification completed (`THIRD_PARTY_NOTICES.md`).

## Publish
1. Commit release prep changes.
2. Create and push tag:
```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```
3. GitHub Actions `release.yml` builds artifacts and creates the GitHub release using auto-generated release notes.

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
