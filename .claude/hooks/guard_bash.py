#!/usr/bin/env python3
"""PreToolUse guard for the Bash tool.

Reads the tool call as JSON on stdin and answers with a permission decision:
  deny  - never run this, in any permission mode
  ask   - a human must confirm, even when the command is otherwise auto-allowed
  (no output) - no opinion; the normal permission rules decide

This is a tripwire for obvious mistakes and prompt-injected commands, not a
sandbox: a determined command can be obfuscated past any pattern list. Keep
real secrets out of reach (see README, "Going further") rather than relying on
this alone.
"""
import json
import re
import sys

SEG = r"[^;&|\n]*"  # stay inside one simple command

# Paths holding credentials. Referencing them from the shell is always denied.
SECRET_PATHS = [
    (r"(?:^|[\s/'\"=<>(:])\.env(?!\.(?:example|sample|template)\b)(?:\.[\w.-]+)?(?=$|[\s'\";|&)<>])",
     "references a .env file"),
    (r"(?:~|\$HOME|\$\{HOME\}|/Users/[^/\s]+|/home/[^/\s]+|/root)/\.ssh/(?![\w.-]*\.pub\b|known_hosts\b)",
     "references SSH keys or config"),
    (r"\bid_(?:rsa|dsa|ecdsa|ed25519)\b(?!\.pub)", "references an SSH private key"),
    (r"\.aws/(?:credentials|config|sso/|cli/cache)", "references AWS credentials"),
    (r"\.gnupg\b", "references the GnuPG keyring"),
    (r"\.kube/config\b", "references kubeconfig credentials"),
    (r"\.docker/config\.json\b", "references Docker registry credentials"),
    (r"\.config/gh/hosts\.yml\b", "references the GitHub CLI token store"),
    (r"(?:^|[\s/'\"=])\.(?:netrc|pgpass|htpasswd)\b", "references a credential file"),
    (r"(?:~|\$HOME|\$\{HOME\})/\.npmrc\b", "references the user npm token store"),
    (r"[\w./-]\.(?:pem|p12|pfx|jks|keystore|kdbx)\b", "references a key or keystore file"),
    (r"\bsecurity\s+(?:find|dump)-", "reads the macOS keychain"),
]

DENY = [
    # Catastrophic deletes: recursive rm aimed at /, ~, $HOME, ., .. or *.
    (r"\brm\b(?=" + SEG + r"\s-(?:[a-zA-Z]*[rR][a-zA-Z]*|-recursive)\b)" + SEG
     + r"\s(?:--\s+)?[\"']?(?:/|/\*|~/?|\$HOME/?|\$\{HOME\}/?|\.{1,2}/?|\*)[\"']?(?=\s|$|[;&|])",
     "recursive delete of a root, home or working directory"),
    (r"\b(?:mkfs(?:\.\w+)?|diskutil\s+erase\w*)\b", "formats a disk"),
    (r"\bdd\b" + SEG + r"\bof=/dev/", "writes directly to a device"),
    # History rewriting on the remote.
    (r"\bgit\b" + SEG + r"\bpush\b" + SEG + r"\s(?:--force(?![-\w])|-[a-zA-Z]*f[a-zA-Z]*\b)",
     "force-push (use --force-with-lease on a feature branch, with confirmation)"),
    (r"\bgit\b" + SEG + r"\bpush\b" + SEG + r"\s\+[\w./-]", "force-push via +refspec"),
    # Bypassing the repository's own guardrails.
    (r"\bgit\b" + SEG + r"\s--no-verify\b", "skips git hooks (--no-verify)"),
    (r"\bgit\b" + SEG + r"\bcommit\b" + SEG + r"\s-[a-zA-Z]*n[a-zA-Z]*(?=\s|$)", "skips git hooks (commit -n)"),
    (r"(?i)\bcore\.hookspath\b", "changes or overrides the git hooks path"),
    (r"\bgit\b" + SEG + r"\s--no-gpg-sign\b", "creates an unsigned commit or tag"),
    (r"(?i)\b(?:commit\.gpgsign|tag\.gpgsign|hooks\.requiresigned)(?:\s*=\s*|\s+)[\"']?(?:false|0|no|off)\b",
     "turns off commit signing"),
    (r"(?i)--unset(?:-all)?\s+(?:commit\.gpgsign|tag\.gpgsign|hooks\.requiresigned)\b", "turns off commit signing"),
    # Hook protections, whether set per clone or in the tracked .hooksconfig.
    (r"(?i)\bhooks\.(?:enforcebranchnames|requireticket|blockprotectedpush)(?:\s*=\s*|\s+)[\"']?(?:false|0|no|off)\b",
     "turns off a branch or push protection"),
    (r"(?i)--unset(?:-all)?\s+hooks\.(?:enforcebranchnames|requireticket|blockprotectedpush)\b",
     "turns off a branch or push protection"),
    (r"(?i)\bhooks\.ticketlesstypes\b", "changes which branch types may omit the ticket"),
    (r"\bgit\b" + SEG + r"\bconfig\b" + SEG + r"\b(?:--global|--system)\b" + SEG
     + r"\b(?:credential|url\.|user\.signingkey|gpg\.)", "changes global git credential or signing config"),
    # Remote code execution patterns.
    (r"\b(?:curl|wget|fetch)\b" + r"[^;&\n]*\|\s*(?:sudo\s+)?(?:ba|z|da|k|fi)?sh\b", "pipes a download into a shell"),
    (r"\b(?:ba|z)?sh\b\s+(?:-c\s+)?[\"']?(?:<\(|\$\()\s*(?:curl|wget)\b", "executes a downloaded script"),
    # Credential exfiltration helpers.
    (r"\bgh\b" + SEG + r"\bauth\b" + SEG + r"\b(?:token|status\b" + SEG + r"(?:--show-token|-t\b))", "prints the GitHub token"),
    (r"\bgh\b" + SEG + r"\brepo\b" + SEG + r"\bdelete\b", "deletes a GitHub repository"),
    (r"\bgh\b" + SEG + r"\bpr\b" + SEG + r"\bmerge\b", "merges a pull request (humans merge)"),
]

