# Hexguard

Hexguard is an AI-assisted dependency maintenance task for Elixir projects.
It analyzes Hex package diffs for security and compatibility risk, runs compile
and tests, and can open PRs automatically.

## What it does

- Picks a dependency (`mix hexguard ash` or `--random`)
- Fetches package diffs with `mix hex.package diff`
- Runs a restricted security evaluation in Docker
- Runs a compatibility evaluation with workspace context
- Verifies your project with compile and tests
- Creates a branch, commit, PR, and issue (when blocked)

## Install

Add Hexguard to your target project:

```elixir
def deps do
  [
    {:hexguard, "~> 0.1", only: :dev, runtime: false}
  ]
end
```

Then install deps:

```bash
mix deps.get
```

## Usage

Update one dependency:

```bash
mix hexguard ash
```

Pick a random updatable dependency:

```bash
mix hexguard --random
```

Dry-run mode (no branch/commit/push/PR/issue):

```bash
mix hexguard ash --dry-run
```

Help:

```bash
mix help hexguard
```

## Key options

- `--random` pick one dependency with update available
- `--base` base branch for PRs (default: `main`)
- `--model` override model for opencode
- `--block-breaking-changes` fail on compatibility/breaking concerns too
- `--allow-dirty` skip clean-tree check
- `--dry-run` disable branch/commit/push/PR/issue side effects

## Requirements

- Elixir `~> 1.19`
- `gh` authenticated for PR/issue operations
- `opencode` and Docker available
- API credentials for model provider (for example `OPENAI_API_KEY`)

## Automation

- Scheduled and manual task runner: `.github/workflows/daily-hexguard.yml`
- Automated release PRs/changelog and Hex.pm package publish: `.github/workflows/release-please.yml`
- Release docs workflow (HexDocs publish on release): `.github/workflows/release-docs.yml`

## Contributing

Contribution and maintainer workflow details are in `CONTRIBUTING.md`.
