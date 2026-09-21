# Graphify Init Design

## Goal

Initialize Graphify for the current Git repository with a repeatable, code-only workflow and project-scoped agent integration.

## Entry points

- Installed: `install.sh` downloads `graphify-init` to `~/.local/bin/graphify-init`.
- One-shot: pipe the same `graphify-init` executable directly to Bash.
- Initialization logic exists only in `graphify-init`; `install.sh` only installs it.

## Initialization flow

1. Require an interactive terminal and a Git repository.
2. If `uv` is absent, ask permission to install it; decline exits without further changes.
3. If `graphify` is absent, ask permission to install `graphifyy` with `uv tool install`; decline exits without further changes.
4. Select the agent platform with arrow keys and Enter.
5. Idempotently update `.gitignore` and `.graphifyignore` using managed blocks.
6. Install the selected Graphify skill and always-on integration with project scope only.
7. Run the initial local AST extraction with `graphify extract . --code-only`.
8. Install Graphify Git hooks and display their status.

The initializer never installs a user-global Graphify skill.

## Git policy

Commit Graphify's portable/shared outputs when present:

- `graphify-out/graph.json`
- `graphify-out/manifest.json`
- `graphify-out/GRAPH_REPORT.md`
- `graphify-out/graph.html` when visualization is explicitly generated
- project-scoped agent skill and integration files
- `.graphifyignore`

Add these local/runtime artifacts to `.gitignore`:

```gitignore
# graphify-init: local and generated state
/graphify-out/cache/
/graphify-out/cost.json
/graphify-out/.graphify_*
/graphify-out/needs_update
/graphify-out/.needs_update
```

Do not automatically classify optional exports such as `memory/`, `reflections/`, `wiki/`, `obsidian/`, or `converted/`; teams may intentionally share them.

## Ignore behavior

Graphify already respects `.gitignore` and internally skips common dependency, IDE, cache, and build directories. `.graphifyignore` remains conservative and is used only for Graphify-specific exclusions, avoiding broad patterns that could hide real source files.

## Safety and idempotency

- Default every installation prompt to No.
- Refuse non-interactive dependency installation.
- Append each managed block at most once and preserve existing file content.
- Quote paths and avoid executing downloaded content except through the user's explicit one-shot command.
- Stop immediately when a required command fails.

## Verification

- Shell syntax validation with `bash -n`.
- Automated tests with stubbed `uv`, `graphify`, and `git` commands for installed, missing, accepted, declined, and repeated-run paths.
- Manual smoke test in a temporary Git repository.
