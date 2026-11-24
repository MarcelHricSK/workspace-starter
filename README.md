# workspace-starter

A stack-agnostic repository template with security guardrails already wired in.
It contains no application code: start a project from it, then add your stack on top.

## What you get

| Layer              | What it does                                                                                                                                                                                                                                                                       | Where                                           |
|--------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------|
| Git hygiene        | Ignore rules for secrets and local files, LF line endings, editor defaults                                                                                                                                                                                                         | `.gitignore`, `.gitattributes`, `.editorconfig` |
| Local git hooks    | Block secrets, key files, `.env` files, conflict markers and oversized files at commit; enforce Conventional Commits; at push, re-scan outgoing commits, refuse unsigned commits, enforce `<type>/<description>` branch names (ticket key optional or required per project) and refuse force-push or deletion of `main` | `.githooks/`, `scripts/scan-secrets.sh`         |
| CI                 | Same checks as local, plus gitleaks over the full history, a workflow security audit (zizmor), actionlint, shellcheck and dependency review on pull requests                                                                                                                       | `.github/workflows/ci.yml`                      |
| Dependency updates | Weekly grouped Dependabot updates with a 7-day cooldown                                                                                                                                                                                                                            | `.github/dependabot.yml`                        |
| GitHub protections | Ruleset for the default branch plus security and Actions settings, applied by one script                                                                                                                                                                                           | `scripts/harden-github.sh`                      |
| Governance         | CODEOWNERS, pull request and issue templates, security policy, contributing guide                                                                                                                                                                                                  | `.github/`, `SECURITY.md`, `CONTRIBUTING.md`    |
| Claude Code        | Permission rules plus guard hooks that keep the agent away from secrets, destructive commands and the guardrails themselves                                                                                                                                                        | `.claude/`, `CLAUDE.md`                         |

Local tooling needs only `git` and `bash`. The Claude Code hooks need `python3`.
The hooks have no third-party dependencies.

## Start a project from this template

1. Create the repository from the template (GitHub: **Use this template**, or
   `gh repo create my-project --template MarcelHricSK/workspace-starter --private --clone`).
2. Make it yours, then verify the workspace:

   ```bash
   scripts/init.sh
   ```

   ```bash
   scripts/check.sh
   ```

   `init.sh` fills the starter's placeholders (code owner, security advisory link,
   copyright holder and year) from the repository's remote and your git identity, moves
   this file to `GUARDRAILS.md`, starts a fresh `README.md` for the project and enables
   the git hooks. Every value can be overridden: `scripts/init.sh --owner my-org/my-team`.
   Until it has run, `scripts/check.sh` fails locally and in CI.

3. Review `LICENSE`. The starter ships an all-rights-reserved notice in the holder's
   name; swap in the licence the project needs.
4. Push the first commit, then apply the GitHub protections (dry run first):

   ```bash
   scripts/harden-github.sh
   ```

   ```bash
   scripts/harden-github.sh --apply
   ```