ASK = [
    (r"\brm\b" + SEG + r"\s-(?:[a-zA-Z]*[rR][a-zA-Z]*|-recursive)\b", "recursive delete"),
    (r"\bsudo\b", "runs with elevated privileges"),
    (r"\bchmod\b" + SEG + r"\b0?777\b", "makes files world-writable"),
    (r"\bfind\b" + SEG + r"\s-(?:delete|exec|execdir|ok|okdir|fprint|fprintf|fls)\b",
     "find that deletes, executes or writes"),
    (r"\bgit\b" + SEG + r"\bpush\b" + SEG + r"\s--force-with-lease\b", "rewrites remote history"),
    # Tags often trigger releases, so creating or pushing one needs a human.
    (r"\bgit\b" + SEG + r"\btag\b(?!\s*(?:$|[;&|])|\s+(?:-l|--list|-n\d*|-v|--verify|--contains|--points-at|--merged|--no-merged|--sort)\b)",
     "creates, moves or deletes a tag, which can trigger a release"),
    (r"\bgit\b" + SEG + r"\bpush\b" + SEG + r"(?:\s--tags\b|\s--follow-tags\b|\srefs/tags/|\stag\s|[\s/]v\d+\.\d+\.\d+\b)",
     "pushes a tag, which can trigger a release"),
    (r"\bgit\b" + SEG + r"\breset\b" + SEG + r"\s--hard\b", "discards uncommitted work"),
    (r"\bgit\b" + SEG + r"\bclean\b" + SEG + r"\s-[a-zA-Z]*f", "deletes untracked files"),
    (r"\bgit\b" + SEG + r"\b(?:checkout|restore)\b" + SEG + r"\s(?:--\s+)?\.(?=\s|$)", "discards uncommitted work"),
    (r"\bgit\b" + SEG + r"\bbranch\b" + SEG + r"\s(?:-D\b|--delete\s+--force\b)", "force-deletes a branch"),
    (r"\bgit\b" + SEG + r"\bstash\b" + SEG + r"\b(?:drop|clear)\b", "deletes stashed work"),
    (r"\bgit\b" + SEG + r"\b(?:filter-branch|filter-repo|update-ref|reflog\s+expire)\b", "rewrites or prunes history"),
    (r"\bgh\b" + SEG + r"\b(?:secret|variable)\b" + SEG + r"\b(?:set|delete|remove)\b", "changes repository secrets or variables"),
    (r"\bgh\b" + SEG + r"\bapi\b" + SEG + r"\s(?:-X|--method)[\s=]*(?:DELETE|PUT|PATCH|POST)\b", "mutating GitHub API call"),
    (r"(?:^|[;&|]\s*)(?:printenv|env)\s*(?:$|[|>;&])", "dumps the environment, which may hold secrets"),
    (r"\b(?:export|declare)\s+-p\b", "dumps the environment, which may hold secrets"),
]

# Writing to the guardrails themselves through the shell needs confirmation.
GUARDRAIL_PATHS = r"(?:\.claude/(?:settings[\w.]*\.json|hooks\b)|\.githooks\b|\.git/(?:hooks|config)\b|\.github/workflows\b|scripts/scan-secrets\.sh|scripts/check\.d\b|\.hooksconfig\b)"
WRITE_OPS = r"(?:>|\btee\b|\bsed\b[^;&|\n]*\s-[a-zA-Z]*i|\bperl\b[^;&|\n]*\s-[a-zA-Z]*i|\b(?:rm|mv|cp|chmod|chown|ln|truncate|install|dd|patch|touch)\b)"


def decide(command):
    for pattern, reason in SECRET_PATHS:
        if re.search(pattern, command):
            return "deny", reason + "; secrets are off-limits to the agent"
    for pattern, reason in DENY:
        if re.search(pattern, command):
            return "deny", reason
    if re.search(GUARDRAIL_PATHS, command) and re.search(WRITE_OPS, command):
        return "ask", "modifies the repository's guardrails (hooks, Claude settings or workflows)"
    for pattern, reason in ASK:
        if re.search(pattern, command):
            return "ask", reason
    return None, None


def main():
    try:
        payload = json.load(sys.stdin)
        command = payload.get("tool_input", {}).get("command", "")
        if not isinstance(command, str):
            raise ValueError("command is not a string")
        decision, reason = decide(command)
    except Exception as exc:  # fail closed: a broken guard must not wave things through
        decision, reason = "ask", f"guard_bash.py could not evaluate this command ({exc})"
    if decision:
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": decision,
                "permissionDecisionReason": f"Workspace guard: {reason}.",
            }
        }))


if __name__ == "__main__":
    main()
