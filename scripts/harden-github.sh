#!/usr/bin/env bash
# Applies the GitHub-side protections that cannot live in the repository:
# rulesets plus security and Actions settings.
#
#   scripts/harden-github.sh            show what would change (dry run)
#   scripts/harden-github.sh --apply    apply it
#
# Run it once per repository, after the first push (the default branch and
# the CI workflow must exist). Requires the GitHub CLI, authenticated as a
# repository admin. Re-running updates the existing rulesets in place.
#
# Options (environment variables):
#   REPO=owner/name            target repository (default: the current one)
#   REQUIRED_APPROVALS=0       approving reviews needed on a pull request
#   REQUIRE_CODE_OWNERS=false  require review from CODEOWNERS
#   REQUIRE_SIGNED=true        require verified signatures on every branch
#   REQUIRED_CHECK=ci-ok       status check that must pass ("" for none)
#   ALLOW_ADMIN_BYPASS=false   let repository admins bypass the rulesets
set -euo pipefail

apply=false
case "${1:-}" in
  --apply) apply=true ;;
  "" | --dry-run) ;;
  *)
    sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
    ;;
esac

command -v gh >/dev/null 2>&1 || {
  echo "harden-github: the GitHub CLI (gh) is required." >&2
  exit 1
}

REPO=${REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}
REQUIRED_APPROVALS=${REQUIRED_APPROVALS:-0}
REQUIRE_CODE_OWNERS=${REQUIRE_CODE_OWNERS:-false}
REQUIRE_SIGNED=${REQUIRE_SIGNED:-true}
REQUIRED_CHECK=${REQUIRED_CHECK-ci-ok}
ALLOW_ADMIN_BYPASS=${ALLOW_ADMIN_BYPASS:-false}
BRANCH_RULESET="protect-default-branch"
SIGN_RULESET="require-signed-commits"

is_bool() { [ "$1" = true ] || [ "$1" = false ]; }
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "invalid REPO: $REPO" >&2; exit 2; }
[[ "$REQUIRED_APPROVALS" =~ ^[0-9]$ ]] || { echo "REQUIRED_APPROVALS must be 0-9" >&2; exit 2; }
[[ "$REQUIRED_CHECK" =~ ^[A-Za-z0-9_./\ -]*$ ]] || { echo "invalid REQUIRED_CHECK" >&2; exit 2; }
for v in "$REQUIRE_CODE_OWNERS" "$REQUIRE_SIGNED" "$ALLOW_ADMIN_BYPASS"; do
  is_bool "$v" || { echo "boolean options must be true or false" >&2; exit 2; }
done

# Private repositories only get rulesets and secret scanning on a paid plan.
# Find that out once, up front, instead of failing step by step.
is_private=$(gh api "repos/$REPO" --jq .private)
rulesets_available=true
if [ "$is_private" = true ] && ! gh api "repos/$REPO/rulesets" >/dev/null 2>&1; then
  rulesets_available=false
fi

bypass='[]'
if [ "$ALLOW_ADMIN_BYPASS" = true ]; then
  # actor_id 5 is the built-in "Repository admin" role.
  bypass='[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"always"}]'
fi

# --- Ruleset 1: the default branch ------------------------------------------
rules='{"type":"deletion"},{"type":"non_fast_forward"},{"type":"required_linear_history"}'
rules="$rules,{\"type\":\"pull_request\",\"parameters\":{\"required_approving_review_count\":$REQUIRED_APPROVALS,\"dismiss_stale_reviews_on_push\":true,\"require_code_owner_review\":$REQUIRE_CODE_OWNERS,\"require_last_push_approval\":false,\"required_review_thread_resolution\":true}}"
if [ -n "$REQUIRED_CHECK" ]; then
  rules="$rules,{\"type\":\"required_status_checks\",\"parameters\":{\"strict_required_status_checks_policy\":true,\"required_status_checks\":[{\"context\":\"$REQUIRED_CHECK\"}]}}"
fi
branch_ruleset=$(
  cat <<JSON
{
  "name": "$BRANCH_RULESET",
  "target": "branch",
  "enforcement": "active",
  "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
  "bypass_actors": $bypass,
  "rules": [$rules]
}
JSON
)

# --- Ruleset 2: signed commits on every branch ------------------------------
# Applied to all branches, not just the default one: with squash merges the
# commit that lands on the default branch is created and signed by GitHub, so
# a default-branch-only rule would never check what contributors push.
sign_ruleset=$(
  cat <<JSON
{
  "name": "$SIGN_RULESET",
  "target": "branch",
  "enforcement": "active",
  "conditions": {"ref_name": {"include": ["~ALL"], "exclude": []}},
  "bypass_actors": $bypass,
  "rules": [{"type": "required_signatures"}]
}
JSON
)

# GitHub cannot sign the commits it rewrites for "rebase and merge", so that
# method is switched off while signatures are required.
if [ "$REQUIRE_SIGNED" = true ]; then
  merge_settings='{"allow_merge_commit":false,"allow_squash_merge":true,"allow_rebase_merge":false,"delete_branch_on_merge":true}'
  merge_summary="squash merges only"
  sign_summary="every push to every branch must carry a verified signature"