5. Add your stack: extend `.gitignore`, add ecosystem blocks to
   `.github/dependabot.yml`, and put build, lint and test steps in `scripts/check.d/`
   (see [Project checks](#project-checks)).

Every later clone has to run `scripts/setup.sh` once: git does not enable tracked
hooks on its own.

The file `.starter-version` records which release of the starter the project began
from; [CHANGELOG.md](CHANGELOG.md) lists what changed in each release.

## How the layers back each other up

No single layer is trusted on its own.

- **Local hooks** give fast feedback but can be skipped with `--no-verify`.
- **`pre-push`** re-scans every outgoing commit, so a skipped pre-commit hook is still caught,
  and refuses unsigned commits.
- **CI** repeats the checks on a machine the author does not control and scans the full history with gitleaks.
- **The rulesets** make CI and signatures mandatory: nothing reaches `main` without a pull
  request and a green `ci-ok`, and no branch accepts a commit without a verified signature.
- **GitHub push protection** (enabled by `harden-github.sh`) rejects known token formats server-side.

## Secret scanning

`scripts/scan-secrets.sh` looks for well-known token formats (AWS, GitHub, GitLab,
Slack, Google, Stripe, Anthropic, OpenAI, npm, JWTs, private key blocks),
hard-coded credentials assigned to secret-looking names, and URLs with inline
passwords. It also rejects files that should never be committed (`.env*`, `*.pem`,
`*.key`, keystores, SSH private keys).

For a false positive, append `gitleaks:allow` to the line, or add a path regex
to `.secretscanignore`. Use `.env.example` (committed, placeholders only) to
document required variables and keep real values in an untracked `.env`.

If a real secret was committed, removing it is not enough: **rotate it**.

## Signed commits

Every commit must be signed. Three layers enforce it:

- `scripts/setup.sh` turns on `commit.gpgsign` and `tag.gpgsign` for the clone when a
  signing key is configured, and prints setup steps when it is not.
- The `pre-push` hook refuses to push commits that carry no signature.
- `scripts/harden-github.sh` adds a ruleset that requires a **verified** signature on
  every push to every branch. It covers all branches because squash merges are signed by
  GitHub itself, so a rule on `main` alone would never check what contributors push.

Because GitHub cannot sign rebased commits, the hardening script also limits merging to
squash. GPG and SSH signing both work; the key must be registered with GitHub as a
signing key for the signature to count as verified.

To run a project without the requirement, apply the protections with
`REQUIRE_SIGNED=false scripts/harden-github.sh --apply` and set
`git config hooks.requireSigned false`.

## Branch names

Branches are named `<type>/<short-description>`, for example `feat/add-user-subjects`.
The type is one of the commit types and the description is lowercase kebab-case.

A ticket key may always be put after the slash: `feat/TIC-123-add-user-subjects`. To make
it mandatory for a project, set `requireTicket = true` in `.hooksconfig`; then only the
types in `ticketlessTypes` (default `chore`) may omit it.

The `pre-push` hook rejects any other name. Protected branches and bot branches
(`dependabot/…`, `renovate/…`) are exempt. This check is local only: GitHub can enforce
branch-name patterns in rulesets, but only on Enterprise plans.

## Git hook settings

Each setting is looked up in three places, first match wins:

1. per-clone git config, for yourself only: `git config hooks.requireTicket true`
2. the tracked `.hooksconfig`, for everyone who clones the repository
3. the built-in default

`.hooksconfig` uses git-config syntax and lists every setting with its default. A value
that cannot be read (a typo in a boolean, a broken file) makes the hook fail rather than
fall back, so a mistake cannot silently switch a check off.

| Setting                    | Default       | Meaning                                                           |
|----------------------------|---------------|-------------------------------------------------------------------|
| `hooks.maxFileSizeKB`      | `1024`        | largest file `pre-commit` accepts                                 |
| `hooks.protectedBranches`  | `main master` | branches that cannot be force-pushed or deleted                   |
| `hooks.blockProtectedPush` | `false`       | `pre-push` refuses any direct push to an existing protected branch |
| `hooks.requireSigned`      | `true`        | `pre-push` refuses unsigned commits                               |
| `hooks.enforceBranchNames` | `true`        | `pre-push` checks the branch name                                 |
| `hooks.requireTicket`      | `false`       | branch names must carry a ticket key                              |
| `hooks.ticketlessTypes`    | `chore`       | types that may omit the ticket when `requireTicket` is on         |

`blockProtectedPush` is for repositories where the hosting platform cannot require pull
requests (for example a private repository on a plan without rulesets). The first push
that creates the branch is still allowed.

## Project checks

`scripts/check.sh` runs every tracked, executable file in `scripts/check.d/`, in name
order, after its own checks. Put your stack's build, lint and test steps there
(`scripts/check.d/10-lint.sh`, `20-test.sh`, …) and they run locally and in CI without
touching the workflow.

## Claude Code

`.claude/settings.json` is shared by everyone who opens the repository with Claude Code.

- **Permission rules** allow routine read-only commands, ask before commit, push,
  creating a pull request and editing one's title or description, and deny reading
  secret files and merging pull requests.
  `find` is deliberately not auto-allowed: it can delete files and run other programs.
- **`guard_bash.py`** denies commands that touch credential files, force-push, skip git
  hooks, pipe downloads into a shell or delete from the root, home or working directory.
  It also denies turning off commit signing. It asks for confirmation on recursive
  deletes, `sudo`, history rewrites and anything that modifies the guardrails.
- **`guard_files.py`** denies any access to secret files and writes inside `.git`, and
  asks before edits to hooks, Claude settings, skills, agents, workflows, CODEOWNERS or
  the scanner.
- **Skills** in `.claude/skills/`: `git-commit` (the conventions the git hooks enforce),
  `github-create-pr` (opens a pull request that follows `.github/pull_request_template.md`
  and never merges) and `create-skill` (`/create-skill <description>` drafts a new skill).
- **`scripts/lint-agent-files.sh`**, run by `scripts/check.sh`, holds skills and agents
  to the guardrails' standard: valid frontmatter whose name matches the directory or
  file, a description, no `Bash` in `allowed-tools`, no hooks, no `permissionMode` on an
  agent, and no shell output injected into the prompt.

The hooks are configured to fail closed: if `python3` is missing, the guarded tools
are blocked rather than allowed. Hooks run in every permission mode.

They are a tripwire, not a sandbox. Pattern matching cannot stop a deliberately
obfuscated command, so do not treat them as the only protection for anything valuable.
The user settings below supply the real boundary.

Personal overrides go in `.claude/settings.local.json` (untracked).

### Recommended user settings

Set these two once in your own `~/.claude/settings.json`. They are part of the intended
setup, not optional extras: the repository settings only cover repositories built from
this template, while user settings protect every project you open.

```json
{
  "permissions": {
    "disableBypassPermissionsMode": "disable"
  },
  "sandbox": {
    "enabled": true
  }
}
```

Merge the keys into the file if it already exists; do not replace it.

- **Sandbox on.** Shell commands run inside an operating-system sandbox that limits which
  files they can read or write and which hosts they can reach. The guard hooks only
  recognise known-bad command text; the sandbox holds even when a command is obfuscated.
- **Bypass mode off.** Removes the permission mode that skips every prompt, so the
  "ask before commit, push and guardrail edits" rules cannot be waved through wholesale.

The sandbox also enforces this repository's `Read` deny rules, which cover `~/.gnupg` and
`~/.ssh`. If a signed `git commit` or an SSH `git push` fails inside the sandbox because
it cannot reach your key, let those two commands run outside it. They still ask for
confirmation every time:

```json
{
  "sandbox": {
    "enabled": true,
    "excludedCommands": ["git commit:*", "git push:*"]
  }
}
```

See the Claude Code documentation on sandboxing for what your platform needs installed.

## Going further

Not enabled by default because they depend on your setup:

- **Required reviews**: `REQUIRED_APPROVALS=1 REQUIRE_CODE_OWNERS=true scripts/harden-github.sh --apply`.
- **Code scanning**: add CodeQL or a stack-specific analyser once there is code to analyse.
- **Deep local scan**: install gitleaks and `scripts/check.sh` runs it automatically over
  the git history and your uncommitted changes. Do this before publishing an existing
  history. Without gitleaks the step is skipped and the built-in scanner still runs.

## Maintaining the template

- Actions are pinned to commit SHAs and updated by Dependabot.
- The gitleaks, actionlint and zizmor versions in `ci.yml` are pinned by hand
  (version plus SHA-256); bump them together with their checksums.
- `scripts/selftest.sh` proves the hooks block what they claim to block. Add a case
  whenever you add a rule.

## License

Proprietary, all rights reserved. See [LICENSE](LICENSE).
