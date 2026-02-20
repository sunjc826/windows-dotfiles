# PowerShell bootstrap script for windows-dotfiles
# declarative installer similar to the Linux `install.sh`/Makefile

$repo = Split-Path -Parent $MyInvocation.MyCommand.Definition
$home = $HOME

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
Create or replace a symbolic link under the user's home directory.

.DESCRIPTION
Given a source file inside the repository and a destination path relative to
`$HOME`, this helper ensures the parent directory of the destination exists,
removes any existing item at that location, and then creates a symbolic link
pointing from the destination to the source.

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
        Write-Host "Removing existing $dest"
        Remove-Item $dest -Force
    }
    Write-Host "Linking $dest -> $src"
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
Append the contents of a repository file to a user file.

.DESCRIPTION
Useful when building composite configuration files by concatenating several
fragments.  Ensures the destination directory exists, then reads the source
file and appends its text to the end of the destination file.

.PARAMETER srcRel
Path to the source file relative to the repository root.

.PARAMETER destRel
Path to the destination file relative to `$HOME`.
#>
    param(
        [string]$srcRel,
        [string]$destRel
    )
    $src = Join-Path $repo $srcRel
    $dest = Join-Path $home $destRel
    Ensure-Directory (Split-Path $dest -Parent)
    Write-Host "Appending content of $src to $dest"
    Get-Content $src | Add-Content $dest
}

# declare what should happen; this mirrors the Linux style of having a list
$actions = @(
    @{ Type = 'link'; Src = '.claude\settings.json'; Dest = '.claude\settings.json' }
    @{ Type = 'link'; Src = '.claude\CLAUDE.md'; Dest = '.claude\CLAUDE.md'; Optional = $true }
    # future items could be copied, appended, etc.
)

foreach ($a in $actions) {
    if ($a.Optional -and -not (Test-Path (Join-Path $repo $a.Src))) {
        continue
    }
    switch ($a.Type) {
        'link' { Ensure-Link $a.Src $a.Dest }
        'copy' { Ensure-Copy $a.Src $a.Dest }
        'append' { Append-Source $a.Src $a.Dest }
        default { Write-Warning "Unknown action type: $($a.Type)" }
    }
}

Write-Host "Bootstrap complete."
