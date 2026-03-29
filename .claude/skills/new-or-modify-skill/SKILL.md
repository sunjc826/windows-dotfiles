---
name: new-or-modify-skill
description: Reference for creating, renaming, moving, or modifying Claude Code skills
---

# Creating and Modifying Claude Code Skills

## Directory Structure

Skills live under `.claude/skills/<skill-name>/SKILL.md`. The scope determines
where they are discovered:

- `~/.claude/skills/` — personal skills, available across all projects
- `<project>/.claude/skills/` — project-scoped skills

Each skill is a directory containing a required `SKILL.md` and optional
supporting files (templates, examples, scripts) that can be referenced from the
main file.

```
.claude/skills/
  my-skill/
    SKILL.md            # required
    reference.md        # optional supporting docs
    examples/
      sample.md
    scripts/
      helper.sh
```

### User-Level Skills (this machine)

Personal skills are managed through the **windows-dotfiles** repo and symlinked
into `~/.claude/skills/` by the installer. When creating a new user-level skill:

1. Create the skill directory in the dotfiles repo:
   `C:\Users\sunjc\Documents\Projects\windows-dotfiles\.claude\skills\<skill-name>\SKILL.md`
2. Register the skill in `install.ps1` by adding an entry to the `$actions` array:
   ```powershell
   @{ Type = 'link'; Src = '.claude\skills\<skill-name>'; Dest = '.claude\skills\<skill-name>' }
   ```
3. Run the installer (or manually symlink for immediate use):
   ```bash
   ln -sfn /c/Users/sunjc/Documents/Projects/windows-dotfiles/.claude/skills/<skill-name> \
           /c/Users/sunjc/.claude/skills/<skill-name>
   ```

**Never** create user-level skills directly in `~/.claude/skills/` — they won't
be tracked by git or deployed to other machines.

## Renaming or Moving Skills

When renaming a user-level skill, update **all three** locations:

1. **Directory name** — rename the folder under
   `windows-dotfiles/.claude/skills/`
2. **Frontmatter `name`** — update in `SKILL.md`
3. **`install.ps1`** — update the `Src`/`Dest` in the `$actions` array to match
   the new name, and remove the old entry

Then remove the old symlink and create the new one (or re-run the installer):

```bash
rm -rf ~/.claude/skills/<old-name>
ln -sfn /c/Users/sunjc/Documents/Projects/windows-dotfiles/.claude/skills/<new-name> \
        /c/Users/sunjc/.claude/skills/<new-name>
```

## SKILL.md Format

A YAML frontmatter block followed by Markdown instructions.

```yaml
---
name: my-skill
description: Short description of what the skill does
user-invocable: true
disable-model-invocation: false
allowed-tools: Read, Grep
context: fork
agent: Explore
model: opus
argument-hint: [issue-number]
---

# Instructions in Markdown

Steps, rules, or knowledge that Claude should follow.
```

## Frontmatter Fields

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `name` | string | directory name | Display name for `/skill-name` invocation. Lowercase, hyphens, numbers only, max 64 chars. |
| `description` | string | — | What the skill does. Claude uses this to decide when to auto-load it. |
| `user-invocable` | bool | `true` | If `false`, hidden from the `/` menu. Use for background knowledge. |
| `disable-model-invocation` | bool | `false` | If `true`, Claude will not auto-load the skill; only manual `/name` invocation works. |
| `allowed-tools` | string | — | Comma-separated tools Claude can use without asking (e.g. `Read, Grep, Glob`). |
| `context` | string | — | Set to `fork` to run in an isolated subagent context. |
| `agent` | string | — | Subagent type when using `context: fork` (e.g. `Explore`, `Plan`, `general-purpose`). |
| `model` | string | — | Override the model (e.g. `opus`, `sonnet`, `haiku`). |
| `argument-hint` | string | — | Hint shown in autocomplete (e.g. `[issue-number]`). |

## Argument Substitution

When invoked as `/my-skill arg1 arg2`, arguments are available as:

- `$0`, `$1`, ... — positional arguments
- `$ARGUMENTS[0]`, `$ARGUMENTS[1]`, ... — array syntax
- `$ARGUMENTS` — all arguments as a string

## Dynamic Context

Use `` !`command` `` to inject shell command output into the skill body at load
time:

```markdown
## Current branch
!`git branch --show-current`
```

## Common Patterns

**Background knowledge (auto-loaded by Claude when relevant):**
```yaml
---
name: conventions
description: Coding conventions for this project
user-invocable: false
---
```

**Manual-only task (side effects like deploying):**
```yaml
---
name: deploy
description: Deploy the application
disable-model-invocation: true
---
```

**Isolated research:**
```yaml
---
name: research
description: Deep-dive research into a topic
context: fork
agent: Explore
---
```

## Writing High-Quality Skills

For comprehensive guidance on writing effective, discoverable, and well-tested
skills — including TDD-based validation, search optimization, and
bulletproofing — use `superpowers:writing-skills` (if the superpowers plugin is
installed).

## Skills vs Commands

Skills (`.claude/skills/`) supersede the older commands system
(`.claude/commands/`). Commands still work but skills take precedence when both
exist with the same name. Skills support supporting files, automatic invocation,
and richer frontmatter.
