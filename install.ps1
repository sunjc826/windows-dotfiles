# PowerShell bootstrap script for windows-dotfiles
# declarative installer similar to the Linux `install.sh`/Makefile
[CmdletBinding()]
param()

# Don't prompt the user for confirmation
if ($DebugPreference -eq 'Inquire') {
    $DebugPreference = 'Continue'
}
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
directory already exists. Also creates the parents if missing like mkdir -p.

.PARAMETER path
The full filesystem path of the directory to verify or create.
#>
    param([string]$path)
    if (-not (Test-Path $path)) {
        Write-Debug "Creating directory $path"
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

function New-DotfilesLinkItem {
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
        switch ($item.LinkType) {
            'SymbolicLink' {
                $target = $item.Target
                if ($target -eq $src) {
                    Write-Debug "Existing symlink already correct: $dest -> $src"
                    return
                } else {
                    throw "$dest is a symlink but points to $target instead of $src. Please fix manually."
                }
            }
            'Junction' {
                $target = $item.Target
                if ($target -eq $src) {
                    Write-Debug "Existing junction already correct: $dest -> $src"
                    return
                } else {
                    throw "$dest is a junction but points to $target instead of $src. Please fix manually."
                }
            }
            default {
                throw "$dest exists and is neither a symbolic link nor junction (LinkType=${item.LinkType}). Please rename or remove it before running the installer."
            }
        }
    }

    Write-Debug "Creating symbolic link $dest -> $src"
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
    Write-Debug "Copying $src to $dest"
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
            Write-Debug "Destination already contains '$line', skipping."
            return
        }
    }
    Write-Debug "Appending line '$line' to $dest"
    Add-Content -Path $dest -Value $line
}

# $hkcuFound = $false
# $hkcu = Get-PSProvider | Where-Object Name -Eq Registry | Select-Object -ExpandProperty Drives | Where-Object Root -Eq HKEY_CURRENT_USER | Select-Object Name

# if ($hkcu.GetType().Name -eq 'String') {
#     $hkcuFound = $true
# }
# elseif ($null -eq $hkcu) {
#     Write-Error 'Cannot find HKCU registry'
# }
# elseif ($hkcu.GetType().IsArray) {
#     Write-Error 'Multiple entries for HKEY_CURRENT_USER found'
# }

function Add-DotfilesUserPathItem {
<#
.SYNOPSIS
Append an item to the user registry path, if not already present.
If not absolute, then it will relative to `$HOME`.

.PARAMETER Path
Path name.

.PARAMETER IsAbsolute
Whether Path is an absolute path.
#>
    param(
        [string]$path,
        [bool]$isAbsolute = $false,
        [bool]$isRegistry = $true
    )
    $resolvedPath = Resolve-DotfilesDest $path $isAbsolute
    if (!$isRegistry) {
        $currentUserPath = ${env:PATH}
    }
    else {
        $currentUserPath = Get-ItemProperty HKCU:\Environment -Name Path | Select-Object -ExpandProperty Path
    }

    if ($currentUserPath -split ';' -contains $resolvedPath) {
        Write-Debug "$path already exists in user path"
    }

    $nextPathValue = $currentUserPath + ";$resolvedPath"
    if (!$isRegistry) {
        ${env:PATH} = $nextPathValue   
    } else {
        Set-ItemProperty HKCU:\Environment -Name Path -Value $nextPathValue
    }
}

