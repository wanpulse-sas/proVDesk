#Requires -Version 5.1
# Exercise temporary mappings without building, signing or changing ACLs.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../utils/ShortWorkspace.ps1')
$repository = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixture = Join-Path $repository ('work/subst-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$child = @'
$ErrorActionPreference = 'Stop'
if ($PSScriptRoot -notmatch '^[D-Z]:\\$') { throw "Child path expanded: $PSScriptRoot" }
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'child-path.txt'), $PSScriptRoot)
$drive = New-Object IO.DriveInfo([IO.Path]::GetPathRoot($PSScriptRoot))
if ($drive.AvailableFreeSpace -le 0) { throw 'Mapped drive disk query failed.' }
'@
Set-Content -LiteralPath (Join-Path $fixture 'child.ps1') -Value $child -Encoding UTF8
$before = (& "$env:SystemRoot/System32/subst.exe") -join "`n"
Invoke-ShortWorkspace $fixture {
    param($shortRoot)
    & "$PSHOME/powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $shortRoot 'child.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Child process failed.' }
}
if (-not (Test-Path (Join-Path $fixture 'child-path.txt'))) { throw 'Child output missing from physical workspace.' }
$failed = $false
try { Invoke-ShortWorkspace $fixture { param($shortRoot) throw 'Expected test failure' } } catch {
    if ($_.Exception.Message -ne 'Expected test failure') { throw }
    $failed = $true
}
if (-not $failed) { throw 'Build failure was swallowed.' }
Remove-ShortWorkspace $fixture
if (Test-Path (Join-Path $fixture '.ci-subst.json')) { throw 'Ownership record was not removed.' }
$after = (& "$env:SystemRoot/System32/subst.exe") -join "`n"
if ($before -ne $after) { throw 'SUBST mappings changed after cleanup.' }
# Exercise fallback cleanup while the ownership record is still present.
Invoke-ShortWorkspace $fixture {
    param($shortRoot)
    Remove-ShortWorkspace $fixture
    if (Test-Path -LiteralPath $shortRoot) { throw 'Fallback cleanup did not remove the drive.' }
}
[pscustomobject]@{ Drive = 'Z:'; Target = 'C:\another-workspace' } |
    ConvertTo-Json | Set-Content (Join-Path $fixture '.ci-subst.json') -Encoding UTF8
$refused = $false
try { Remove-ShortWorkspace $fixture } catch { $refused = $true }
if (-not $refused) { throw 'Foreign ownership record accepted.' }
Remove-Item -LiteralPath (Join-Path $fixture '.ci-subst.json')
Write-Host 'SUBST lifecycle tests passed: child path, disk space, success, failure, fallback and ownership.'
