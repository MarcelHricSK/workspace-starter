#!/usr/bin/env bash
# Lints Claude Code skills and subagents. Their text becomes instructions the
# agent follows, so they are held to the same standard as the guardrails.
#
#   scripts/lint-agent-files.sh [dir...]   default: .claude/skills .claude/agents
#
# A directory named "agents" holds subagents (<name>.md); any other directory
# holds skills (<name>/SKILL.md). Missing directories are skipped. Rules:
#   - frontmatter between "---" lines with a name and a description
#   - the name is kebab-case and matches the skill directory or agent file
#   - allowed-tools does not pre-approve Bash
#   - no hooks (they run shell commands); agents set no permissionMode
#   - no dynamic shell injection (!`command` or a ```! block) in any file
#   - SKILL.md stays under 500 lines
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if [ "$#" -eq 0 ]; then
  set -- .claude/skills .claude/agents
fi

exec python3 - "$@" <<'PY'
import os
import re
import sys

NAME = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
KEY = re.compile(r"^([A-Za-z][\w-]*):\s*(.*)$")
INJECTION = re.compile(r"(?:^|[\s(])!`[^`\n]+`|^\s*```!", re.M)
MAX_LINES = 500

errors = []
checked = 0


def err(path, msg):
    errors.append(f"{path}: {msg}")


def frontmatter(path, text):
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        err(path, "no frontmatter (the file must start with ---)")
        return None
    try:
        end = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
    except StopIteration:
        err(path, "frontmatter is not closed with ---")
        return None
    fields, last = {}, None
    for line in lines[1:end]:
        m = KEY.match(line)
        if m:
            last = m.group(1)
            fields[last] = m.group(2).strip()
        elif last and line.strip():
            fields[last] = (fields[last] + " " + line.strip()).strip()
    return fields


def unquote(value):
    return value.strip().strip("'\"")


def check_text(path, text):
    if INJECTION.search(text):
        err(path, "dynamic shell injection (!`command` or a ```! block) is not allowed")


def check_file(path, expected_name, kind):
    global checked
    checked += 1
    try:
        text = open(path, encoding="utf-8").read()
    except (OSError, UnicodeDecodeError) as exc:
        err(path, f"cannot read: {exc}")
        return
    fields = frontmatter(path, text)
    if fields is not None:
        name = unquote(fields.get("name", ""))
        if not name:
            err(path, "frontmatter has no name")
        elif not NAME.match(name):
            err(path, f"name '{name}' is not kebab-case (a-z, 0-9, -; at most 64 characters)")
        elif name != expected_name:
            err(path, f"name '{name}' does not match '{expected_name}'")
        if not unquote(fields.get("description", "")):
            err(path, "frontmatter has no description")
        if re.search(r"\bBash\b", fields.get("allowed-tools", "")):
            err(path, "allowed-tools must not pre-approve Bash; let the permission rules decide")
        if "hooks" in fields:
            err(path, "hooks are not allowed in a skill or agent; configure hooks in .claude/settings.json")
        if kind == "agent" and "permissionMode" in fields:
            err(path, "an agent must not set permissionMode")
    if kind == "skill" and len(text.splitlines()) > MAX_LINES:
        err(path, f"longer than {MAX_LINES} lines; move detail into supporting files")
    check_text(path, text)


for root in sys.argv[1:]:
    if not os.path.isdir(root):
        continue
    if os.path.basename(os.path.normpath(root)) == "agents":
        for entry in sorted(os.listdir(root)):
            path = os.path.join(root, entry)
            if entry.endswith(".md") and os.path.isfile(path):
                check_file(path, entry[:-3], "agent")
        continue
    for entry in sorted(os.listdir(root)):
        skill_dir = os.path.join(root, entry)
        if not os.path.isdir(skill_dir):
            continue
        skill_md = os.path.join(skill_dir, "SKILL.md")
        if not os.path.isfile(skill_md):
            err(skill_dir, "skill has no SKILL.md")
            continue
        check_file(skill_md, entry, "skill")
        for dirpath, _, files in os.walk(skill_dir):
            for f in sorted(files):
                path = os.path.join(dirpath, f)
                if path == skill_md:
                    continue
                try:
                    check_text(path, open(path, encoding="utf-8").read())
                except UnicodeDecodeError:
                    pass  # binary supporting file

for e in errors:
    print(e, file=sys.stderr)
if errors:
    print(f"{len(errors)} problem(s) in skills and agents", file=sys.stderr)
    sys.exit(1)
print(f"{checked} skill(s) and agent(s) checked")
PY