function Set-DotfilesUserEnvironmentItem {
<#
.SYNOPSIS
Append an item to the user registry environment, if not already present.
If not absolute, then it will relative to `$HOME`.

.PARAMETER Path
Path name.

.PARAMETER IsAbsolute
Whether Path is an absolute path.
#>
    param(
        [string]$name,
        [string]$value,
        [bool]$isOverride = $false,
        [bool]$isRegistry = $true
    )
    $currentValue = $null
    if (!$isRegistry) {
        if (Get-ChildItem Env:\ | Where-Object Name -eq $name) {
            $currentValue = Get-Item Env:\$name
        }
    }
    else {
        if (Get-Item HKCU:\Environment | Where-Object Property -eq $name) {
            $currentValue = Get-ItemProperty HKCU:\Environment -Name $name | Select-Object -ExpandProperty $name
        }
    }

    if ($null -ne $currentValue) {
        if ($currentValue -eq $value) {
            Write-Debug "$name already set to $value"
            return
        }

        if (!$isOverride) {
            throw "$name currently set to $currentValue"
        }
    }

    Write-Debug "Setting env $name to $value"
    if (!$isRegistry) {
        Set-Item Env:\$name -Value $value 
    }
    else {
        Set-ItemProperty HKCU:\Environment -Name $name -Value $value
    }
}

$coreDrive = 'C'
$dataDrive = 'C'
if (Get-PSDrive | Where-Object Name -eq 'D') {
    $dataDrive = 'D'
}

# declare what should happen; this mirrors the Linux style of having a list
$actions = @(
    @{ Type = 'link'; Src = '.claude\settings.json'; Dest = '.claude\settings.json' }
    @{ Type = 'link'; Src = '.claude\CLAUDE.md'; Dest = '.claude\CLAUDE.md'; Optional = $true }
    @{ Type = 'link'; Src = '.claude\skills\powershell'; Dest = '.claude\skills\powershell' }
    @{ Type = 'link'; Src = '.claude\skills\new-skill'; Dest = '.claude\skills\new-skill' }
    @{ Type = 'link'; Src = 'Microsoft.PowerShell_profile.ps1'; Dest = $profile; IsAbsolute = $true }
    @{ Type = 'mkdir'; Path = "${dataDrive}:\LLM"; isAbsolute = $true }
    @{ Type = 'userEnv'; Name = 'OLLAMA_MODELS'; Value = "${dataDrive}:\LLM"; IsAbsolute = $true; IsOverride = $true }
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
        $override = $a.ContainsKey('IsOverride') -and $a.IsOverride
        switch ($a.Type) {
            'link'  { New-DotfilesLinkItem $a.Src $a.Dest $abs }
            'copy'  { Copy-DotfilesItem $a.Src $a.Dest $abs }
            'append' {
                $kw = if ($a.ContainsKey('Keyword')) { $a.Keyword } else { 'source' }
                Add-DotfilesSourceItem $a.Src $a.Dest -isAbsolute $abs -keyword $kw
            }
            'userPath' {
                $isRegistry = !$a.ContainsKey('IsRegistry') -or $a.IsRegistry
                Add-DotfilesUserPathItem $a.Path $abs $isRegistry
            }
            'mkdir' { New-DotfilesDirectoryItem $a.Path $abs }
            'userEnv' {
                $isRegistry = !$a.ContainsKey('IsRegistry') -or $a.IsRegistry
                Set-DotfilesUserEnvironmentItem -name $a.Name -value $a.Value -isOverride $override -isRegistry $isRegistry
            }
            default { throw "Unknown action type: $($a.Type)" }
        }
        $status = 'Success'
    } catch {
        $status = "Failed"
        $statusMessage = $_.Exception.Message
    }
    switch ($a.Type) {
        'mkdir'    { $src = $null;    $dest = $a.Path }
        'userPath' { $src = $a.Path;  $dest = 'PATH' }
        'userEnv'  { $src = $a.Value; $dest = $a.Name }
        default    { $src = $a.Src;   $dest = $a.Dest }
    }
    $result = [pscustomobject]@{
        PSTypeName    = 'Dotfiles.InstallResult'
        Installed     = $src
        Method        = $method
        Target        = $dest
        Status        = $status
        StatusMessage = $statusMessage
    }
    $results += $result
}

Write-Debug "Bootstrap complete."

if ($results.Count -gt 0) {
    Write-Debug "`nSummary:`n"
    $results | Sort-Object -Property Status
}
