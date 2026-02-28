---
name: powershell
description: Conventions for writing idiomatic PowerShell 5.1 scripts
user-invocable: false
---

# PowerShell Conventions

When generating or modifying PowerShell scripts, follow these rules:

## Approved Verbs

Use Microsoft's approved verbs for function names (the set returned by
`Get-Verb`).  For example use `New-`, `Get-`, `Set-`, `Remove-`, `Invoke-`,
`Resolve-`, `Test-`, `Add-`, `Copy-`, `Import-`, etc.

## Namespace Prefix

Apply a project-specific namespace as a prefix to the **Noun** part of
every function name, in the form `Verb-<Namespace><Noun>`.  For example,
in the windows-dotfiles repo the namespace is `Dotfiles`:

- `New-DotfilesDirectoryItem`
- `Link-DotfilesItem`
- `Copy-DotfilesItem`
- `Resolve-DotfilesDest`

When working in a different project, derive an appropriate short namespace
from the project name and use it consistently.

## PowerShell 5.1 Compatibility

Target PowerShell 5.1 (Windows PowerShell) unless told otherwise.  This means:

- No ternary operator (`$x ? $a : $b`) — use `if`/`else` instead.
- No null-coalescing (`??`) or null-conditional (`?.`) operators.
- No `&&` or `||` pipeline chain operators — use `if`/`else` or semicolons.
- No `` `e `` escape for ANSI — use `[char]27` instead.
