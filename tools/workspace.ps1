#Requires -Version 5.1
<#
.SYNOPSIS
  Context Workbench — native PowerShell implementation (no Python).
  Same commands as: python tools/workspace.py ...

.EXAMPLE
  ./tools/workspace.ps1 list
  ./tools/workspace.ps1 create "Acme Corporation"
  ./tools/workspace.ps1 create technical-architect "Acme Corporation"
  ./tools/workspace.ps1 sync ./WORKSPACES/default_acme
#>
$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptRoot "..")).Path
$RegistryPath = Join-Path $RepoRoot "registry.json"
$WorkbenchName = "WORKBENCH.json"
$MaxSlugLen = 10
$DefaultWorkspaces = "WORKSPACES"
$DefaultBp = "default"

function Die([string]$Msg) {
    Write-Error "context-bench: $Msg"
    exit 1
}

function Get-Registry {
    if (-not (Test-Path -LiteralPath $RegistryPath)) { Die "missing $RegistryPath" }
    Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Normalize-ClientSlug([string]$Raw) {
    $s = ($Raw.ToLower() -creplace '[^a-z0-9]', '')
    if ([string]::IsNullOrEmpty($s)) { $s = "client" }
    if ($s.Length -gt $MaxSlugLen) { $s = $s.Substring(0, $MaxSlugLen) }
    return $s
}

function Get-BlueprintFolderPrefix([string]$BlueprintId) {
    return $BlueprintId.ToLower().Replace("-", "_")
}

function Get-DefaultFolderName([string]$BlueprintId, [string]$Raw) {
    return "$(Get-BlueprintFolderPrefix $BlueprintId)_$(Normalize-ClientSlug $Raw)"
}

function Test-ExplicitPath([string]$Arg) {
    $s = $Arg.Trim()
    if ($s.Length -eq 0 -or $s -eq "." -or $s -eq "..") { return $true }
    if ($s.Contains("/") -or $s.Contains("\")) { return $true }
    if ([System.IO.Path]::IsPathRooted($s)) { return $true }
    if ($s.Length -gt 1 -and $s[1] -eq ":" -and [char]::IsLetter($s[0])) { return $true }
    return $false
}

function Copy-TreeMerge([string]$Src, [string]$Dst) {
    if (-not (Test-Path -LiteralPath $Src -PathType Container)) { Die "missing directory: $Src" }
    Get-ChildItem -LiteralPath $Src -Recurse -File | ForEach-Object {
        $srcP = $_.FullName
        $rel = $srcP.Substring((Resolve-Path $Src).Path.Length).TrimStart([char[]]@('\', '/'))
        $out = Join-Path $Dst $rel
        $dir = Split-Path -Parent $out
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Copy-Item -LiteralPath $srcP -Destination $out -Force
    }
}

function Merge-Layers([string]$BlueprintId, [string]$Target, $Reg) {
    $bpNames = @($Reg.blueprints.psobject.Properties.Name)
    if ($bpNames -notcontains $BlueprintId) {
        Die "unknown blueprint `"$BlueprintId`". Use: list"
    }
    $bp = $Reg.blueprints.$BlueprintId
    $sharedRel = $Reg.sharedRoot
    $shared = Join-Path $RepoRoot $sharedRel
    Copy-TreeMerge $shared $Target
    foreach ($ov in @($bp.overlays)) {
        if ([string]::IsNullOrEmpty($ov)) { continue }
        Copy-TreeMerge (Join-Path $RepoRoot $ov) $Target
    }
}

function Reset-Directories([string]$Target, $Reg) {
    foreach ($name in @($Reg.resetDirectories)) {
        if ([string]::IsNullOrEmpty($name)) { continue }
        $d = Join-Path $Target $name
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Get-ChildItem -LiteralPath $d -Force | Remove-Item -Recurse -Force
        New-Item -ItemType File -Path (Join-Path $d ".gitkeep") -Force | Out-Null
    }
}

function Get-MetaDirForBlueprint([string]$BlueprintId, $Reg) {
    $bp = $Reg.blueprints.$BlueprintId
    $first = $null
    if ($bp.overlays -and $bp.overlays.Count -gt 0) { $first = $bp.overlays[0] }
    if ($first) { return Join-Path $RepoRoot $first }
    return Join-Path $RepoRoot $Reg.sharedRoot
}

function Write-WorkbenchJson(
    [string]$Target,
    [string]$BlueprintId,
    [string]$ClientDisplay,
    [string]$ClientSlug,
    [string]$DirName,
    $Reg
) {
    $mdir = Get-MetaDirForBlueprint $BlueprintId $Reg
    $metaPath = Join-Path $mdir "metadata.json"
    $bpver = "0"
    $bplabel = ""
    $bprole = $null
    if (Test-Path -LiteralPath $metaPath) {
        $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($meta.version) { $bpver = [string]$meta.version }
        if ($meta.label) { $bplabel = [string]$meta.label }
        $bprole = $meta.role
    }
    $regEntry = $Reg.blueprints.$BlueprintId
    if ([string]::IsNullOrEmpty($bplabel) -and $regEntry.label) { $bplabel = [string]$regEntry.label }
    $regVer = if ($null -ne $Reg.version) { $Reg.version } else { 1 }
    $created = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")

    $doc = [ordered]@{
        schema_version = 1
        blueprint      = [ordered]@{
            id      = $BlueprintId
            version = $bpver
            label   = $bplabel
            role    = $bprole
        }
        engagement     = [ordered]@{
            client_display_name = if ([string]::IsNullOrWhiteSpace($ClientDisplay)) { $null } else { $ClientDisplay }
            client_slug         = if ([string]::IsNullOrWhiteSpace($ClientSlug)) { $null } else { $ClientSlug }
        }
        paths          = [ordered]@{ directory_name = $DirName }
        registry       = [ordered]@{ version = $regVer }
        created_utc    = $created
        generator      = [ordered]@{ tool = "tools/workspace.ps1"; kind = "create" }
    }
    $json = $doc | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath (Join-Path $Target $WorkbenchName) -Value $json -Encoding UTF8
}

function Read-WorkbenchBlueprintId([string]$Target) {
    $f = Join-Path $Target $WorkbenchName
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try {
        $w = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
        return [string]$w.blueprint.id
    } catch { return $null }
}

function Update-WorkbenchSync([string]$Target, [string]$BlueprintId, $Reg) {
    $f = Join-Path $Target $WorkbenchName
    $mdir = Get-MetaDirForBlueprint $BlueprintId $Reg
    $metaPath = Join-Path $mdir "metadata.json"
    $bpver = "0"
    if (Test-Path -LiteralPath $metaPath) {
        $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($meta.version) { $bpver = [string]$meta.version }
    }
    $ts = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $lsb = [pscustomobject]@{ id = $BlueprintId; version = $bpver }
    if (Test-Path -LiteralPath $f) {
        $j = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
        $j | Add-Member -NotePropertyName last_synced_utc -NotePropertyValue $ts -Force
        $j | Add-Member -NotePropertyName last_sync_blueprint -NotePropertyValue $lsb -Force
        $j | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $f -Encoding UTF8
    } else {
        [pscustomobject]@{
            schema_version      = 1
            last_synced_utc     = $ts
            last_sync_blueprint = $lsb
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $f -Encoding UTF8
    }
}

function Invoke-List {
    $Reg = Get-Registry
    Write-Output "Blueprints (id - label)"
    Write-Output ""
    $Reg.blueprints.PSObject.Properties | ForEach-Object {
        $bid = $_.Name
        $m = $_.Value
        $suf = ""
        if ($m.description) { $suf = " - $($m.description)" }
        Write-Output "  $bid"
        Write-Output "    $($m.label)$suf"
        Write-Output ""
    }
}

function Invoke-Create {
    param([string[]]$Positional, [string]$ParentRaw, [switch]$NoReset, [switch]$GitInit)
    $Reg = Get-Registry
    $parent = $null
    if ($ParentRaw) {
        $expanded = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ParentRaw)
        New-Item -ItemType Directory -Path $expanded -Force | Out-Null
        $parent = (Resolve-Path -LiteralPath $expanded).Path
    } else {
        $parent = Join-Path $RepoRoot $DefaultWorkspaces
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        $parent = (Resolve-Path $parent).Path
    }

    $bid = $null
    $name = $null
    if ($Positional.Count -eq 1) {
        if (@($Reg.blueprints.psobject.Properties.Name) -notcontains $DefaultBp) {
            Die "registry must define `"$DefaultBp`" for single-argument create"
        }
        $bid = $DefaultBp
        $name = $Positional[0]
    } elseif ($Positional.Count -eq 2) {
        $bid = $Positional[0]
        $name = $Positional[1]
        if (@($Reg.blueprints.psobject.Properties.Name) -notcontains $bid) {
            Die "unknown blueprint `"$bid`". Use: list"
        }
    } else {
        Die "create: expected 1 or 2 arguments after options:`n  create `"Client or path`"`n  create technical-architect `"Client or path`""
    }

    $target = $null
    $clientDisplay = $null
    $clientSlug = $null
    $dirName = $null
    if (Test-ExplicitPath $name) {
        if ([System.IO.Path]::IsPathRooted($name)) {
            $target = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($name)
        } else {
            $target = Join-Path $parent $name
        }
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        $target = (Resolve-Path -LiteralPath $target).Path
        $dirName = Split-Path -Leaf $target
    } else {
        $dirName = Get-DefaultFolderName $bid $name
        $target = Join-Path $parent $dirName
        $clientDisplay = $name.Trim()
        $clientSlug = Normalize-ClientSlug $name
    }

    if ((Test-Path -LiteralPath $target) -and (Get-ChildItem -LiteralPath $target -Force | Select-Object -First 1)) {
        Die "refusing to write into non-empty directory:`n  $target"
    }
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Merge-Layers $bid $target $Reg
    if (-not $NoReset) { Reset-Directories $target $Reg }
    Write-WorkbenchJson $target $bid $clientDisplay $clientSlug $dirName $Reg
    if ($GitInit) {
        Push-Location $target
        try {
            & git init
            if ($LASTEXITCODE -ne 0) { Die "git init failed" }
        } finally { Pop-Location }
    }
    Write-Output "Created workspace:"
    Write-Output "  $target"
    Write-Output "Blueprint: $bid"
    if (-not $NoReset) {
        Write-Output "Reset to empty: $($Reg.resetDirectories -join ', ') (.gitkeep only in each)."
    }
    Write-Output "Wrote $WorkbenchName (use for sync without repeating blueprint id)."
}

function Invoke-Sync {
    param([string]$A1, [string]$A2, [switch]$DryRun)
    $Reg = Get-Registry
    $bid = $null
    $target = $null
    if ($A2) {
        $bid = $A1
        $target = (Resolve-Path -LiteralPath $A2).Path
    } else {
        $target = (Resolve-Path -LiteralPath $A1).Path
        $bid = Read-WorkbenchBlueprintId $target
        if ([string]::IsNullOrEmpty($bid)) {
            Die "no blueprint id in $(Join-Path $target $WorkbenchName). Use: sync BLUEPRINT PATH"
        }
    }
    if (-not (Test-Path -LiteralPath $target -PathType Container)) { Die "not a directory: $target" }
    if (-not (Test-Path -LiteralPath (Join-Path $target ".agent-instructions.md"))) {
        Write-Warning "$(Join-Path $target '.agent-instructions.md') missing - sync may be wrong folder."
    }
    if (@($Reg.blueprints.psobject.Properties.Name) -notcontains $bid) { Die "unknown blueprint `"$bid`"" }

    if ($DryRun) {
        Write-Output "Would update from blueprint '$bid' (last overlay wins per path):"
        Write-Output ""
        $sharedRel = $Reg.sharedRoot
        $map = @{}
        Get-ChildItem -LiteralPath (Join-Path $RepoRoot $sharedRel) -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            $rel = $_.FullName.Substring((Resolve-Path (Join-Path $RepoRoot $sharedRel)).Path.Length).TrimStart([char[]]@('\', '/'))
            $map[$rel] = $_.FullName
        }
        foreach ($ov in @($Reg.blueprints.$bid.overlays)) {
            if ([string]::IsNullOrEmpty($ov)) { continue }
            $root = Join-Path $RepoRoot $ov
            Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                $rel = $_.FullName.Substring((Resolve-Path $root).Path.Length).TrimStart([char[]]@('\', '/'))
                $map[$rel] = $_.FullName
            }
        }
        foreach ($rel in ($map.Keys | Sort-Object)) {
            $tag = if (Test-Path -LiteralPath (Join-Path $target $rel)) { "exists" } else { "new" }
            Write-Output "  [$tag] $rel"
        }
        Write-Output ""
        Write-Output "Dry run only; no files written."
        return
    }

    Merge-Layers $bid $target $Reg
    Update-WorkbenchSync $target $bid $Reg
    Write-Output "Synced blueprint '$bid' into:"
    Write-Output "  $target"
    Write-Output "Engagement data under INPUTS, TASK-DEFINITIONS, WORK-IN-PROGRESS, DELIVERABLES was not cleared."
    Write-Output "Matching paths from blueprints were overwritten."
    Write-Output "Updated $WorkbenchName (last_synced_utc)."
}

# --- entry ---
if ($args.Count -lt 1) { Die "usage: $($MyInvocation.MyCommand.Name) list / create / sync ..." }

$cmd = $args[0]
switch ($cmd) {
    "list" {
        Invoke-List
    }
    "create" {
        $rest = @($args | Select-Object -Skip 1)
        $parentRaw = $null
        $noReset = $false
        $gitInit = $false
        $pos = [System.Collections.ArrayList]@()
        $i = 0
        while ($i -lt $rest.Count) {
            switch ($rest[$i]) {
                { $_ -in "--parent", "-p" } {
                    $i++
                    if ($i -ge $rest.Count) { Die "create: --parent needs a value" }
                    $parentRaw = $rest[$i]
                    $i++
                }
                "--no-reset" { $noReset = $true; $i++ }
                "--git" { $gitInit = $true; $i++ }
                default { [void]$pos.Add($rest[$i]); $i++ }
            }
        }
        Invoke-Create -Positional @($pos) -ParentRaw $parentRaw -NoReset:$noReset -GitInit:$gitInit
    }
    "sync" {
        $rest = @($args | Select-Object -Skip 1)
        $dry = $false
        $pos = [System.Collections.ArrayList]@()
        foreach ($x in $rest) {
            if ($x -eq "--dry-run") { $dry = $true } else { [void]$pos.Add($x) }
        }
        if ($pos.Count -lt 1) { Die "sync: need PATH or BLUEPRINT PATH" }
        if ($pos.Count -ge 2) {
            Invoke-Sync -A1 $pos[0] -A2 $pos[1] -DryRun:$dry
        } else {
            Invoke-Sync -A1 $pos[0] -A2 $null -DryRun:$dry
        }
    }
    default { Die "unknown command '$cmd'. Use: list, create, or sync" }
}
