#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/graphify-init"
INSTALLER="$ROOT/install.sh"
PASS=0
FAIL=0
CASE_DIR=""
STATUS=0
OUTPUT=""

cleanup() {
  if [[ -n "$CASE_DIR" && -d "$CASE_DIR" ]]; then
    rm -rf "$CASE_DIR"
  fi
}
trap cleanup EXIT

pass() {
  PASS=$((PASS + 1))
  printf 'ok - %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf 'not ok - %s\n' "$1"
  [[ -z "$OUTPUT" ]] || printf '%s\n' "$OUTPUT" | sed 's/^/  /'
}

assert_status() {
  local expected=$1 name=$2
  if [[ "$STATUS" -eq "$expected" ]]; then pass "$name"; else fail "$name (expected status $expected, got $STATUS)"; fi
}

assert_output_contains() {
  local expected=$1 name=$2
  if [[ "$OUTPUT" == *"$expected"* ]]; then pass "$name"; else fail "$name (missing: $expected)"; fi
}

assert_log_excludes() {
  local unexpected=$1 name=$2
  if [[ ! -f "$CASE_DIR/calls.log" ]] || ! grep -Fq "$unexpected" "$CASE_DIR/calls.log"; then
    pass "$name"
  else
    fail "$name (unexpected call: $unexpected)"
  fi
}

assert_log_contains() {
  local expected=$1 name=$2
  if [[ -f "$CASE_DIR/calls.log" ]] && grep -Fxq "$expected" "$CASE_DIR/calls.log"; then
    pass "$name"
  else
    fail "$name (missing call: $expected)"
  fi
}

assert_log_equals() {
  local expected=$1 name=$2 actual
  actual=$(cat "$CASE_DIR/calls.log")
  if [[ "$actual" == "$expected" ]]; then
    pass "$name"
  else
    OUTPUT=$(printf 'expected:\n%s\nactual:\n%s' "$expected" "$actual")
    fail "$name"
  fi
}

assert_file_equals() {
  local file=$1 expected=$2 name=$3 actual
  actual=$(cat "$file")
  if [[ "$actual" == "$expected" ]]; then
    pass "$name"
  else
    OUTPUT=$(printf 'expected:\n%s\nactual:\n%s' "$expected" "$actual")
    fail "$name"
  fi
}

assert_count() {
  local expected=$1 pattern=$2 file=$3 name=$4 actual
  actual=$(grep -Fc "$pattern" "$file" || true)
  if [[ "$actual" -eq "$expected" ]]; then pass "$name"; else fail "$name (expected $expected, got $actual)"; fi
}

new_case() {
  cleanup
  CASE_DIR=$(mktemp -d)
  mkdir -p "$CASE_DIR/bin" "$CASE_DIR/home/.local/bin" "$CASE_DIR/repo"
  : > "$CASE_DIR/calls.log"
}

write_stub() {
  local name=$1
  shift
  {
    printf '#!/usr/bin/env bash\n'
    printf '%s\n' "$@"
  } > "$CASE_DIR/bin/$name"
  chmod +x "$CASE_DIR/bin/$name"
}

run_script() {
  local workdir=$1 answers=$2 mode=${3:-file}
  printf '%s' "$answers" > "$CASE_DIR/answers"
  set +e
  if [[ "$mode" == "stdin" ]]; then
    OUTPUT=$(cd "$workdir" && env \
      HOME="$CASE_DIR/home" \
      PATH="$CASE_DIR/bin:/usr/bin:/bin" \
      GRAPHIFY_INIT_TTY="$CASE_DIR/answers" \
      GRAPHIFY_INIT_TEST_STOP_AFTER_DEPS=1 \
      GRAPHIFY_INIT_CALL_LOG="$CASE_DIR/calls.log" \
      GRAPHIFY_INIT_FAIL_STEP="${GRAPHIFY_INIT_FAIL_STEP:-}" \
      GRAPHIFY_INIT_FAKE_UV_INSTALLER="$CASE_DIR/uv-installer" \
      bash -s < "$SCRIPT" 2>&1)
  else
    OUTPUT=$(cd "$workdir" && env \
      HOME="$CASE_DIR/home" \
      PATH="$CASE_DIR/bin:/usr/bin:/bin" \
      GRAPHIFY_INIT_TTY="$CASE_DIR/answers" \
      GRAPHIFY_INIT_TEST_STOP_AFTER_DEPS=1 \
      GRAPHIFY_INIT_CALL_LOG="$CASE_DIR/calls.log" \
      GRAPHIFY_INIT_FAIL_STEP="${GRAPHIFY_INIT_FAIL_STEP:-}" \
      GRAPHIFY_INIT_FAKE_UV_INSTALLER="$CASE_DIR/uv-installer" \
      bash "$SCRIPT" 2>&1)
  fi
  STATUS=$?
  set -e
}

