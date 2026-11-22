# Contributing

## Setup

```bash
scripts/setup.sh
```

This enables the git hooks in `.githooks/` and turns on commit signing for the clone.
Run it once per clone.

### Commit signing

Commits must be signed; unsigned commits are rejected at push. If `scripts/setup.sh`
reports that no signing key is configured, the quickest route is an SSH key:

```bash
git config --global gpg.format ssh
```

```bash
git config --global user.signingkey ~/.ssh/id_ed25519.pub
```

```bash
git config --global commit.gpgsign true
```

Then add the same public key to GitHub under **Settings > SSH and GPG keys** as a
**signing key** (a separate entry from an authentication key), and re-run
`scripts/setup.sh`. An existing GPG key works too.

## Workflow

1. Branch from `main` as `<type>/<short-description>`, for example
   `feat/add-user-subjects` or `fix/login-redirect`. The type is one of the commit types
   below. If the project requires tickets (`requireTicket = true` in `.hooksconfig`), put
   the tracker key after the slash, `feat/TIC-123-add-user-subjects`, and reference it in
   the commit footer as `Refs: TIC-123`. The `pre-push` hook rejects branches that do not
   match.
2. Commit in small, reviewable steps using [Conventional Commits](https://www.conventionalcommits.org/):
   `type(scope): description`, with type one of
   `build`, `chore`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`, `revert`, `style`, `test`.
   Mark breaking changes with `!` (`feat(api)!: drop v1 endpoints`).
3. Run the checks before pushing:

   ```bash
   scripts/check.sh
   ```

4. Open a pull request. `main` only accepts changes through pull requests with a green `ci-ok` check.

## Rules that are not negotiable

- **No secrets in the repository.** Not in code, tests, fixtures, logs, screenshots or commit
  messages. Document variables in `.env.example`; keep values in an untracked `.env`.
- **Do not bypass the hooks** (`--no-verify`) to get a commit through. If a check is wrong,
  fix the check in the same pull request and say so.
- **Sign every commit.** No `--no-gpg-sign`, no switching `commit.gpgsign` off.
- **Pin what you depend on.** Lockfiles are committed; GitHub Actions are pinned to a full
  commit SHA with the version in a trailing comment.
- **Changes to guardrails get extra scrutiny.** Anything under `.github/`, `.githooks/`,
  `.claude/` or `scripts/` must be called out in the pull request description.

## Reporting security issues

See [SECURITY.md](SECURITY.md). Never open a public issue for a vulnerability.
