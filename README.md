# graphify-init

Initialize [Graphify](https://github.com/Graphify-Labs/graphify) for the current Git repository with code-only extraction, project-scoped agent integration, safe ignore rules, and automatic Git hooks.

## Install

Install the reusable command:

```bash
curl -fsSL https://raw.githubusercontent.com/wrallee/graphify-init/main/install.sh | bash
graphify-init
```

For a Codex-only setup that keeps Graphify files local:

```bash
graphify-init --local
```

`--local` is supported only for Codex. It creates an ignored `AGENTS.override.md` with Graphify instructions and tells Codex to read the repository's `AGENTS.md` when one exists. Codex reads the override in place of `AGENTS.md`, so this explicit reference preserves the shared instructions. Use `graphify-init --local --no-base-agents` when the existing `AGENTS.md` should not apply.

Or initialize the current repository once without installing `graphify-init`:

```bash
curl -fsSL https://raw.githubusercontent.com/wrallee/graphify-init/main/graphify-init | bash
```

The script asks before installing either `uv` or Graphify. Declining either installation stops initialization.

## What it does

1. Verifies that the current directory belongs to a Git repository.
2. Offers to install `uv` when missing.
3. Offers to install the official `graphifyy` package when Graphify is missing.
4. Lets you select Codex, Claude Code, Gemini CLI, OpenCode, Cursor, or Antigravity with the arrow keys.
5. Installs only project-scoped Graphify skills and integration files.
6. Updates `.gitignore` and `.graphifyignore` through idempotent managed blocks.
7. Builds a local AST graph with no LLM calls and no visualization, unless `graphify-out/graph.json` already exists.
8. Installs Graphify's Git hooks in the default mode.

In `--local` mode, the initializer installs the Codex project skill, leaves `AGENTS.md` untouched, ignores `AGENTS.override.md`, `.codex/hooks.json`, `.codex/skills/graphify/`, `.graphifyignore`, and all of `graphify-out/`, and skips new Git hook installation. Existing hooks remain installed. The initializer does not change `.gitattributes` in this mode. A changed local `SKILL.md` is backed up as `SKILL.md.bak` before replacement.

Re-running preserves an existing graph, or resumes an extraction or clustering step interrupted during initialization. Use `graphify update .` when you want to refresh a completed graph. If Graphify files are already tracked by Git, `--local` stops before changing the repository and prints the `git rm --cached` command needed to keep those files local.

## Generated-file policy

The initializer ignores local caches and runtime state:

```gitignore
/graphify-out/cache/
/graphify-out/cost.json
/graphify-out/.graphify_*
/graphify-out/needs_update
/graphify-out/.needs_update
```

Portable outputs such as `graph.json`, `manifest.json`, and `GRAPH_REPORT.md` remain available to commit and share with the team.

With `--local`, the entire `graphify-out/` directory is ignored instead.

## Requirements

- Bash 4+
- Git
- `curl` when `uv` must be installed
- An interactive terminal, including when using `curl | bash`

Designed for Linux, macOS, and WSL.

## Development

```bash
bash -n graphify-init install.sh tests/test-graphify-init.sh
bash tests/test-graphify-init.sh
```
