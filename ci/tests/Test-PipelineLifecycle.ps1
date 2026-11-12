#Requires -Version 5.1
# Local-only integration test: replace build stages with harmless fixture scripts.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repository = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$before = (& "$env:SystemRoot/System32/subst.exe") -join "`n"
$previousBranch = $env:BITBUCKET_BRANCH
try {
$env:BITBUCKET_BRANCH = 'master'
foreach ($failureStage in @('', 'Test-Runner', 'Test-Toolchain', 'Build-Payload', 'Sign-Installer', 'Publish-GitHubRelease', 'Publish-Installer')) {
    $fail = [bool]$failureStage
    $fixture = Join-Path $repository ('work/lifecycle-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path "$fixture/ci/utils" | Out-Null
    foreach ($file in @('Run-Pipeline.ps1', 'Cleanup-Workspace.ps1', 'utils/ShortWorkspace.ps1', 'utils/Diagnostics.ps1')) {
        Copy-Item "$repository/ci/$file" "$fixture/ci/$file"
    }
    $stage = @'
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Add-Content "$root/stages.txt" $MyInvocation.MyCommand.Name
if ($root -notmatch '^[D-Z]:\\$') { throw 'Build stage did not receive short path.' }
New-Item -ItemType Directory -Force -Path "$root/build-tools/vcpkg/buildtrees/fixture" | Out-Null
Set-Content "$root/build-tools/vcpkg/buildtrees/fixture/stdout.log" 'fixture diagnostic'
'@
    foreach ($name in @('Test-Runner', 'Test-Ci', 'Prepare-Source', 'Test-Toolchain', 'Prepare-BuildEnvironment', 'Build-Payload',
            'Complete-Payload', 'Sign-Payload', 'Package-Installer', 'Sign-Installer', 'Publish-GitHubRelease', 'Publish-Installer')) {
        $content = $stage
        if ($name -eq $failureStage) { $content += "`r`nexit 23" }
        Set-Content "$fixture/ci/$name.ps1" $content -Encoding UTF8
    }
    & "$PSHOME/powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$fixture/ci/Run-Pipeline.ps1"
    $code = $LASTEXITCODE
    if (($code -ne 0) -ne $fail) { throw 'Pipeline exit status did not preserve the stage failure.' }
    & "$PSHOME/powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$fixture/ci/Cleanup-Workspace.ps1"
    if ($LASTEXITCODE -ne 0) { throw 'After-script failed.' }
    if (-not (Test-Path "$fixture/diagnostics/build-tools/vcpkg/buildtrees/fixture/stdout.log")) { throw 'Diagnostics missing.' }
    if ($failureStage -eq 'Test-Toolchain' -and (Get-Content "$fixture/stages.txt") -contains 'Prepare-BuildEnvironment.ps1') { throw 'Heavy preparation ran after a failed preflight.' }
    $executed = @(Get-Content "$fixture/stages.txt")
    if ($failureStage -and $failureStage -ne 'Publish-Installer' -and $executed -contains 'Publish-Installer.ps1') { throw 'Publication ran after an earlier failure.' }
    if (-not $fail -and $executed[-1] -ne 'Publish-Installer.ps1') { throw 'Publication was not the last stage.' }
    if ($failureStage -eq 'Test-Runner' -and $executed.Count -ne 1) { throw 'Later stages ran after a failed runner preflight.' }
    if (Test-Path "$fixture/.ci-subst.json") { throw 'SUBST state was not cleaned.' }
    if (((& "$env:SystemRoot/System32/subst.exe") -join "`n") -ne $before) { throw 'SUBST mapping leaked.' }
}
} finally { $env:BITBUCKET_BRANCH = $previousBranch }
Write-Host 'Pipeline success/failure, diagnostics and after-script lifecycle tests passed.'
