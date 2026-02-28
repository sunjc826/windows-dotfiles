---
name: new-skill
description: Reference for creating new Claude Code skills
---

# Creating Claude Code Skills

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

## Skills vs Commands

Skills (`.claude/skills/`) supersede the older commands system
(`.claude/commands/`). Commands still work but skills take precedence when both
exist with the same name. Skills support supporting files, automatic invocation,
and richer frontmatter.
