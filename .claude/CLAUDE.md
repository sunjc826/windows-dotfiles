# User Instructions

## Dotfiles Repository

This is a **dotfiles repo**. Files here are symlinked/copied onto the system
via `install.ps1`. When asked to create or modify system configuration files
(e.g. PowerShell profiles, Claude Code settings, skills, shell configs), always
create them **in this repo** — not directly on the system. The installer will
take care of placing them in the correct system locations.

## Shell Environment

This is a Windows machine with two bash environments available:

1. **Git Bash** — located at `C:\Program Files\Git\bin\bash.exe`
   - Uses MINGW64 paths: `/c/Users/sunjc/...`
2. **WSL1 bash** — located at `C:\WINDOWS\system32\bash.exe` (the default `bash` on PATH)
   - Uses WSL mount paths: `/mnt/c/Users/sunjc/...`

**IMPORTANT for the Bash tool:** The Bash tool uses **Git Bash (MINGW64)**, not WSL1. This means:       
- Use Git Bash style paths: `/c/Users/sunjc/...` (e.g., `/c/Users/sunjc/Documents/Projects/vscode`).    
- Do **NOT** use WSL1 style paths like `/mnt/c/Users/...` — those won't resolve in Git Bash.
- **ALWAYS use forward slashes (`/`)** instead of backslashes (`\\`) in Bash commands.
- `/tmp` maps to `C:\Users\sunjc\AppData\Local\Temp\` (useful for the stdout workaround below).

## Bash Tool stdout Workaround

The Bash tool on Windows has a known bug where **any command that produces stdout fails with exit code 1
** (see [claude-code#26558](https://github.com/anthropics/claude-code/issues/26558)). The stdout pipe is broken due to an incompatibility with MSYS2/WSL's fd translation.                                      
**Workaround:** Redirect output to a temp file, then use the Read tool to retrieve it:
```bash
command > /tmp/cc_output.txt 2>&1; true
```
Then use `Read` on `C:\Users\sunjc\AppData\Local\Temp\cc_output.txt` to see the output.

**Temp file policy:**
- Use a **single file** `/tmp/cc_output.txt` for all Bash output — overwrite it each time (do NOT create numbered variants like `cc_output2.txt`).                                                            
- For the rare case where multiple parallel Bash calls need separate outputs, use `/tmp/cc_out_1.txt`, `/tmp/cc_out_2.txt`, etc., and **clean them up immediately** after reading with `rm -f /tmp/cc_out_*.txt 2>/dev/null; true`.                                                                                     
- **Always clean up** temp files at the end of a session or when they are no longer needed.

Remove this section once the bug is fixed upstream.
