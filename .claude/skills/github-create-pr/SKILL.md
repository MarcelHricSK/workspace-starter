---
name: github-create-pr
description: Open a GitHub pull request for the current branch, following the repository's PR template. Use when the user asks to open, draft or update a PR.
license: LicenseRef-MarcelHric-Proprietary
metadata:
  author: Marcel Hric
  version: "1.0.0"
---

# Create a pull request

Open a GitHub pull request for the **current branch** against the repository's default
branch. Companion to the `git-commit` skill, which covers branches, commits and signing.

A pull request is visible to others, so open one only when the user asks. When finished
work looks ready for review, offer to open it instead of doing so.

Pull requests are reviewed and merged by humans. Never merge, approve, enable auto-merge
or push to the default branch yourself.

## Steps

1. **Gather the branch state.**
   - `git rev-parse --abbrev-ref HEAD`: the current branch
   - `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`: the base branch

   Then `git fetch origin <base>` so the comparison is against the remote, not a stale
   local copy, and run these together:
   - `git log origin/<base>..HEAD --format='%h %s%n%b'`: the commits the PR will
     contain, with their bodies (for tickets and breaking changes)
   - `git diff origin/<base>...HEAD --stat`: the files it changes
   - `git status --short`: uncommitted work
   - `gh pr list --head <branch> --state open --json number,url,title,body`: an
     existing PR

   Stop early when:
   - **the branch is the base branch**: changes need their own branch first (see
     `git-commit`).
   - **there are no commits** ahead of the base: there is nothing to review.

   When **a PR is already open** for the branch, do not create another. Push any new
   commits (step 3), then compare its title and description with the commits. If they
   no longer describe the branch, show the user what is out of date and, once they
   agree, update it with `gh pr edit <number> --title "<title>" --body-file -`, written
   as in steps 4 and 5. Report its URL.

2. **Leave uncommitted work alone.** Only committed work goes into a PR. If
   `git status` shows changes, do not stage or commit them unless the user asks; tell
   them those files are not included and continue with what is committed.

3. **Push the branch** if it has no upstream or is ahead of it:
   `git push -u origin <branch>`.
   - Never force-push, and never rebase or reset to make a push go through.
   - **Rejected because the remote has commits this branch lacks:** stop and tell the
     user. Whether to merge or rebase their work is their call.
   - **Rejected by a hook** (branch name, signing, secret scan): fix the cause as
     `git-commit` describes; never bypass the hook.

4. **Write the title**: `<type>[(<scope>)][!]: <subject>`, in Conventional Commits style
   (lowercase, imperative, no trailing period, about 72 characters at most).
   - With one commit, reuse its subject. With several, summarize the branch as a whole,
     using the type of the most significant change (`feat` over `fix` over `refactor`).
   - **Breaking changes.** If any commit marks one (`!` before the colon, or a
     `BREAKING CHANGE:` footer), add `!` to the title and say in the body how users
     migrate.
   - **Tickets.** Look for ticket keys in `Refs:` footers of the commits and in the
     branch name (`feat/ABC-123-add-login` gives `ABC-123`). Write them as the tracker
     does, usually uppercase. Where they go depends on the repository:
     - If the repository's instructions (CLAUDE.md, CONTRIBUTING.md) say where, follow
       them.
     - Otherwise look at recent titles:
       `gh pr list --state merged --limit 10 --json title --jq '.[].title'`. If they
       start with the ticket (`[ABC-123] feat: …`), do the same.
     - Otherwise put `Refs: ABC-123` at the end of the body and keep the title clean.
     - Never invent a ticket. A branch without one gets a PR without one.

5. **Write the body.**
   - **Use the repository's template** when there is one:
     `.github/pull_request_template.md` or `.github/PULL_REQUEST_TEMPLATE.md`. Keep its
     headings and order, replace every comment placeholder with real content, and keep
     its checklist: tick an item only when it is actually true for this change; leave
     the rest unticked and say why underneath.
   - **Otherwise use the default template**, `templates/pull_request.md` in this
     skill's directory (see "Default template" below).
   - **Either way**, add the call-out sections below that apply, and write for a
     reviewer who has not seen the conversation:
     - **Summary:** what the PR does and why. One sentence for a trivial change. Two to
       four for a fix or a feature: the root cause for a fix, the motivation for a
       feature. If it builds on another open PR, add `Depends on #123`.
     - **Reviewer notes** (only when useful; right after the summary): the risky or
       non-obvious part of the diff, trade-offs, anything you would point out in person.
     - **Changes:** concrete changes as bullets, each led by the file, module or area it
       touches. Group them by area when the diff is large.
     - **Testing:** the tests added or changed (name the key cases when they document
       behaviour) and the commands that were actually run, such as `scripts/check.sh`.
       Say plainly what was not verified: "compiles, not run", "CI only",
       "manual flow not exercised".
   - **Write it as if it were public**, because on a public repository it is: no
     secrets or tokens, internal hostnames or URLs, customer or personal data, and no
     raw logs or stack traces that may contain them. Summarize instead.
   - No "Generated with" footer and no co-author or attribution lines.

6. **Create the PR** with the body passed through a file or a quoted heredoc, so
   backticks and `$` in it are not run by the shell:

   ```bash
   gh pr create --base <base> --head <branch> --title "<title>" --body-file - <<'EOF'
   <body>
   EOF
   ```

   Open it ready for review unless the user asked for a draft (`--draft`).

7. **Report** the PR URL, and repeat which uncommitted files were left out, if any.

## Call-out sections

Add each section only when the diff touches that area (check the file list from step 1).
They go after Changes and before Testing; with a repository template, put them before
its checklist.

| Section             | When                                                                                                                                   | What to write                                                                         |
|---------------------|----------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------|
| `## Security`       | Auth, permissions, secrets handling, git hooks, CI workflows, `.claude/` settings, hooks or skills, dependency or supply-chain changes | What changed in the safety net and why it is still sound                              |
| `## Config changes` | New or changed config keys, environment variables (`.env.example`), infrastructure config                                              | What each environment must set before deploying                                       |
| `## Data migration` | Schema changes, data migrations, backfills                                                                                             | What it migrates, rough volume, whether it is safe to run again                       |
| `## API changes`    | Public endpoints, request or response shapes, CLI flags, library exports                                                               | Each change marked **additive** or **breaking**, with the migration for breaking ones |
| `## Deploy notes`   | More than one deployable part, or a shared package others depend on                                                                    | What must be redeployed, and in which order if it matters                             |

## Default template

[templates/pull_request.md](templates/pull_request.md), in this skill's directory, is
the body to fill in when the repository has no template of its own. Replace every
`<placeholder>`, and leave out `Reviewer notes` and `Refs` when they do not apply.

## Title examples

```
feat(auth): add passkey sign-in
fix: keep the session after a token refresh
feat(api)!: drop the v1 endpoints            ← breaking change
[ABC-123] fix: correct the retry delay        ← repository puts tickets in titles
chore: bump dependencies
```
