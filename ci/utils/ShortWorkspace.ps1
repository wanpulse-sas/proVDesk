# Map the existing workspace without moving files or changing ACLs.
function Get-WorkspaceMappings {
    $lines = & "$env:SystemRoot/System32/subst.exe"
    if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate SUBST mappings.' }
    $mappings = @{}
    foreach ($line in $lines) {
        if ($line -match '^([A-Za-z]:)\\: => (.+)$') {
            $mappings[$Matches[1].ToUpperInvariant()] = $Matches[2].TrimEnd('\')
        }
    }
    return $mappings
}

function Remove-ShortWorkspace([string]$Workspace) {
    $statePath = Join-Path $Workspace '.ci-subst.json'
    if (-not (Test-Path -LiteralPath $statePath)) { return }
    $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $expected = [IO.Path]::GetFullPath($Workspace).TrimEnd('\')
    if ($state.Drive -notmatch '^[D-Z]:$' -or $state.Target -ne $expected) {
        throw 'Invalid workspace SUBST ownership record; refusing cleanup.'
    }
    $mappings = Get-WorkspaceMappings
    if ($mappings.ContainsKey($state.Drive)) {
        if ($mappings[$state.Drive] -ne $expected) { throw 'SUBST target changed; refusing to remove another mapping.' }
        & "$env:SystemRoot/System32/subst.exe" $state.Drive /D
        if ($LASTEXITCODE -ne 0) { throw "Cannot remove workspace drive $($state.Drive)." }
        Write-Host "Removed workspace drive $($state.Drive)"
    } elseif ([IO.Directory]::Exists($state.Drive + '\')) {
        throw 'Drive is no longer a SUBST mapping; refusing cleanup.'
    }
    Remove-Item -LiteralPath $statePath -ErrorAction Stop
}

function Invoke-ShortWorkspace([string]$Workspace, [scriptblock]$Action) {
    $physicalRoot = [IO.Path]::GetFullPath($Workspace).TrimEnd('\')
    $statePath = Join-Path $physicalRoot '.ci-subst.json'
    if (Test-Path -LiteralPath $statePath) { throw 'A workspace SUBST record already exists; run Cleanup-Workspace.ps1 first.' }
    $mappings = Get-WorkspaceMappings
    $occupied = @([IO.Directory]::GetLogicalDrives() | ForEach-Object { $_.TrimEnd('\') })
    $occupied += @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Name + ':' })
    $drive = $null
    foreach ($letter in 90..68) {
        $candidate = ([char]$letter).ToString() + ':'
        if ($candidate -notin $occupied -and -not $mappings.ContainsKey($candidate)) { $drive = $candidate; break }
    }
    if (-not $drive) { throw 'No free drive letter is available for the CI workspace.' }
    & "$env:SystemRoot/System32/subst.exe" $drive $physicalRoot
    if ($LASTEXITCODE -ne 0) { throw "Cannot map workspace to $drive" }
    $previousLocation = Get-Location
    try {
        # Record ownership so after-script can retry cleanup if this process stops.
        [pscustomobject]@{ Drive = $drive; Target = $physicalRoot } |
            ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
        $shortRoot = $drive + '\'
        Write-Host "Workspace: $shortRoot -> $physicalRoot"
        & $Action $shortRoot
    } finally {
        Set-Location -LiteralPath $physicalRoot
        if (Test-Path -LiteralPath $statePath) {
            Remove-ShortWorkspace $physicalRoot
        } else {
            # State creation may have failed; only remove the mapping just created.
            $current = Get-WorkspaceMappings
            if ($current.ContainsKey($drive) -and $current[$drive] -eq $physicalRoot) {
                & "$env:SystemRoot/System32/subst.exe" $drive /D
                if ($LASTEXITCODE -ne 0) { throw "Cannot remove workspace drive $drive" }
            }
        }
        Set-Location -LiteralPath $previousLocation.Path
    }
}
