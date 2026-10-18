# Releases

## Prepare

1. Update `fan_version.lua` (for example, `0.3.1` or `0.4.0-rc.1`).
2. Update versioned installation examples in README when needed.
3. Run `python tools/package.py --tag v0.3.1` and inspect `dist/`.

Packaging validates the version, checks ZIP integrity and writes SHA-256 files. Tests, local environments and user data are excluded. No third-party Python packages are needed.

## GitHub automation

After the workflow is present in the repository's default branch, push a matching version tag, such as `v0.3.1`. The Release workflow builds the archives, creates a draft, uploads both ZIPs and their individual SHA-256 files, then publishes it. Tags containing a prerelease suffix produce prereleases.

GitHub generates release notes automatically when the draft is created. A mismatched tag stops the build. Published assets are never overwritten. If upload fails, the draft remains; rerun the workflow for that tag to finish it. Manual runs must select an existing tag; branch runs are skipped.

The workflow uses the repository's automatic `GITHUB_TOKEN` with `contents: write`; no personal token is required. Repository or organization policy must allow that permission. Setup does not create a tag or publish a release by itself.
