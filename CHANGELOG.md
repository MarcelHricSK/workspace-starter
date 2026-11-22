# Changelog

All notable changes to the starter are listed here, newest first. Versions follow
[Semantic Versioning](https://semver.org/). `.starter-version` in a project records the
release it was created from.

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
