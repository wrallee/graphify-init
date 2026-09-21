# Graphify Init Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Subagent-driven development is prohibited for this project.

**Goal:** Ship a public Bash utility that installs or runs once to configure Graphify safely in the current Git repository.

**Architecture:** A single executable, `graphify-init`, owns every initialization behavior. `install.sh` only downloads that executable into a user-selected bin directory, so installed and one-shot usage cannot drift. Plain Bash tests exercise the executable through stubbed commands and isolated temporary repositories.

**Tech Stack:** Bash 4+, Git, curl, uv, Graphify CLI, plain Bash test harness

**Spec:** `docs/specs/2026-09-22-graphify-init.md`

## Global Constraints

- Dependency installation prompts default to No and refusal exits without continuing.
- The initializer installs Graphify integrations only with project scope; it never installs a user-global Graphify skill.
- Initial extraction is local AST only and makes no LLM call.
- `graphify-out/cache/`, `cost.json`, hidden Graphify runtime files, and update markers remain untracked.
- Existing `.gitignore` and `.graphifyignore` content must be preserved.
- Both `curl | bash` and installed-command execution must read interactive input from the terminal rather than standard input.
- The implementation uses no runtime dependency beyond commands already required by the workflow.

## Review Focus

- `curl | bash` consumes standard input: prompts and arrow-key selection must still use `/dev/tty`.
- A partially installed `uv` may not yet be on `PATH`: refresh the current process path before testing the command.
- Existing managed ignore blocks may be incomplete or manually modified: repeated runs must not duplicate entries.
- Platform commands differ between generic skill installers and platform-specific installers: each menu choice must run the documented project-scoped commands only.
- Failure after modifying ignore files must return a non-zero status and clearly name the failed Graphify step.

---

### Task 1: Initialization executable and dependency prompts

**Files:**
- Create: `graphify-init`
- Create: `tests/test_graphify-init.sh`

**Interfaces:**
- Consumes: Git repository state, `/dev/tty`, `uv`, and `graphify` commands.
- Produces: executable `graphify-init`; shell functions `confirm`, `ensure_uv`, `ensure_graphify`, `append_managed_block`, `select_platform`, and `run_initialization`.

- [ ] **Step 1: Write failing dependency and precondition tests**

Create a plain Bash harness that builds a temporary Git repository, prepends stub commands to `PATH`, and verifies:

```bash
run_case outside-git
assert_status 1
assert_output_contains "run this inside a Git repository"

run_case missing-uv-decline --answers $'n\n'
assert_status 1
assert_not_called graphify

run_case missing-graphify-decline --answers $'n\n'
assert_status 1
assert_called uv
```

- [ ] **Step 2: Run tests and verify failure**

Run: `bash tests/test_graphify-init.sh`

Expected: FAIL because `graphify-init` does not exist.

- [ ] **Step 3: Implement terminal input and dependency checks**

Implement:

```bash
confirm "uv is not installed. Install it now?" || exit 1
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"

confirm "Graphify is not installed. Install it now?" || exit 1
uv tool install graphifyy
```

All prompts read from a dedicated terminal descriptor. Validate each installed command before proceeding and show actionable PATH guidance on failure.

- [ ] **Step 4: Run dependency tests**

Run: `bash tests/test_graphify-init.sh`

Expected: dependency and Git precondition cases PASS.

- [ ] **Step 5: Commit**

```bash
git add graphify-init tests/test_graphify-init.sh
git commit -m "feat: add dependency-aware initializer"
```

### Task 2: Platform selection and Graphify initialization

**Files:**
- Modify: `graphify-init`
- Modify: `tests/test_graphify-init.sh`

**Interfaces:**
- Consumes: validated `graphify` command and a selected platform identifier.
- Produces: project-scoped skill/config files, `graphify-out/graph.json`, `GRAPH_REPORT.md`, and Git hooks.

- [ ] **Step 1: Add failing platform command tests**

Use key-sequence fixtures for Up, Down, and Enter, then assert the Graphify stub receives these exact project-scoped flows:

```text
codex:      install --project --platform codex; codex install --project
claude:     install --project; claude install --project
gemini:     install --project --platform gemini; gemini install --project
opencode:   install --project --platform opencode; opencode install --project
cursor:     cursor install --project
antigravity: antigravity install --project
```

Every platform then runs:

```text
extract . --code-only
cluster-only . --no-viz --no-label
hook install
hook status
```

- [ ] **Step 2: Run the platform tests and verify failure**

Run: `bash tests/test_graphify-init.sh`

Expected: FAIL because menu navigation and platform mappings are absent.

