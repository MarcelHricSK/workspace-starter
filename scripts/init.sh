#!/usr/bin/env bash
# Makes a repository created from the starter your own.
#
#   scripts/init.sh [options]   fill the placeholders, give the project its own
#                               README, then run scripts/setup.sh
#   scripts/init.sh --check     exit 1 if a placeholder is still present
#
# Options (each defaults to what git knows about this clone):
#   --owner <handle>      GitHub user or org/team for CODEOWNERS   (owner of origin)
#   --repo <owner/name>   repository, for the advisory link       (origin)
#   --holder <name>       copyright holder in LICENSE             (git user.name)
#   --year <yyyy>         copyright year                          (this year)
#   --name <project>      project name for the new README         (repository name)
#   --render-only         only fill placeholders: keep README, skip setup
#
# Safe to run again: filled placeholders and an existing GUARDRAILS.md are left alone.
set -euo pipefail

# Replacement text is always literal, even if it contains "&".
shopt -u patsub_replacement 2>/dev/null || true

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

# The placeholders this script owns, as "file|token". --check looks at exactly
# these, so documentation that merely mentions a token never trips it.
PLACEHOLDERS=(
  ".github/CODEOWNERS|__STARTER_OWNER__"
  ".github/ISSUE_TEMPLATE/config.yml|__STARTER_REPO__"
  "LICENSE|__STARTER_HOLDER__"
  "LICENSE|__STARTER_YEAR__"
)

usage() {
  sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}
die() {
  printf 'init: %s\n' "$*" >&2
  exit 1
}

check_only=false
render_only=false
owner="" repo="" holder="" year="" name=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) check_only=true ;;
    --render-only) render_only=true ;;
    --owner | --repo | --holder | --year | --name)
      [ "$#" -ge 2 ] || usage
      case "$1" in
        --owner) owner=$2 ;;
        --repo) repo=$2 ;;
        --holder) holder=$2 ;;
        --year) year=$2 ;;
        --name) name=$2 ;;
      esac
      shift
      ;;
    *) usage ;;
  esac
  shift
done

if [ "$check_only" = true ]; then
  remaining=0
  for entry in "${PLACEHOLDERS[@]}"; do
    file=${entry%%|*}
    token=${entry##*|}
    if [ -f "$file" ] && grep -qF -- "$token" "$file"; then
      printf '  %s still contains %s\n' "$file" "$token" >&2
      remaining=1
    fi
  done
  if [ "$remaining" -ne 0 ]; then
    printf 'init: this repository still has starter placeholders. Run scripts/init.sh.\n' >&2
    exit 1
  fi
  exit 0
fi

# --- Work out the values ----------------------------------------------------
if [ -z "$repo" ]; then
  origin=$(git remote get-url origin 2>/dev/null || true)
  # git@host:owner/name.git, https://host/owner/name(.git), ssh://git@host/owner/name.git
  repo=$(printf '%s' "$origin" | sed -E 's#^(https?://[^/]+/|ssh://[^/]+/|[^:/]+@[^:]+:)##; s#\.git$##; s#/$##')
fi
[ -n "$owner" ] || owner=${repo%%/*}
[ -n "$name" ] || name=${repo##*/}
[ -n "$holder" ] || holder=$(git config --get user.name 2>/dev/null || true)
[ -n "$year" ] || year=$(date +%Y)

[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
  die "cannot tell the repository from 'origin'; pass --repo <owner/name>."
[[ "$owner" =~ ^[A-Za-z0-9][A-Za-z0-9-]*(/[A-Za-z0-9._-]+)?$ ]] ||
  die "'$owner' is not a GitHub user or org/team; pass --owner <handle>."
[[ "$year" =~ ^[0-9]{4}$ ]] || die "--year must be four digits."
[ -n "$holder" ] || die "no copyright holder; pass --holder <name> or set git user.name."
case "$holder$name" in
  *$'\n'*) die "values must be a single line." ;;
esac

# --- Fill the placeholders --------------------------------------------------
value_for() {
  case "$1" in
    __STARTER_OWNER__) printf '%s' "$owner" ;;
    __STARTER_REPO__) printf '%s' "$repo" ;;
    __STARTER_HOLDER__) printf '%s' "$holder" ;;
    __STARTER_YEAR__) printf '%s' "$year" ;;
  esac
}

# replace_in <file> <token> <value>: literal replacement that keeps the file's mode.
replace_in() {
  local file=$1 token=$2 value=$3 line tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/init.XXXXXX")
  while IFS= read -r line || [ -n "$line" ]; do
    printf '%s\n' "${line//"$token"/$value}"
  done <"$file" >"$tmp"
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

filled=0
for entry in "${PLACEHOLDERS[@]}"; do
  file=${entry%%|*}
  token=${entry##*|}
  if [ -f "$file" ] && grep -qF -- "$token" "$file"; then
    replace_in "$file" "$token" "$(value_for "$token")"
    filled=$((filled + 1))
  fi
done
printf 'init: filled %s placeholder(s) (owner %s, repository %s, holder %s, year %s).\n' \
  "$filled" "$owner" "$repo" "$holder" "$year"

[ "$render_only" = true ] && exit 0

# --- Give the project its own README ----------------------------------------
# The starter's README documents the guardrails. Keep it as GUARDRAILS.md and
# start a fresh README for the project itself.
if [ -f README.md ] && [ ! -e GUARDRAILS.md ]; then
  if git ls-files --error-unmatch README.md >/dev/null 2>&1; then
    git mv README.md GUARDRAILS.md
  else
    mv README.md GUARDRAILS.md
  fi
  cat >README.md <<EOF
# $name

<!-- Describe the project here. -->

This repository was created from the workspace-starter template. Its guardrails
(git hooks, CI, secret scanning, Claude Code settings) are described in
[GUARDRAILS.md](GUARDRAILS.md). To contribute, see [CONTRIBUTING.md](CONTRIBUTING.md).
EOF
  printf 'init: moved the starter README to GUARDRAILS.md and started README.md for %s.\n' "$name"
fi

# --- Enable the hooks -------------------------------------------------------
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  scripts/setup.sh
fi