else
  merge_settings='{"allow_merge_commit":false,"allow_squash_merge":true,"allow_rebase_merge":true,"delete_branch_on_merge":true}'
  merge_summary="squash and rebase merges only"
  sign_summary="not required (the ruleset is removed if it exists)"
fi

cat <<PLAN
Repository: $REPO

Ruleset "$BRANCH_RULESET" on the default branch:
  - no deletion, no force-push, linear history
  - changes only through pull requests ($REQUIRED_APPROVALS approval(s), code owners: $REQUIRE_CODE_OWNERS,
    stale approvals dismissed, conversations must be resolved)
  - required status check: ${REQUIRED_CHECK:-none} (branch must be up to date)

Ruleset "$SIGN_RULESET" on all branches:
  - $sign_summary

Admins may bypass the rulesets: $ALLOW_ADMIN_BYPASS

Repository settings:
  - $merge_summary, head branches deleted on merge
  - Actions: default GITHUB_TOKEN read-only, cannot approve pull requests,
    actions must be pinned to a full commit SHA
  - Dependabot alerts and security updates on
  - secret scanning and push protection on
  - private vulnerability reporting on
PLAN

if [ "$rulesets_available" != true ]; then
  cat <<'NOTE'

NOTE: this repository is private and its plan does not include rulesets or
secret scanning, so both rulesets and the secret scanning settings are SKIPPED.
Nothing on GitHub will then stop a direct or unsigned push. Protection rests on
the git hooks and CI: consider `blockProtectedPush = true` in .hooksconfig.
NOTE
fi
if [ "$is_private" = true ]; then
  printf '\nNOTE: private vulnerability reporting is for public repositories and is skipped.\n'
fi

if [ "$apply" != true ]; then
  printf '\nDry run. Re-run with --apply to make these changes.\n'
  exit 0
fi

failures=0
errfile=$(mktemp "${TMPDIR:-/tmp}/harden-github.XXXXXX")
trap 'rm -f "$errfile"' EXIT
try() { # try <description> <gh api args...>   (JSON body on stdin when given)
  local desc=$1
  shift
  if gh api -H "X-GitHub-Api-Version: 2022-11-28" "$@" >/dev/null 2>"$errfile"; then
    printf '  ok      %s\n' "$desc"
  else
    printf '  FAILED  %s\n          %s\n' "$desc" "$(tr '\n' ' ' <"$errfile" | cut -c1-200)"
    failures=$((failures + 1))
  fi
}
ruleset_id() { gh api "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$1\") | .id" | head -n 1; }
upsert_ruleset() { # upsert_ruleset <name> <json>
  local id
  id=$(ruleset_id "$1")
  if [ -n "$id" ]; then
    try "update ruleset $1" -X PUT "repos/$REPO/rulesets/$id" --input - <<<"$2"
  else
    try "create ruleset $1" -X POST "repos/$REPO/rulesets" --input - <<<"$2"
  fi
}

skipped() { printf '  skipped %s\n' "$1"; }

printf '\nApplying:\n'
if [ "$rulesets_available" != true ]; then
  skipped "rulesets (not available for this private repository)"
elif [ "$REQUIRE_SIGNED" = true ]; then
  upsert_ruleset "$BRANCH_RULESET" "$branch_ruleset"
  upsert_ruleset "$SIGN_RULESET" "$sign_ruleset"
else
  upsert_ruleset "$BRANCH_RULESET" "$branch_ruleset"
  sign_id=$(ruleset_id "$SIGN_RULESET")
  if [ -n "$sign_id" ]; then
    try "remove ruleset $SIGN_RULESET" -X DELETE "repos/$REPO/rulesets/$sign_id"
  fi
fi

try "merge settings" -X PATCH "repos/$REPO" --input - <<<"$merge_settings"
try "Actions token read-only" -X PUT "repos/$REPO/actions/permissions/workflow" --input - <<<'{"default_workflow_permissions":"read","can_approve_pull_request_reviews":false}'
try "Actions SHA pinning" -X PUT "repos/$REPO/actions/permissions" --input - <<<'{"enabled":true,"allowed_actions":"all","sha_pinning_required":true}'
try "Dependabot alerts" -X PUT "repos/$REPO/vulnerability-alerts"
try "Dependabot security updates" -X PUT "repos/$REPO/automated-security-fixes"
if [ "$rulesets_available" = true ]; then
  try "secret scanning + push protection" -X PATCH "repos/$REPO" --input - <<<'{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}'
else
  skipped "secret scanning + push protection (not available for this private repository)"
fi
if [ "$is_private" = true ]; then
  skipped "private vulnerability reporting (public repositories only)"
else
  try "private vulnerability reporting" -X PUT "repos/$REPO/private-vulnerability-reporting"
fi

if [ "$failures" -gt 0 ]; then
  printf '\n%s step(s) failed. They need admin access to the repository; on a private\n' "$failures"
  printf 'repository some also need a paid plan.\n'
  exit 1
fi
printf '\nDone. Review: https://github.com/%s/settings/rules\n' "$REPO"