- [ ] **Step 3: Implement the arrow-key menu and platform mappings**

Render six platforms, keep selection within bounds, restore cursor visibility on exit, and run only the selected platform's documented project-scoped commands. Stop on the first failed command.

- [ ] **Step 4: Run platform tests**

Run: `bash tests/test_graphify-init.sh`

Expected: all six mappings and initialization sequence cases PASS.

- [ ] **Step 5: Commit**

```bash
git add graphify-init tests/test_graphify-init.sh
git commit -m "feat: add project-scoped Graphify setup"
```

### Task 3: Idempotent ignore policy

**Files:**
- Modify: `graphify-init`
- Modify: `tests/test_graphify-init.sh`

**Interfaces:**
- Consumes: repository-root `.gitignore` and `.graphifyignore`, which may be absent or populated.
- Produces: one managed block in each file without altering unrelated content.

- [ ] **Step 1: Add failing ignore-file tests**

Verify a first run adds the exact `.gitignore` block:

```gitignore
# graphify-init: local and generated state
/graphify-out/cache/
/graphify-out/cost.json
/graphify-out/.graphify_*
/graphify-out/needs_update
/graphify-out/.needs_update
```

Verify `.graphifyignore` excludes project-installed Graphify skill directories without duplicating Graphify's built-in build/dependency exclusions. Run initialization twice and assert each marker occurs exactly once while pre-existing lines remain byte-for-byte present.

- [ ] **Step 2: Run ignore tests and verify failure**

Run: `bash tests/test_graphify-init.sh`

Expected: FAIL because ignore-file management is absent.

- [ ] **Step 3: Implement managed-block updates**

Append a newline only when required, use start/end markers, replace an existing managed block atomically, and preserve all content outside that block.

- [ ] **Step 4: Run ignore tests**

Run: `bash tests/test_graphify-init.sh`

Expected: first-run, repeat-run, and pre-existing-content cases PASS.

- [ ] **Step 5: Commit**

```bash
git add graphify-init tests/test_graphify-init.sh
git commit -m "feat: manage Graphify ignore policy"
```

### Task 4: Installer and user documentation

**Files:**
- Create: `install.sh`
- Create: `README.md`
- Modify: `tests/test-graphify-init.sh`

**Interfaces:**
- Consumes: raw GitHub URL, `curl`, writable `${INSTALL_DIR:-$HOME/.local/bin}`.
- Produces: installed executable `${INSTALL_DIR:-$HOME/.local/bin}/graphify-init` and documented one-shot command.

- [ ] **Step 1: Add failing installer tests**

Stub `curl` and verify:

```bash
INSTALL_DIR="$tmp/bin" bash install.sh
test -x "$tmp/bin/graphify-init"
cmp "$tmp/bin/graphify-init" graphify-init
```

Also verify a download failure leaves no partial executable and returns non-zero.

- [ ] **Step 2: Run installer tests and verify failure**

Run: `bash tests/test-graphify-init.sh`

Expected: FAIL because `install.sh` is absent.

- [ ] **Step 3: Implement `install.sh` and README**

Document exactly two entry points:

```bash
curl -fsSL https://raw.githubusercontent.com/wrallee/graphify-init/main/install.sh | bash
curl -fsSL https://raw.githubusercontent.com/wrallee/graphify-init/main/graphify-init | bash
```

The installer downloads to a temporary file in the destination, validates it with `bash -n`, sets executable permissions, and renames it atomically.

- [ ] **Step 4: Run all tests and syntax checks**

Run:

```bash
bash -n graphify-init install.sh tests/test-graphify-init.sh
bash tests/test-graphify-init.sh
```

Expected: all checks PASS.

- [ ] **Step 5: Commit**

```bash
git add install.sh README.md tests/test-graphify-init.sh
git commit -m "docs: add installer and usage guide"
```

### Task 5: Final verification and publication

**Files:**
- Modify only if verification finds defects.

**Interfaces:**
- Consumes: clean local `main` branch with all prior task commits.
- Produces: public `wrallee/graphify-init` repository with verified `main`.

- [ ] **Step 1: Run a temporary-repository smoke test**

Run the one-shot executable against a temporary Git repository with stubbed dependency commands, select Codex, and verify command order, managed ignores, and successful exit.

- [ ] **Step 2: Review the staged Git history and worktree**

Run:

```bash
git status --short
git log --oneline --decorate -5
```

Expected: clean worktree and coherent task-level commits.

- [ ] **Step 3: Create and publish the repository**

Create public repository `wrallee/graphify-init`, add it as `origin`, and push `main`. Confirm the repository page and both raw download URLs are reachable.