run_installer() {
  set +e
  OUTPUT=$(env \
    HOME="$CASE_DIR/home" \
    PATH="$CASE_DIR/bin:/usr/bin:/bin" \
    INSTALL_DIR="$CASE_DIR/install-bin" \
    GRAPHIFY_INIT_FAKE_DOWNLOAD="$SCRIPT" \
    bash "$INSTALLER" 2>&1)
  STATUS=$?
  set -e
}

test_rejects_non_git_directory() {
  new_case
  write_stub uv 'exit 0'
  write_stub graphify 'exit 0'
  run_script "$CASE_DIR/repo" ''
  assert_status 1 "outside Git repository exits"
  assert_output_contains "run this inside a Git repository" "outside Git repository explains failure"
}

test_declining_uv_stops_one_shot_execution() {
  new_case
  write_stub curl 'printf "%s\\n" curl >> "$GRAPHIFY_INIT_CALL_LOG"' 'exit 99'
  git -C "$CASE_DIR/repo" init -q
  run_script "$CASE_DIR/repo" $'n\n' stdin
  assert_status 1 "declining uv exits"
  assert_output_contains "uv is not installed" "missing uv prompts for installation"
  assert_log_excludes "curl" "declining uv does not download installer"
}

test_declining_graphify_stops_before_uv_tool_install() {
  new_case
  write_stub uv 'printf "%s\\n" "uv $*" >> "$GRAPHIFY_INIT_CALL_LOG"' 'exit 0'
  git -C "$CASE_DIR/repo" init -q
  run_script "$CASE_DIR/repo" $'n\n'
  assert_status 1 "declining Graphify exits"
  assert_output_contains "Graphify is not installed" "missing Graphify prompts for installation"
  assert_log_excludes "uv tool install graphifyy" "declining Graphify skips installation"
}

test_accepting_uv_runs_official_installer_and_refreshes_path() {
  new_case
  cat > "$CASE_DIR/uv-installer" <<'INSTALLER'
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/uv" <<'UV'
#!/usr/bin/env bash
printf '%s\n' "uv $*" >> "$GRAPHIFY_INIT_CALL_LOG"
exit 0
UV
chmod +x "$HOME/.local/bin/uv"
INSTALLER
  write_stub curl \
    'printf "%s\\n" "curl $*" >> "$GRAPHIFY_INIT_CALL_LOG"' \
    'cat "$GRAPHIFY_INIT_FAKE_UV_INSTALLER"'
  git -C "$CASE_DIR/repo" init -q
  run_script "$CASE_DIR/repo" $'y\nn\n'
  assert_status 1 "accepted uv install reaches Graphify prompt"
  assert_output_contains "Graphify is not installed" "uv path refresh finds installed uv"
  if grep -Fq "https://astral.sh/uv/install.sh" "$CASE_DIR/calls.log"; then
    pass "uv uses official installer"
  else
    fail "uv uses official installer"
  fi
}

test_accepting_graphify_uses_official_package() {
  new_case
  write_stub uv \
    'printf "%s\\n" "uv $*" >> "$GRAPHIFY_INIT_CALL_LOG"' \
    'if [[ "$*" == "tool install graphifyy" ]]; then' \
    '  printf "#!/usr/bin/env bash\\nexit 0\\n" > "$HOME/.local/bin/graphify"' \
    '  chmod +x "$HOME/.local/bin/graphify"' \
    'fi'
  git -C "$CASE_DIR/repo" init -q
  run_script "$CASE_DIR/repo" $'y\n\n'
  assert_status 0 "accepting Graphify installation continues"
  if grep -Fxq "uv tool install graphifyy" "$CASE_DIR/calls.log"; then
    pass "Graphify installs official graphifyy package"
  else
    fail "Graphify installs official graphifyy package"
  fi
}

test_platform_flow() {
  local name=$1 down_count=$2 integration=$3 answers='' i
  new_case
  write_stub uv 'exit 0'
  write_stub graphify 'printf "%s\\n" "graphify $*" >> "$GRAPHIFY_INIT_CALL_LOG"'
  git -C "$CASE_DIR/repo" init -q
  for ((i = 0; i < down_count; i++)); do
    answers+=$'\e[B'
  done
  answers+=$'\n'
  run_script "$CASE_DIR/repo" "$answers"
  assert_status 0 "$name initialization succeeds"
  assert_log_equals "$integration
graphify extract . --code-only
graphify cluster-only . --no-viz --no-label
graphify hook install
graphify hook status" "$name uses project-scoped command sequence"
}

