---
name: git-commit
description: Commit-message, branch, staging and signing conventions enforced by this repository's git hooks. Read before staging changes, drafting or amending a commit, creating a branch, or pushing, and whenever a git hook rejects something.
license: LicenseRef-MarcelHric-Proprietary
metadata:
  author: Marcel Hric
  version: "1.0.0"
---

# Git commits & branches

The rules here are enforced by `.githooks/` (`pre-commit`, `commit-msg`, `pre-push`) and
repeated server-side by GitHub rulesets, so a commit that breaks them is rejected rather
than merely frowned upon. If this file and a hook ever disagree, the hook is right; fix
this file.

## Workflow: when asked to commit

1. **Look first.** `git status` and `git diff --staged` show what is actually staged.
2. **Get off `main`.** It only accepts pull requests, so create a branch if you are on
   it, named `<type>/<description>` (see [Branches](#branches)). If the project requires
   tickets and you do not know the ticket, ask for it.
3. **Stage by filename**, one logical change at a time (see [Staging](#staging)). If the
   changes span unrelated areas, propose splitting them before writing any message.
4. **Run `scripts/check.sh`** when the change touches more than docs. It runs what CI
   runs, so problems surface now instead of on the pull request.
5. **Write the message**: pick the type from the [table](#types), add a scope if one
   package dominates, then one imperative sentence (see [Message format](#message-format)).
6. **Commit with no bypass flags.** The commit is signed automatically (see
   [Signing](#signing)). Committing and pushing each ask the user for confirmation.
7. **If a hook rejects it**, fix the cause (see [When a hook rejects](#when-a-hook-rejects)).

## Message format

```
<type>[(<scope>)][!]: <subject>

[body: wrap at 72 cols, explain WHY not WHAT]

[footer: Refs: TIC-123, BREAKING CHANGE: ...]
```

### Types

These eleven are the only ones `commit-msg` accepts. Anything else, including `update`
and `wip`, is rejected.

| Type | Use for |
| --- | --- |
| `feat` | a new endpoint, feature or capability |
| `fix` | a bug fix |
| `refactor` | internal restructuring with no behaviour change |
| `perf` | same behaviour, faster or lighter |
| `test` | tests only |
| `docs` | documentation only |
| `style` | formatting only, no code change |
| `ci` | workflows and CI configuration |
| `build` | build system and packaging |
| `chore` | dependency bumps, gitignore, housekeeping |
| `revert` | undoing an earlier commit |

### Scope

Optional. Use a package or feature name when it helps the reader: `feat(core): …`,
`fix(ui): …`. Lowercase letters, digits, `.`, `_`, `/` and `-` only; the hook rejects
`feat(Core)`.

### Subject

- Lowercase first letter, imperative mood ("add", "fix", not "added", "fixed")
- No trailing period
- Aim for ≤ 72 characters; the hook rejects a first line over 100
- Say what changed; the why belongs in the body
- No ticket id in the subject; it goes in the footer

### Body and footer

Add a body only when the subject is not self-explanatory: a blank line, then prose on
motivation, context or trade-offs. Keep it to about four lines unless a gotcha genuinely
needs more.

When the work has a ticket, reference it in the footer as `Refs: TIC-123`, using the same
key as the branch name. Take it from the branch when you are on a ticket branch; do not
invent one when there is none.

Mark a breaking change with `!` before the colon and a `BREAKING CHANGE:` footer that
tells the reader how to migrate.

Do not add Claude as co-author or any attribution trailer; the repository's settings
turn attribution off on purpose.

## Branches

Name branches `<type>/<short-kebab-description>`:

```
feat/add-user-subjects
fix/login-redirect
docs/setup-guide
```

- **Type**: the same types as commits (see the [table](#types)). Default to `feat` when
  in doubt.
- **Description**: a few lowercase words in kebab-case saying what the branch does.

### Tickets

Whether a ticket is required is a project setting. Check before creating a branch:

```bash
git config --no-includes --file .hooksconfig --type=bool --get hooks.requireTicket
```

- **Prints `true`:** the ticket is mandatory and goes right after the slash, written
  exactly as the tracker writes it: `feat/TIC-123-add-user-subjects`. If you do not know
  the ticket, ask the user before creating the branch; do not guess a number or invent
  one. Only the types listed in `hooks.ticketlessTypes` (default `chore`) may omit it,
  and only when the user confirms there is no ticket.
- **Prints nothing or `false`:** tickets are optional. Use one when the work has one,
  leave it out otherwise.

A ticket used in the branch name also goes in the commit footer as `Refs: TIC-123`,
never in the subject.

`pre-push` checks the name, so a wrong one is rejected when you push; rename with
`git branch -m <new-name>`. `main` and bot branches (`dependabot/…`, `renovate/…`) are
exempt. `main` only takes pull requests, and humans merge them. Some repositories also
set `hooks.blockProtectedPush`, in which case the hook itself refuses a push to `main`.

## Staging

- **Stage by filename** (`git add path/to/file.md`). `git add -A` and `git add .` sweep up
  untracked drafts and stray local files that were never meant to be shared.
- **Keep secrets out.** Never stage `.env*`, key files, data directories or
  `.claude/settings.local.json`. The one exception is `.env.example`, which holds
  placeholders only. No real credential belongs anywhere in a diff, including tests,
  fixtures and docs: once pushed, it has to be rotated, not just deleted.
- **One logical change per commit.** A migration, the service method that uses it and the
  test for that method are one commit. A migration and an unrelated rename are two.
- **Guardrails get their own commit.** Changes under `.githooks/`, `.claude/`, `.github/`
  or `scripts/` affect everyone's safety net, so keep them separate and call them out in
  the pull request.

## Signing

Every commit must be signed. `scripts/setup.sh` turns on `commit.gpgsign` for the clone,
so a plain `git commit` signs without extra flags.

- Do not pass `--no-gpg-sign` or turn off `commit.gpgsign`. GitHub rejects unsigned
  commits on every branch, so an unsigned commit only fails later and further from its
  cause.
- If signing fails (locked or missing key, pinentry cannot prompt), stop and tell the
  user. Do not retry unsigned.
- To sign commits that slipped through: `git commit --amend --no-edit -S` for the last
  one, or `git rebase --exec 'git commit --amend --no-edit -S' <base>` for a series. The
  rebase rewrites history, so ask first.

## When a hook rejects

| Hook | Rejects |
| --- | --- |
| `pre-commit` | secrets and credential-looking values, `.env*` and key files, merge conflict markers, files over 1 MB |
| `commit-msg` | a subject that is not `<type>(<scope>)!: <description>` with an allowed type, or a first line over 100 characters |
| `pre-push` | secrets in any outgoing commit, unsigned commits, a branch name that breaks the convention, force-push or deletion of `main`, and (where configured) any direct push to `main` |

Fix the cause and commit again. Do not reach for `--no-verify`, `git commit -n`, a
changed `core.hooksPath` or a switched-off `hooks.*` setting: the same checks run in CI and on GitHub, so bypassing locally
only moves the failure to a place where it is harder to fix.

If the secret scanner flags something that is not a secret, show the user the finding
and let them decide whether to append `gitleaks:allow` to the line or add the path to
`.secretscanignore`. Each exception is a blind spot, so that choice is theirs.

Never force-push, and do not rewrite pushed history unless the user asks for it.

## Examples

Good:

```
fix: correct provider id propagation in tests
```

```
ci: pin actionlint to 1.7.12
```

```
feat(auth): add date of birth validation to signup

Required by the new terms version, which makes the field mandatory.
Validates >= 18 years on submission.

Refs: TIC-123
```

```
feat(api)!: drop v1 endpoints

BREAKING CHANGE: clients must move to /v2; see docs/migration.md.
```

Bad:

```
Added user subjects.            ← no type, wrong tense, capitalized, period
update                          ← no type, no subject
update: bump dependencies       ← "update" is not an allowed type; use chore
feat(Core): add cache           ← scope must be lowercase
feat: TIC-123 add user subjects ← ticket goes in the footer, not the subject
```

Branch names:

```
feat/add-user-subjects          ← good (rejected only where tickets are required)
feat/TIC-123-add-user-subjects  ← good everywhere
chore/bump-deps                 ← good everywhere: chore may omit the ticket
feature/add-user-subjects       ← "feature" is not a type; use feat
add-user-subjects               ← missing type
feat/Add_User_Subjects          ← description not lowercase kebab-case
feat/TIC-123                    ← ticket but no description
```
