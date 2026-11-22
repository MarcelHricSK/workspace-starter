#!/usr/bin/env python3
"""PreToolUse guard for file tools (Read, Edit, Write, MultiEdit, NotebookEdit, Grep).

  deny  - secret files (any access) and .git internals (writes)
  ask   - edits to the guardrails themselves: git hooks, Claude Code settings
          and hooks, CI workflows, CODEOWNERS, the secret scanner
  (no output) - no opinion; the normal permission rules decide

Paths are checked both as given and with symlinks resolved, case-insensitively.
"""
import fnmatch
import json
import os
import sys

WRITE_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}

SECRET_BASENAMES = [
    ".env", ".env.*", "*.pem", "*.key", "*.p12", "*.pfx", "*.jks", "*.keystore", "*.kdbx",
    "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519", ".netrc", ".pgpass", ".htpasswd",
]
SECRET_BASENAME_EXCEPTIONS = [".env.example", ".env.sample", ".env.template"]

# Matched against the absolute path with a leading and trailing "/" on each part.
SECRET_PATH_PARTS = [
    "/.ssh/", "/.gnupg/", "/.aws/", "/.kube/config", "/.docker/config.json",
    "/.config/gh/", "/.data/",
]
SECRET_PATH_EXCEPTIONS = ["*.pub", "*/known_hosts"]

# Globs whose modification needs a human in the loop. Each is matched against
# the repository-relative path at the top level AND at any depth, so a copy of
# the guardrails kept in a subdirectory (a template source, a nested project)
# is protected the same way.
GUARDRAIL_GLOBS = [
    ".claude/settings.json", ".claude/settings.local.json", ".claude/hooks/*",
    ".githooks/*", ".github/workflows/*", ".github/codeowners", ".github/dependabot.yml",
    "scripts/scan-secrets.sh", "scripts/check.d/*", ".secretscanignore", ".hooksconfig",
]


def is_guardrail(rel):
    return any(fnmatch.fnmatch(rel, g) or fnmatch.fnmatch(rel, "*/" + g) for g in GUARDRAIL_GLOBS)


def candidates(raw, cwd):
    """The path as given (normalised) and with symlinks resolved, lower-cased."""
    expanded = os.path.expanduser(raw)
    if not os.path.isabs(expanded):
        expanded = os.path.join(cwd, expanded)
    seen = []
    for path in (os.path.normpath(expanded), os.path.realpath(expanded)):
        path = path.replace("\\", "/").lower()
        if path not in seen:
            seen.append(path)
    return seen


def is_secret(path):
    base = path.rsplit("/", 1)[-1]
    if any(fnmatch.fnmatch(base, p) for p in SECRET_BASENAMES) and base not in SECRET_BASENAME_EXCEPTIONS:
        return f"{base} is a secret or key file"
    probe = path if path.endswith("/") else path + "/"
    for part in SECRET_PATH_PARTS:
        needle = part if part.endswith("/") else part + "/"
        if needle in probe and not any(fnmatch.fnmatch(path, e) for e in SECRET_PATH_EXCEPTIONS):
            return f"{part.strip('/')} holds credentials"
    return None


def decide(tool, raw_path, cwd, project):
    project = os.path.realpath(project).replace("\\", "/").lower()
    for path in candidates(raw_path, cwd):
        reason = is_secret(path)
        if reason:
            return "deny", reason + "; secrets are off-limits to the agent"
        if tool not in WRITE_TOOLS:
            continue
        if "/.git/" in path + "/":
            return "deny", "direct edits inside .git are not allowed; use git commands"
        if path.startswith(project + "/"):
            rel = path[len(project) + 1:]
            if is_guardrail(rel):
                return "ask", f"{rel} is part of the repository's guardrails; a human must confirm changes to it"
    return None, None


def main():
    try:
        payload = json.load(sys.stdin)
        tool = payload.get("tool_name", "")
        tool_input = payload.get("tool_input", {}) or {}
        cwd = payload.get("cwd") or os.getcwd()
        project = os.environ.get("CLAUDE_PROJECT_DIR") or cwd
        raw = tool_input.get("file_path") or tool_input.get("notebook_path") or tool_input.get("path")
        decision, reason = (None, None)
        if isinstance(raw, str) and raw:
            decision, reason = decide(tool, raw, cwd, project)
    except Exception as exc:  # fail closed
        decision, reason = "ask", f"guard_files.py could not evaluate this call ({exc})"
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
