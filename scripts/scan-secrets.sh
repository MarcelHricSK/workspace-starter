#!/usr/bin/env bash
# Dependency-free secret scanner (git + bash + grep + awk only).
#
#   scripts/scan-secrets.sh --staged              lines and files staged for commit
#   scripts/scan-secrets.sh --all                 every tracked file in the index
#   scripts/scan-secrets.sh --range <git-log-args> lines added by those commits
#
# It is a fast first line of defence, not a replacement for a full scanner:
# CI runs gitleaks over the whole history as the authoritative check.
#
# False positives:
#   - append "gitleaks:allow" to the offending line, or
#   - add a path regex to .secretscanignore (one ERE per line, matched against
#     the repository-relative path).
set -euo pipefail

usage() {
  sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

mode=""
range_args=()
case "${1:-}" in
  --staged) mode=staged ;;
  --all) mode=all ;;
  --range)
    mode=range
    shift
    [ "${1:-}" = "--" ] && shift
    [ "$#" -gt 0 ] || usage
    range_args=("$@")
    ;;
  *) usage ;;
esac

cd "$(git rev-parse --show-toplevel)"

TAB=$'\t'
ALLOW_MARKER='gitleaks:allow'
IGNORE_FILE=.secretscanignore
[ -f "$IGNORE_FILE" ] || IGNORE_FILE=/dev/null

tmp=$(mktemp -d "${TMPDIR:-/tmp}/scan-secrets.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

# --- Patterns ---------------------------------------------------------------
# High-confidence token formats. One POSIX ERE per line, case-sensitive.
cat >"$tmp/strict" <<'EOF'
-----BEGIN [A-Z ]*PRIVATE KEY
(^|[^A-Za-z0-9/+])(A3T[A-Z0-9]|AKIA|ASIA|ABIA|ACCA)[A-Z0-9]{16}([^A-Za-z0-9/+=]|$)
gh[pousr]_[A-Za-z0-9]{36,}
github_pat_[A-Za-z0-9_]{22,}
glpat-[A-Za-z0-9_-]{20,}
xox[abeoprs]-[A-Za-z0-9-]{10,}
hooks\.slack\.com/services/T[A-Za-z0-9_]+/B[A-Za-z0-9_]+/[A-Za-z0-9_]+
AIza[0-9A-Za-z_-]{35}
[rs]k_live_[0-9a-zA-Z]{20,}
sk-ant-[A-Za-z0-9_-]{20,}
sk-(proj|svcacct|admin)-[A-Za-z0-9_-]{20,}
npm_[A-Za-z0-9]{36}
_authToken=[A-Za-z0-9_-]{8,}
eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}
EOF

# Generic shapes: quoted literal assigned to a secret-looking name, and URLs
# with inline credentials. Case-insensitive, and skipped when the line looks
# like a placeholder or an environment lookup.
generic_re='(password|passwd|secret|token|api[_-]?key|access[_-]?key|private[_-]?key|client[_-]?secret)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"'[:space:]]{12,}["'"'"']'
generic_re="${generic_re}"'|[a-z][a-z0-9+.-]*://[A-Za-z0-9._~%-]+:[A-Za-z0-9._~%!$&*+,;=-]{3,}@[A-Za-z0-9.-]'
placeholder_re='example|placeholder|changeme|change[_-]me|your[_-]|dummy|redacted|xxxx|\*\*\*\*|<[^>]+>|\$\{|\{\{|process\.env|os\.environ|getenv|localhost|127\.0\.0\.1'

