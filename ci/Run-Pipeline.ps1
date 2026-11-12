#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'utils/ShortWorkspace.ps1')
$workspace = Split-Path $PSScriptRoot -Parent
Invoke-ShortWorkspace $workspace {
    param($shortRoot)
    # Start each child through its short path so PSScriptRoot stays short too.
    Set-Location -LiteralPath $shortRoot
    try {
        foreach ($stage in @('Test-Runner', 'Test-Ci', 'Prepare-Source', 'Test-Toolchain', 'Prepare-BuildEnvironment',
                'Build-Payload', 'Complete-Payload', 'Sign-Payload', 'Package-Installer', 'Sign-Installer', 'Publish-Installer')) {
            Write-Host "=== $stage ==="
            & "$PSHOME/powershell.exe" -NoProfile -File (Join-Path $shortRoot "ci/$stage.ps1")
            if ($LASTEXITCODE -ne 0) { throw "$stage failed (exit $LASTEXITCODE)." }
        }
    } finally {
        # Collect while the short drive still exists; never replace the build error.
        try {
            . (Join-Path $shortRoot 'ci/utils/Diagnostics.ps1')
            Export-BuildDiagnostics $shortRoot
        } catch { Write-Warning 'Diagnostic collection failed; cleanup will still run.' }
    }
}
