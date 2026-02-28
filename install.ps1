# PowerShell bootstrap script for windows-dotfiles
# declarative installer similar to the Linux `install.sh`/Makefile

# Make all cmdlet errors terminating so they are caught by try/catch blocks
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $MyInvocation.MyCommand.Definition
# $home is a builtin variable to Powershell, its value is C:\Users\sunjc

Update-FormatData -PrependPath (Join-Path $repo 'Dotfiles.InstallResult.Format.ps1xml')

function Resolve-DotfilesDest {
    param(
        [string]$destRel,
        [bool]$isAbsolute = $false
    )
    if ($isAbsolute) { return $destRel }
    return Join-Path $home $destRel
}

function New-DotfilesDirectoryItem {
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

function Link-DotfilesItem {
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
Path (relative to `$HOME`) where the link should be created, or an absolute
path when `$isAbsolute` is true.

.PARAMETER isAbsolute
Whether destRel is an absolute path.
#>
    param(
        [string]$srcRel,
        [string]$destRel,
        [bool]$isAbsolute = $false
    )
    $src = Join-Path $repo $srcRel
    $dest = Resolve-DotfilesDest $destRel $isAbsolute
    $srcItem = Get-Item $src
    New-DotfilesDirectoryItem (Split-Path $dest -Parent)

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
    # Admin privileges are needed for this, the alternative is to New-Item -ItemType SymbolicLink -Path ($dest).Parent -Target ($src).Parent | Out-Null
    try {
        New-Item -ItemType SymbolicLink -Path $dest -Target $src | Out-Null
    } catch {
        if ($srcItem.PSIsContainer) {
            New-Item -ItemType Junction -Path $dest -Target $src | Out-Null
        } else {
            throw "Admin privileges needed to symlink a file"
        }
    }
}

function Copy-DotfilesItem {
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
Destination path relative to `$HOME`, or an absolute path when `$isAbsolute`
is true.

.PARAMETER isAbsolute
Whether destRel is an absolute path.
#>
    param(
        [string]$srcRel,
        [string]$destRel,
        [bool]$isAbsolute = $false
    )
    $src = Join-Path $repo $srcRel
    $dest = Resolve-DotfilesDest $destRel $isAbsolute
    
    New-DotfilesDirectoryItem (Split-Path $dest -Parent)
    Write-Host "Copying $src to $dest"
    Copy-Item -Path $src -Destination $dest -Force
}

function Add-DotfilesSourceItem {
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
Path to the destination file relative to `$HOME`, or an absolute path when
`$isAbsolute` is true.

.PARAMETER isAbsolute
Whether destRel is an absolute path.

.PARAMETER keyword
The directive to prefix the source path with; defaults to `source`.
#>
    param(
        [string]$srcRel,
        [string]$destRel,
        [bool]$isAbsolute = $false,
        [string]$keyword = 'source'
    )
    $src = Join-Path $repo $srcRel
    $dest = Resolve-DotfilesDest $destRel $isAbsolute
    New-DotfilesDirectoryItem (Split-Path $dest -Parent)

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
    @{ Type = 'link'; Src = '.claude\skills\powershell'; Dest = '.claude\skills\powershell' }
    @{ Type = 'link'; Src = '.claude\skills\new-skill'; Dest = '.claude\skills\new-skill' }
    @{ Type = 'link'; Src = 'Microsoft.PowerShell_profile.ps1'; Dest = $profile; IsAbsolute = $true }
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
        $abs = $a.ContainsKey('IsAbsolute') -and $a.IsAbsolute
        switch ($a.Type) {
            'link'  { Link-DotfilesItem $a.Src $a.Dest $abs }
            'copy'  { Copy-DotfilesItem $a.Src $a.Dest $abs }
            'append' {
                $kw = if ($a.ContainsKey('Keyword')) { $a.Keyword } else { 'source' }
                Add-DotfilesSourceItem $a.Src $a.Dest -isAbsolute $abs -keyword $kw
            }
            default { throw "Unknown action type: $($a.Type)" }
        }
        $status = 'Success'
    } catch {
        $status = "Failed"
        $statusMessage = $_.Exception.Message
    }
    $result = [pscustomobject]@{
        PSTypeName    = 'Dotfiles.InstallResult'
        Installed     = $a.Src
        Method        = $method
        Target        = $a.Dest
        Status        = $status
        StatusMessage = $statusMessage
    }
    $results += $result
}

Write-Host "Bootstrap complete."

if ($results.Count -gt 0) {
    Write-Host "`nSummary:`n"
    $results | Sort-Object -Property Status
}