# --- Forbidden file names ---------------------------------------------------
bad_names=0
check_names() {
  local f base
  shopt -s nocasematch
  while IFS= read -r -d '' f; do
    [ -n "$f" ] || continue
    base=${f##*/}
    case "$base" in
      .env.example | .env.sample | .env.template) ;;
      .env | .env.* | *.pem | *.key | *.p12 | *.pfx | *.jks | *.keystore | *.kdbx | \
        id_rsa | id_dsa | id_ecdsa | id_ed25519 | .netrc | .pgpass | .htpasswd)
        if ! grep -qE -f "$tmp/ignore_names" <<<"$f" 2>/dev/null; then
          printf '  %s\n' "$f" >>"$tmp/names"
          bad_names=$((bad_names + 1))
        fi
        ;;
    esac
  done
  shopt -u nocasematch
}

# Path ignore list without comments/blank lines (may be empty).
grep -vE '^[[:space:]]*(#|$)' "$IGNORE_FILE" >"$tmp/ignore_names" || true
[ -s "$tmp/ignore_names" ] || printf '%s\n' '^$' >"$tmp/ignore_names"

# --- Collect added lines as "<location>\t<content>" -------------------------
extract() {
  awk -v ignorefile="$tmp/ignore_names" '
    BEGIN { n = 0; while ((getline p < ignorefile) > 0) pats[n++] = p }
    /^commit:/ { commit = substr($0, 8, 10); next }
    /^diff --git / { hdr = 1; next }
    hdr && /^\+\+\+ / {
      file = substr($0, 5); sub(/^b\//, "", file); sub(/\t$/, "", file)
      skip = 0
      for (i = 0; i < n; i++) if (file ~ pats[i]) skip = 1
      next
    }
    /^@@ / { hdr = 0; split($3, a, ","); line = substr(a[1], 2) + 0; next }
    hdr { next }
    /^\+/ {
      if (!skip) print (commit != "" ? commit ":" : "") file ":" line "\t" substr($0, 2)
      line++
    }
  '
}

git_diff_opts=(-U0 --no-color --no-ext-diff --no-textconv --no-renames)

case "$mode" in
  staged)
    git -c core.quotePath=false diff --cached "${git_diff_opts[@]}" --diff-filter=ACMR | extract >"$tmp/lines"
    check_names < <(git diff --cached --name-only -z --no-renames --diff-filter=AM)
    ;;
  all)
    empty_tree=$(git hash-object -t tree /dev/null)
    git -c core.quotePath=false diff --cached "${git_diff_opts[@]}" "$empty_tree" | extract >"$tmp/lines"
    check_names < <(git ls-files -z)
    ;;
  range)
    git -c core.quotePath=false log -p "${git_diff_opts[@]}" --format=commit:%H "${range_args[@]}" | extract >"$tmp/lines"
    check_names < <(git log --name-only -z --no-renames --diff-filter=AM --format= "${range_args[@]}")
    ;;
esac

# --- Match ------------------------------------------------------------------
grep -v -- "$ALLOW_MARKER" "$tmp/lines" >"$tmp/candidates" || true
: >"$tmp/findings"
grep -E -f "$tmp/strict" "$tmp/candidates" >>"$tmp/findings" || true
grep -iE -- "${TAB}.*(${generic_re})" "$tmp/candidates" |
  grep -viE -- "${TAB}.*(${placeholder_re})" >>"$tmp/findings" || true

findings=$(sort -u "$tmp/findings" | wc -l | tr -d ' ')

if [ "$findings" -eq 0 ] && [ "$bad_names" -eq 0 ]; then
  exit 0
fi

{
  if [ "$bad_names" -gt 0 ]; then
    printf 'secret-scan: %s file(s) that must not be committed:\n' "$bad_names"
    sort -u "$tmp/names"
  fi
  if [ "$findings" -gt 0 ]; then
    printf 'secret-scan: %s line(s) that look like secrets:\n' "$findings"
    sort -u "$tmp/findings" | cut -c1-160 | sed "s/${TAB}/  /; s/^/  /"
  fi
  printf '\nIf a secret was really exposed: remove it AND rotate it.\n'
  printf 'False positive? Append "%s" to the line or add the path to .secretscanignore.\n' "$ALLOW_MARKER"
} >&2
exit 1
