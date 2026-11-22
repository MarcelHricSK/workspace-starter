#!/usr/bin/env bash
# One-time setup after cloning: activates the tracked git hooks and reports
# which optional tools are available. Safe to run repeatedly.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

chmod +x .githooks/* scripts/*.sh
if [ -d .claude/hooks ]; then
  chmod +x .claude/hooks/*.py
fi

git config core.hooksPath .githooks
printf 'Git hooks enabled (core.hooksPath=.githooks): %s\n' "$(find .githooks -type f ! -name '_*' -exec basename {} \; | sort | tr '\n' ' ')"

# Signed commits are required (pre-push hook and GitHub ruleset). Turn signing
# on for this clone when a key is available; never touch global config.
printf '\nCommit signing:\n'
signing_key=$(git config --get user.signingkey || true)
signing_on=$(git config --type=bool --get commit.gpgsign || true)
if [ -n "$signing_key" ] || [ "$signing_on" = true ]; then
  git config commit.gpgsign true
  git config tag.gpgsign true
  printf '  ok       commits and tags in this clone are signed (format: %s)\n' "$(git config --get gpg.format || echo openpgp)"
else
  cat <<'EOF'
  missing  no signing key configured; pushes will be rejected until you set one up.
           Simplest route, using an SSH key:
             git config --global gpg.format ssh
             git config --global user.signingkey ~/.ssh/id_ed25519.pub
             git config --global commit.gpgsign true
           Then add the same public key to GitHub as a *signing* key
           (Settings > SSH and GPG keys) and re-run scripts/setup.sh.
EOF
fi

printf '\nTools:\n'
report() {
  local tool=$1 purpose=$2
  if command -v "$tool" >/dev/null 2>&1; then
    printf '  ok       %-11s %s\n' "$tool" "$purpose"
  else
    printf '  missing  %-11s %s\n' "$tool" "$purpose"
  fi
}
report python3 "required by the Claude Code guard hooks (.claude/hooks)"
report gh "required by scripts/harden-github.sh"
report shellcheck "optional: shell linting in scripts/check.sh (required in CI)"
report actionlint "optional: workflow linting in scripts/check.sh (required in CI)"
report gitleaks "optional: deep secret scan in scripts/check.sh (CI runs it on every push)"

printf '\nNext: run scripts/check.sh to verify the workspace.\n'
