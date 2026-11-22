#!/usr/bin/env bash
# Runs every repository-level check. Used locally and by CI, so both always
# agree. In CI (CI=true) a missing linter is an error; locally it is skipped.
set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1

failed=0
step() { printf '\n== %s\n' "$*"; }
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failed=1
}
need() {
  # need <tool>: 0 if available, 1 if it may be skipped; fails the run in CI.
  command -v "$1" >/dev/null 2>&1 && return 0
  if [ "${CI:-}" = "true" ]; then
    fail "$1 is required in CI but not installed"
  else
    printf 'skip: %s not installed\n' "$1"
  fi
  return 1
}

shell_files=()
while IFS= read -r -d '' f; do
  case "$f" in
    *.sh | .githooks/*) shell_files+=("$f") ;;
  esac
done < <(git ls-files -z --cached --others --exclude-standard)

step "Secret scan (tracked and not-yet-tracked files)"
# Scan what `git add -A` would commit, using a throwaway index so the real
# staging area is left untouched.
scan_dir=$(mktemp -d "${TMPDIR:-/tmp}/check-index.XXXXXX")
real_index=$(git rev-parse --git-path index)
if [ -f "$real_index" ]; then
  cp "$real_index" "$scan_dir/index"
fi
if GIT_INDEX_FILE="$scan_dir/index" git add -A &&
  GIT_INDEX_FILE="$scan_dir/index" scripts/scan-secrets.sh --all; then
  printf 'clean\n'
else
  fail "secret scan"
fi
rm -rf "$scan_dir"

step "gitleaks (git history and uncommitted changes)"
# Optional everywhere, including CI: the workflow runs gitleaks in its own job
# with the full history, so this step only adds depth when the tool is present.
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks_scan=(gitleaks git --redact --no-banner --exit-code 1)
  "${gitleaks_scan[@]}" . || fail "gitleaks: secrets in the git history"
  "${gitleaks_scan[@]}" --pre-commit --staged . || fail "gitleaks: secrets in staged changes"
  "${gitleaks_scan[@]}" --pre-commit . || fail "gitleaks: secrets in unstaged changes"
else
  printf 'skip: gitleaks not installed (optional; CI runs it in its own job)\n'
fi

step "Shell syntax"
for f in "${shell_files[@]}"; do
  bash -n "$f" || fail "syntax error in $f"
done
printf '%s file(s) parsed\n' "${#shell_files[@]}"

step "shellcheck"
if need shellcheck; then
  shellcheck -x "${shell_files[@]}" || fail "shellcheck"
fi

step "Claude Code configuration"
if need python3; then
  python3 - <<'PY' || fail "Claude Code configuration"
import ast, glob, json, sys

ok = True
for path in glob.glob(".claude/*.json"):
    try:
        json.load(open(path))
    except ValueError as exc:
        print(f"{path}: invalid JSON: {exc}", file=sys.stderr)
        ok = False
for path in glob.glob(".claude/hooks/*.py"):
    try:
        ast.parse(open(path).read(), path)
    except SyntaxError as exc:
        print(f"{path}: {exc}", file=sys.stderr)
        ok = False
print("settings and hook scripts parse" if ok else "errors found")
sys.exit(0 if ok else 1)
PY
fi

step "Workflows: third-party actions pinned to a commit SHA"
unpinned=$(grep -rnE '^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]' .github/workflows 2>/dev/null |
  grep -vE 'uses:[[:space:]]+(\./|docker://[^[:space:]]+@sha256:[0-9a-f]{64}|[^@[:space:]]+@[0-9a-f]{40}([[:space:]]|$))' || true)
if [ -n "$unpinned" ]; then
  printf '%s\n' "$unpinned" >&2
  fail "actions must be pinned to a full commit SHA"
else
  printf 'all pinned\n'
fi

step "actionlint"
if need actionlint; then
  actionlint || fail "actionlint"
fi

step "Hook settings (.hooksconfig)"
if [ -f .hooksconfig ]; then
  if git config --no-includes --file .hooksconfig --list >/dev/null; then
    printf 'parses\n'
  else
    fail ".hooksconfig is not valid git-config syntax"
  fi
else
  printf 'none (built-in defaults apply)\n'
fi

step "Starter placeholders (scripts/init.sh)"
# A project created from the starter must have run scripts/init.sh. Only the
# template's own source is allowed to keep the placeholders.
if [ "${TEMPLATE_SOURCE:-}" = 1 ]; then
  printf 'skip: template source, placeholders are expected\n'
elif [ -x scripts/init.sh ]; then
  if scripts/init.sh --check; then printf 'none left\n'; else fail "starter placeholders remain"; fi
else
  printf 'no init script\n'
fi

step "Guardrail self-test"
scripts/selftest.sh || fail "self-test"

step "Project checks (scripts/check.d)"
# Extension point: every tracked, executable file in scripts/check.d runs here,
# in name order. Add build, lint and test steps for your stack as files there.
extra_checks=0
while IFS= read -r -d '' f; do
  [ -x "$f" ] || continue
  extra_checks=$((extra_checks + 1))
  printf -- '-- %s\n' "$f"
  "$f" || fail "$f"
done < <(git ls-files -z -- 'scripts/check.d/*' | sort -z)
[ "$extra_checks" -gt 0 ] || printf 'none\n'

printf '\n'
if [ "$failed" -ne 0 ]; then
  printf 'check: FAILED\n' >&2
  exit 1
fi
printf 'check: all checks passed\n'