test_up_arrow_stays_on_first_platform() {
  new_case
  write_stub uv 'exit 0'
  write_stub graphify 'printf "%s\\n" "graphify $*" >> "$GRAPHIFY_INIT_CALL_LOG"'
  git -C "$CASE_DIR/repo" init -q
  run_script "$CASE_DIR/repo" $'\e[A\n'
  assert_status 0 "up arrow at first platform succeeds"
  if head -n 1 "$CASE_DIR/calls.log" | grep -Fxq "graphify install --project --platform codex"; then
    pass "up arrow cannot move before first platform"
  else
    fail "up arrow cannot move before first platform"
  fi
}

test_ignore_files_are_preserved_and_managed_idempotently() {
  local expected_gitignore expected_graphifyignore
  new_case
  write_stub uv 'exit 0'
  write_stub graphify 'printf "%s\\n" "graphify $*" >> "$GRAPHIFY_INIT_CALL_LOG"'
  git -C "$CASE_DIR/repo" init -q
  printf 'existing-rule' > "$CASE_DIR/repo/.gitignore"
  printf 'tracked-generated/\n' > "$CASE_DIR/repo/.graphifyignore"

  run_script "$CASE_DIR/repo" $'\n'
  assert_status 0 "first ignore update succeeds"
  run_script "$CASE_DIR/repo" $'\n'
  assert_status 0 "second ignore update succeeds"

  expected_gitignore=$(cat <<'EOF'
existing-rule
# >>> graphify-init >>>
# graphify-init: local and generated state
/graphify-out/cache/
/graphify-out/cost.json
/graphify-out/.graphify_*
/graphify-out/needs_update
/graphify-out/.needs_update
# <<< graphify-init <<<
EOF
)
  expected_graphifyignore=$(cat <<'EOF'
tracked-generated/
# >>> graphify-init >>>
# graphify-init: exclude installed Graphify skill sources
**/skills/graphify/
# <<< graphify-init <<<
EOF
)

  assert_file_equals "$CASE_DIR/repo/.gitignore" "$expected_gitignore" "gitignore preserves content and policy"
  assert_file_equals "$CASE_DIR/repo/.graphifyignore" "$expected_graphifyignore" "graphifyignore stays conservative"
  assert_count 1 "# >>> graphify-init >>>" "$CASE_DIR/repo/.gitignore" "gitignore managed block is unique"
  assert_count 1 "# >>> graphify-init >>>" "$CASE_DIR/repo/.graphifyignore" "graphifyignore managed block is unique"
}

test_malformed_managed_block_fails_without_data_loss() {
  local original
  new_case
  write_stub uv 'exit 0'
  write_stub graphify 'exit 0'
  git -C "$CASE_DIR/repo" init -q
  original=$'keep-me\n# >>> graphify-init >>>\nuser-rule-after-broken-marker'
  printf '%s' "$original" > "$CASE_DIR/repo/.gitignore"

  run_script "$CASE_DIR/repo" $'\n'
  assert_status 1 "malformed managed block stops initialization"
  assert_file_equals "$CASE_DIR/repo/.gitignore" "$original" "malformed managed block preserves file"
}

test_crlf_managed_block_is_replaced_without_duplication() {
  new_case
  write_stub uv 'exit 0'
  write_stub graphify 'printf "%s\\n" "graphify $*" >> "$GRAPHIFY_INIT_CALL_LOG"'
  git -C "$CASE_DIR/repo" init -q
  printf 'keep-me\r\n# >>> graphify-init >>>\r\nold-policy\r\n# <<< graphify-init <<<\r\n' > "$CASE_DIR/repo/.gitignore"

  run_script "$CASE_DIR/repo" $'\n'
  assert_status 0 "CRLF managed block update succeeds"
  assert_count 1 "# >>> graphify-init >>>" "$CASE_DIR/repo/.gitignore" "CRLF managed block is not duplicated"
  if ! grep -Fq "old-policy" "$CASE_DIR/repo/.gitignore"; then pass "CRLF managed content is replaced"; else fail "CRLF managed content is replaced"; fi
}

