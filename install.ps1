# PowerShell bootstrap script for windows-dotfiles
# declarative installer similar to the Linux `install.sh`/Makefile

$repo = Split-Path -Parent $MyInvocation.MyCommand.Definition
# $home is a builtin variable to Powershell, its value is C:\Users\sunjc

function Ensure-Directory {
<#
.SYNOPSIS
Ensures that a directory exists, creating it if necessary.

.DESCRIPTION
This helper checks whether the given path exists.  If it does not it will
create the directory structure using New-Item.  No error is thrown if the
directory already exists.

.PARAMETER path
The full filesystem path of the directory to verify or create.
#>
    param([string]$path)
    if (-not (Test-Path $path)) {
        Write-Host "Creating directory $path"
        New-Item -ItemType Directory -Path $path | Out-Null
    }
}

function Ensure-Link {
<#
.SYNOPSIS
Ensure a symbolic link exists at the destination pointing at the source.

.DESCRIPTION
This helper behaves idempotently: if the destination already exists as a
symbolic link pointing to the correct source file, nothing is done.  If the
destination exists but is *not* a symlink or points somewhere else, an error
is thrown so it appears as a failure in the summary; it is the user's
responsibility to remove or correct it manually.  Only when the destination is absent is a new
link created.

.PARAMETER srcRel
Path to the source file, relative to the repository root.

.PARAMETER destRel
Path (relative to `$HOME`) where the link should be created.
#>
    param(
        [string]$srcRel,
        [string]$destRel
    )
    $src = Join-Path $repo $srcRel
    $dest = Join-Path $home $destRel
    Ensure-Directory (Split-Path $dest -Parent)

    if (Test-Path $dest) {
        $item = Get-Item -Path $dest -Force
        if ($item.LinkType -eq 'SymbolicLink') {
            $target = $item.Target
            if ($target -eq $src) {
                Write-Host "Existing symlink already correct: $dest -> $src"
                return
            } else {
                throw "$dest is a symlink but points to $target instead of $src. Please fix manually."
            }
        } else {
            throw "$dest exists and is not a symbolic link. Please rename or remove it before running the installer."
        }
    }

    Write-Host "Creating symbolic link $dest -> $src"
    New-Item -ItemType SymbolicLink -Path $dest -Target $src | Out-Null
}

function Ensure-Copy {
<#
.SYNOPSIS
Copy a file from the repository into the user's home directory.

.DESCRIPTION
Makes sure the destination directory exists and then copies the source file
from the repo into `$HOME` at the specified relative path.  Any existing file
at the destination is overwritten.

.PARAMETER srcRel
Source path relative to the repository root.

.PARAMETER destRel
Destination path relative to `$HOME`.
#>
    param(
        [string]$srcRel,
        [string]$destRel
    )
    $src = Join-Path $repo $srcRel
    $dest = Join-Path $home $destRel
    Ensure-Directory (Split-Path $dest -Parent)
    Write-Host "Copying $src to $dest"
    Copy-Item -Path $src -Destination $dest -Force
}

function Append-Source {
<#
.SYNOPSIS
Append a statement to a destination file, if not already present.

.DESCRIPTION
This helper does *not* copy the contents of the source file.  Instead it adds a
line of the form `<keyword> <absolute‑path‑to‑source>` to the destination file
(e.g. `source /path/to/file` or `.` on POSIX).  The keyword can be overridden
to accommodate different shell languages or tools.  Before appending it uses
`Select-String` to determine whether such a line already exists, providing
idempotency: running the installer multiple times won't repeatedly add the
same entry.

.PARAMETER srcRel
Path to the source file relative to the repository root.

.PARAMETER destRel
Path to the destination file relative to `$HOME`.

.PARAMETER keyword
The directive to prefix the source path with; defaults to `source`.
#>
    param(
        [string]$srcRel,
        [string]$destRel,
        [string]$keyword = 'source'
    )
    $src = Join-Path $repo $srcRel
    $dest = Join-Path $home $destRel
    Ensure-Directory (Split-Path $dest -Parent)

    $line = "$keyword $src"
    if (Test-Path $dest) {
        if (Select-String -Path $dest -Pattern [regex]::Escape($line) -Quiet) {
            Write-Host "Destination already contains '$line', skipping."
            return
        }
    }
    Write-Host "Appending line '$line' to $dest"
    Add-Content -Path $dest -Value $line
}

# declare what should happen; this mirrors the Linux style of having a list
$actions = @(
    @{ Type = 'link'; Src = '.claude\settings.json'; Dest = '.claude\settings.json' }
    @{ Type = 'link'; Src = '.claude\CLAUDE.md'; Dest = '.claude\CLAUDE.md'; Optional = $true }
    # future items could be copied, appended, etc.
)

# track what we did for reporting
$results = @()

foreach ($a in $actions) {
    if ($a.Optional -and -not (Test-Path (Join-Path $repo $a.Src))) {
        continue
    }
    $method = $a.Type
    $status = 'unknown'
    $statusMessage = $null
    try {
        switch ($a.Type) {
            'link'  { Ensure-Link $a.Src $a.Dest }
            'copy'  { Ensure-Copy $a.Src $a.Dest }
            'append' {
                $kw = if ($a.ContainsKey('Keyword')) { $a.Keyword } else { 'source' }
                Append-Source $a.Src $a.Dest -keyword $kw
            }
            default { throw "Unknown action type: $($a.Type)" }
        }
        $status = 'Success'
    } catch {
        $status = "Failed"
        $statusMessage = $_.Exception.Message
    }
    $results += [pscustomobject]@{
        Installed = $a.Src
        Method    = $method
        Target    = $a.Dest
        Status    = $status
        StatusMessage = $statusMessage
    }
}

Write-Host "Bootstrap complete."

if ($results.Count -gt 0) {
    Write-Host "`nSummary:`n"
    $results | Sort-Object -Property Status
}
