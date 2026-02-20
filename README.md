# windows-dotfiles

This repository holds configuration and helper scripts for setting up a Windows user environment, analogous to the Linux dotfiles I have kept for years.

## Overview

The goal is to track various personal configuration files (`dotfiles`) in Git so that a fresh Windows machine can be bootstrapped quickly. Windows doesn't use `make` the way my Linux setup does, so installation scripts are typically PowerShell or batch-based, and symlinks are created using `New-Item -ItemType SymbolicLink` or similar.

## Migrating Claude Settings

The Claude CLI stores its per‑user configuration in a `settings.json` file under `%USERPROFILE%\.claude` (e.g. `C:\Users\sunjc\.claude\settings.json`).

To keep the setting under version control:

1. The repository contains:

* a `.claude/settings.json` file with the preferred values (currently just `"autoUpdatesChannel": "latest"`)
* a `.claude/CLAUDE.md` file carrying any user notes or instructions originally present in `%USERPROFILE%\\.claude\\CLAUDE.md`.

2. After cloning the repo on a new machine, create a symbolic link from your home directory to the tracked file:
```powershell
# run from your Windows PowerShell prompt
cd $HOME
New-Item -ItemType SymbolicLink -Path .claude\settings.json -Target "${PWD}\windows-dotfiles\.claude\settings.json"
```

   or simply copy the file if you prefer:
```powershell
Copy-Item -Path "$PWD\windows-dotfiles\.claude\settings.json" -Destination "$HOME\.claude\settings.json" -Force
```

3. Adjust the JSON as needed; any changes should be committed back to the repository so they propagate to other machines.  The `CLAUDE.md` file can also be edited locally and tracked.

> ⚠️ On Windows the parent `.claude` directory must exist before creating the link; use `New-Item -ItemType Directory -Path $HOME\.claude` if necessary.

You can extend this section with more Windows-specific dotfiles (PowerShell profile, registry exports, etc.) as the repo grows.

### Bootstrapping

A simple PowerShell script `install.ps1` is provided at the top level. It is written in a declarative style (inspired by the Linux `install.sh`/Makefile) – you list the operations you want to perform in an array and the helper functions take care of creating directories, links, copies or appends.

The helpers are documented with comments at the top of `install.ps1`; each function explains what it does and describes its parameters. Feel free to read the script for details or to extend the helpers if you need more behaviour.

Running it will ensure the necessary directories exist and create the symbolic links for the Claude files:

```powershell
# from within the repository root
.\\install.ps1
```

Feel free to extend the `$actions` array inside `install.ps1` with more entries (`link`, `copy`, `append`, etc.) to manage additional configuration files in a declarative fashion.  The behaviour of the helpers has been designed to be safe:

* `Ensure-Link` will **not** overwrite an existing file.  If the destination is already a symlink pointing to the correct source nothing happens; if it points elsewhere or is not a link you’ll receive a warning and must resolve the conflict manually.
* `Append-Source` will only add a `<keyword> <path>` line if that exact statement is not already present, preserving idempotency when the installer is rerun.  The keyword defaults to `source` but may be overridden (e.g. `.` for POSIX shells) by supplying a `Keyword` field in the corresponding action entry.

After the run, the script emits a **summary table** listing what was processed, which method was used, the target path, and whether each step succeeded or failed.  This makes it easy to inspect results in PowerShell's naturally object‑oriented output.


