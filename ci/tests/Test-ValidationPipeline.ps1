#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$repository = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixture = Join-Path $repository ('work/validation-flow-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$fixture/ci/utils" -Force | Out-Null
Copy-Item "$repository/ci/Run-Pipeline.ps1" "$fixture/ci/Run-Pipeline.ps1"
Set-Content "$fixture/ci/utils/ShortWorkspace.ps1" 'function Invoke-ShortWorkspace($Workspace, $Action) { & $Action $Workspace }'
Set-Content "$fixture/ci/utils/Diagnostics.ps1" 'function Export-BuildDiagnostics($Root) {}'
$stages = @('Test-Runner', 'Test-Ci', 'Prepare-Source', 'Test-Toolchain', 'Prepare-BuildEnvironment',
    'Build-Payload', 'Complete-Payload', 'Sign-Payload', 'Package-Installer', 'Sign-Installer', 'Publish-GitHubRelease', 'Publish-Installer')
foreach ($stage in $stages) {
    Set-Content "$fixture/ci/$stage.ps1" ('Add-Content "$PSScriptRoot/../stages.txt" ' + "'$stage'")
}
New-Item -ItemType Directory -Path "$fixture/preflight/utils" -Force | Out-Null
Copy-Item "$repository/ci/Test-Runner.ps1" "$fixture/preflight/Test-Runner.ps1"
Set-Content "$fixture/preflight/utils/Common.ps1" 'function Assert-FreeDiskSpace { throw "Fixture preflight complete" }'
Set-Content "$fixture/preflight/utils/Publication.ps1" 'function Assert-PublicationAccess { Add-Content "$PSScriptRoot/../checks.txt" "SMB" }'
Set-Content "$fixture/preflight/utils/GitHubRelease.ps1" 'function Assert-GitHubReleaseAccess { Add-Content "$PSScriptRoot/../checks.txt" "GitHub" }'
$previousBranch = $env:BITBUCKET_BRANCH
try {
foreach ($branch in @('', 'codex/test', 'master')) {
    $env:BITBUCKET_BRANCH = $branch
    Set-Content "$fixture/stages.txt" ''
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$fixture/ci/Run-Pipeline.ps1")
    & "$PSHOME/powershell.exe" @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Pipeline fixture failed.' }
    $actual = @(Get-Content "$fixture/stages.txt" | Where-Object { $_ })
    foreach ($required in @('Build-Payload', 'Sign-Payload', 'Package-Installer', 'Sign-Installer')) {
        if ($required -notin $actual) { throw "Required validation stage missing: $required" }
    }
    foreach ($publication in @('Publish-GitHubRelease', 'Publish-Installer')) {
        if (($publication -in $actual) -ne ($branch -ceq 'master')) { throw "Incorrect publication behavior: $publication" }
    }
    Set-Content "$fixture/preflight/checks.txt" ''
    try { & "$fixture/preflight/Test-Runner.ps1" } catch {
        if ($_.Exception.Message -ne 'Fixture preflight complete') { throw }
    }
    $checks = @(Get-Content "$fixture/preflight/checks.txt" | Where-Object { $_ })
    $expected = if ($branch -ceq 'master') { 'GitHub,SMB' } else { '' }
    if (($checks -join ',') -ne $expected) { throw "Incorrect publication preflight for branch '$branch'." }
}
} finally { $env:BITBUCKET_BRANCH = $previousBranch }
Write-Host 'Only master checks publication access and publishes to GitHub and SMB; all branches build and sign (local stage fixtures).'
