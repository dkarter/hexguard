# Contributing

Thanks for contributing to Hexguard.

## Release automation setup

Hexguard uses Release Please for versioning, changelog updates, and GitHub
releases.

1. Enable GitHub Actions permissions to create and approve pull requests.
2. Keep commit messages in Conventional Commit format (`feat:`, `fix:`, etc.).
3. Optionally set `RELEASE_PLEASE_TOKEN` (a PAT) if you want downstream
   workflows to trigger from release PRs and release tags.
4. Set `HEX_API_KEY` so CI can publish package/docs to Hex on release.

Release config files:

- `release-please-config.json`
- `.release-please-manifest.json`
- `CHANGELOG.md`

## HexDocs on release

On every published GitHub release, CI will:

1. Build docs with `mix docs`
2. Upload the generated `doc/` folder as an artifact
3. Publish docs to HexDocs when `HEX_API_KEY` is configured

Required secret for publication:

- `HEX_API_KEY`

## CI trigger modes

The Hexguard runner workflow supports both scheduled and manual execution.

- **Cron**: runs daily and defaults to `mix hexguard --random`
- **Manual (`workflow_dispatch`)**: supports inputs for:
  - `dep` (specific dependency)
  - `dry_run`
  - `block_breaking_changes`
