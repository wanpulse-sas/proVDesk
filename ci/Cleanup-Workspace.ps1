#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'utils/ShortWorkspace.ps1')
$workspace = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $workspace
try {
    # Fallback for a terminated build process. Reuse its verified short mapping.
    $statePath = Join-Path $workspace '.ci-subst.json'
    $collectionRoot = $workspace
    if (Test-Path -LiteralPath $statePath) {
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $mappings = Get-WorkspaceMappings
        if ($state.Target -eq $workspace -and $mappings.ContainsKey($state.Drive) -and $mappings[$state.Drive] -eq $workspace) {
            $collectionRoot = $state.Drive + '\'
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $workspace 'diagnostics/index.txt'))) {
        . (Join-Path $PSScriptRoot 'utils/Diagnostics.ps1')
        Export-BuildDiagnostics $collectionRoot
    }
} catch { Write-Warning 'Fallback diagnostic collection failed.' }
finally { Remove-ShortWorkspace $workspace }
