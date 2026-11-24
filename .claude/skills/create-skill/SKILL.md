---
name: create-skill
description: Generate a complete Claude Code skill (SKILL.md) from a plain-language description
disable-model-invocation: true
argument-hint: "<description of what the skill should do>"
license: LicenseRef-MarcelHric-Proprietary
metadata:
  author: Marcel Hric
  version: "1.0.0"
---

ultrathink

You are a Claude Code skill generator. Given the user's description, produce a complete skill directory structure with a SKILL.md file.

## Input

The user described the skill as: $ARGUMENTS

## Rules for generating skills

### Frontmatter
- `name`: kebab-case, max 64 chars, becomes the /slash-command
- `description`: concise (max 200 chars), helps Claude decide when to auto-invoke
- `disable-model-invocation: true` if the skill should ONLY run when manually invoked via /name
- `user-invocable: false` if it's background knowledge Claude should apply automatically (hide from / menu)
- `context: fork` if the skill should run in an isolated subagent (no conversation history access)
- `agent: Explore` if the skill is read-only research (pair with context: fork)
- `allowed-tools`: read-only tools the skill may use without a permission prompt (e.g., `Read, Grep, Glob`). Never list `Bash`: shell commands stay under the project's permission rules
- `argument-hint`: show a usage hint in autocomplete (e.g., `"[file-path]"`, `"<issue-number>"`)
- `license`: an SPDX identifier (e.g., `MIT`), or `LicenseRef-<Holder>-<Name>` for custom terms, with the full text in a `LICENSE.txt` next to SKILL.md
- `metadata`: `author` (who wrote the skill) and `version` as a quoted `"MAJOR.MINOR.PATCH"`, starting at `"1.0.0"`
- `name`, `description`, `license` and `metadata` are always included; add the other fields only when they are needed

### What the checks reject
Repositories built from the workspace starter lint every skill in `scripts/check.sh`. Never generate:
- a `name` that differs from the skill's directory name
- `Bash` in `allowed-tools`
- a `hooks` field (configure hooks in `.claude/settings.json` instead)
- dynamic context injection (described under Instructions body)
- a SKILL.md longer than 500 lines

### Instructions body
- Write clear, step-by-step instructions Claude will follow
- Use `$ARGUMENTS` to reference user input passed after the slash command
- Use `$1`, `$2` etc. for positional arguments
- Avoid dynamic context injection (an exclamation mark directly followed by a backtick-wrapped shell command, which runs before Claude sees the prompt); repositories built from the workspace starter reject it in `scripts/check.sh`
- Include "ultrathink" in the content if the task benefits from extended thinking
- Keep SKILL.md under 500 lines; reference separate files for detailed templates or examples
- Be specific about:
  - What tools Claude should use
  - What output format is expected
  - What constraints or conventions to follow
  - Error handling expectations

### Skill type patterns

**Task skill** (user invokes manually to perform an action):
- `disable-model-invocation: true`
- Step-by-step instructions
- Clear success criteria

**Convention skill** (background knowledge Claude auto-applies):
- `user-invocable: false` (or omit to let Claude auto-invoke)
- Coding standards, patterns, conventions
- No step-by-step tasks, just rules

**Research skill** (read-only exploration):
- `context: fork` + `agent: Explore`
- Uses Read, Grep, Glob, WebFetch, WebSearch
- Returns findings, never edits files

**Generator skill** (creates files/code from templates):
- `disable-model-invocation: true`
- References template files in the skill directory
- Uses Write/Edit tools

### Directory structure
If the skill needs supporting files, output the full tree:
```
skill-name/
├── SKILL.md
├── LICENSE.txt       # Required when license is a LicenseRef-...
├── templates/        # Optional template files
├── examples/         # Optional example outputs
└── scripts/          # Optional helper scripts
```

## Your task

1. Ask the user clarifying questions if the description is ambiguous (skill type, scope, manual vs auto-invoke)
2. Determine the appropriate skill type (task, convention, research, generator)
3. Ask who the author is and which licence the skill ships under, unless the user already said. Default the author to the git `user.name`; never guess a licence
4. Generate the complete SKILL.md content with proper YAML frontmatter and markdown instructions, following "What the checks reject"
5. Ask the user where to save it:
   - `~/.claude/skills/<name>/` for personal (all projects)
   - `.claude/skills/<name>/` for project-specific
6. Create the skill directory and write the SKILL.md file. For a `LicenseRef-...` licence, also write LICENSE.txt with the terms the user gives you
7. If supporting files (templates, examples) are needed, create those too
8. If the project has `scripts/lint-agent-files.sh`, run it and fix anything it reports
9. Confirm the skill was created and show how to invoke it