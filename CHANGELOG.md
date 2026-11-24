# Changelog

All notable changes to the starter are listed here, newest first. Versions follow
[Semantic Versioning](https://semver.org/). `.starter-version` in a project records the
release it was created from.

## [0.2.0]

- Claude Code: a `create-skill` skill (`/create-skill <description>`) that drafts a new skill.
- Claude Code: a `github-create-pr` skill that opens a pull request for the current branch,
  filling in the repository's PR template with security, config, migration, API and deploy
  call-outs. It updates an outdated description on request and never merges or force-pushes.
- Claude Code asks before `gh pr edit`, as it already does before `gh pr create`.
- `scripts/lint-agent-files.sh`, run by `scripts/check.sh`: skills and agents need valid
  frontmatter with a matching name and a description, and may not pre-approve `Bash` in
  `allowed-tools`, define hooks, set an agent's `permissionMode` or inject shell output
  into the prompt.
- The guard hooks now ask before edits to `.claude/skills/` and `.claude/agents/`.
- The shipped skills declare their licence, author and version in their frontmatter, and
  carry their licence terms in a `LICENSE.txt` of their own. These terms apply to the
  skills regardless of the project's `LICENSE`.
- `create-skill` writes skills that pass the lint and declare a licence and metadata.

## [0.1.0]

First release.

- Git hygiene: ignore rules for secrets and local files, LF line endings, editor defaults.
- Git hooks: block secrets, key and `.env` files, conflict markers and oversized files at
  commit; enforce Conventional Commits; at push, re-scan outgoing commits, refuse unsigned
  commits, check branch names and refuse force-push or deletion of protected branches.
- Project-wide hook settings in `.hooksconfig`, including an opt-in ticket rule for branch
  names and an opt-in block on direct pushes to protected branches.
- CI: repository checks, gitleaks over the full history, workflow audit, dependency review,
  one aggregate `ci-ok` status.
- `scripts/check.d/` extension point for a project's own build, lint and test steps.
- `scripts/init.sh` to fill the starter's placeholders and give the project its own README.
- `scripts/harden-github.sh` to apply rulesets and security settings on GitHub.
- Claude Code: shared permission rules, guard hooks and a `git-commit` skill.