test_malformed_crlf_managed_block_fails_without_data_loss() {
  local original
  new_case
  write_stub uv 'exit 0'
  write_stub graphify 'exit 0'
  git -C "$CASE_DIR/repo" init -q
  original=$'keep-me\r\n# >>> graphify-init >>>\r\nbroken\r\n'
  printf '%s' "$original" > "$CASE_DIR/repo/.gitignore"
  cp "$CASE_DIR/repo/.gitignore" "$CASE_DIR/original.gitignore"

  run_script "$CASE_DIR/repo" $'\n'
  assert_status 1 "malformed CRLF managed block stops initialization"
  if cmp -s "$CASE_DIR/repo/.gitignore" "$CASE_DIR/original.gitignore"; then
    pass "malformed CRLF block preserves file"
  else
    fail "malformed CRLF block preserves file"
  fi
}

test_graphify_failure_names_step_and_stops() {
  local failed_command=$1 expected_name=$2 next_command=$3
  new_case
  write_stub uv 'exit 0'
  write_stub graphify \
    'printf "%s\\n" "graphify $*" >> "$GRAPHIFY_INIT_CALL_LOG"' \
    'if [[ "$*" == "$GRAPHIFY_INIT_FAIL_STEP" ]]; then exit 42; fi'
  git -C "$CASE_DIR/repo" init -q

  GRAPHIFY_INIT_FAIL_STEP="$failed_command" run_script "$CASE_DIR/repo" $'\n'
  assert_status 42 "$expected_name failure preserves exit status"
  assert_output_contains "ERROR: Graphify step failed: $expected_name" "$expected_name failure is identified"
  assert_log_contains "graphify $failed_command" "$expected_name failing command runs"
  assert_log_excludes "graphify $next_command" "$expected_name failure stops later commands"
}

test_installer_downloads_validated_executable() {
  new_case
  write_stub curl \
    'out=""' \
    'while (($#)); do' \
    '  if [[ "$1" == "-o" ]]; then out=$2; shift 2; else shift; fi' \
    'done' \
    'cp "$GRAPHIFY_INIT_FAKE_DOWNLOAD" "$out"'
  run_installer
  assert_status 0 "installer succeeds"
  if [[ -x "$CASE_DIR/install-bin/graphify-init" ]]; then pass "installer creates executable"; else fail "installer creates executable"; fi
  if cmp -s "$SCRIPT" "$CASE_DIR/install-bin/graphify-init"; then pass "installer preserves downloaded script"; else fail "installer preserves downloaded script"; fi
}

test_installer_failure_leaves_no_partial_file() {
  new_case
  write_stub curl 'exit 22'
  run_installer
  assert_status 1 "download failure exits"
  if [[ ! -e "$CASE_DIR/install-bin/graphify-init" ]] && ! find "$CASE_DIR/install-bin" -type f -print -quit 2>/dev/null | grep -q .; then
    pass "download failure leaves no partial file"
  else
    fail "download failure leaves no partial file"
  fi
}

test_rejects_non_git_directory
test_declining_uv_stops_one_shot_execution
test_declining_graphify_stops_before_uv_tool_install
test_accepting_uv_runs_official_installer_and_refreshes_path
test_accepting_graphify_uses_official_package
test_platform_flow "Codex" 0 $'graphify install --project --platform codex\ngraphify codex install --project'
test_platform_flow "Claude Code" 1 $'graphify install --project\ngraphify claude install --project'
test_platform_flow "Gemini CLI" 2 $'graphify install --project --platform gemini\ngraphify gemini install --project'
test_platform_flow "OpenCode" 3 $'graphify install --project --platform opencode\ngraphify opencode install --project'
test_platform_flow "Cursor" 4 'graphify cursor install --project'
test_platform_flow "Antigravity" 5 'graphify antigravity install --project'
test_up_arrow_stays_on_first_platform
test_ignore_files_are_preserved_and_managed_idempotently
test_malformed_managed_block_fails_without_data_loss
test_crlf_managed_block_is_replaced_without_duplication
test_malformed_crlf_managed_block_fails_without_data_loss
test_graphify_failure_names_step_and_stops 'install --project --platform codex' 'project integration' 'codex install --project'
test_graphify_failure_names_step_and_stops 'extract . --code-only' 'code extraction' 'cluster-only . --no-viz --no-label'
test_graphify_failure_names_step_and_stops 'cluster-only . --no-viz --no-label' 'code clustering' 'hook install'
test_graphify_failure_names_step_and_stops 'hook install' 'hook installation' 'hook status'
test_graphify_failure_names_step_and_stops 'hook status' 'hook status check' 'never-called'
test_installer_downloads_validated_executable
test_installer_failure_leaves_no_partial_file

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
