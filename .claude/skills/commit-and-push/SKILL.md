---
name: commit-and-push
description: Commit session changes with meaningful messages and push. Use "all" argument to commit all changes in logical chunks.
user-invocable: true
argument-hint: [all]
---

# Commit and Push

Commit changes and push to the remote branch.

## Mode Selection

- **Default (no argument):** Commit only files changed during this Claude Code session. Ignore unrelated modifications.
- **`all`:** Commit every staged and unstaged change in the working tree, splitting into multiple logical commits if the changes span unrelated concerns.

## Procedure

1. Run `git status` and `git diff` (staged + unstaged) to survey all changes.
2. Run `git log --oneline -5` to match the repo's commit message style.
3. **Determine scope:**
   - Default mode: identify which files were touched in this session. Exclude anything else.
   - `all` mode: include everything.
4. **Group into commits.** If the changes form one coherent unit, use a single commit. If they span distinct concerns (e.g., a new feature + a config fix + a docs update), split into multiple commits in logical order — foundations first, dependents after.
5. For each commit:
   - Stage only the relevant files by name (never `git add -A` or `git add .`).
   - Write a concise commit message (1-2 sentences) focused on **why**, not **what**. End every message with:
     ```
     Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
     ```
   - Use a HEREDOC for the message to preserve formatting.
6. After all commits succeed, push to the current remote tracking branch. If no upstream is set, push with `-u origin HEAD`.
7. Report what was committed and the push result.

## Rules

- Never commit files that likely contain secrets (`.env`, credentials, tokens). Warn if encountered.
- Never use `--no-verify` or `--no-gpg-sign`.
- Never amend existing commits — always create new ones.
- Never force push.
- If a pre-commit hook fails, fix the issue, re-stage, and create a **new** commit.
- Always pass commit messages via HEREDOC:
  ```bash
  git commit -m "$(cat <<'EOF'
  Message here.

  Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
  EOF
  )"
  ```
