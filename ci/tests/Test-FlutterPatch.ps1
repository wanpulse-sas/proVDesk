#Requires -Version 5.1
# Exercise patch updates and snapshot invalidation without invoking Flutter or a compiler.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../utils/FlutterPatch.ps1')
$repository = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixture = Join-Path $repository ('work/flutter-patch-' + [guid]::NewGuid().ToString('N'))
$sdk = Join-Path $fixture 'sdk'
New-Item -ItemType Directory -Force -Path "$sdk/bin/cache" | Out-Null
git -C $sdk init --quiet
if ($LASTEXITCODE -ne 0) { throw 'Cannot initialize the patch fixture.' }
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText("$sdk/tool.dart", "alpha`n", $utf8)
foreach ($entry in @(@('old', 'beta'), @('new', 'gamma'))) {
    $patch = "--- a/tool.dart`n+++ b/tool.dart`n@@ -1 +1 @@`n-alpha`n+$($entry[1])`n"
    [IO.File]::WriteAllText("$fixture/$($entry[0]).patch", $patch, $utf8)
}
$receipt = "$fixture/applied.patch"
Set-FlutterVs2026Patch $sdk "$fixture/old.patch" $receipt
if ([IO.File]::ReadAllText("$sdk/tool.dart").Replace("`r`n", "`n") -ne "beta`n") { throw 'Initial patch was not applied.' }
[IO.File]::WriteAllText("$sdk/bin/cache/flutter_tools.snapshot", 'cached')
[IO.File]::WriteAllText("$sdk/bin/cache/flutter_tools.stamp", 'cached')
Set-FlutterVs2026Patch $sdk "$fixture/old.patch" $receipt
if (-not (Test-Path "$sdk/bin/cache/flutter_tools.snapshot")) { throw 'An unchanged patch invalidated its cache.' }
Set-FlutterVs2026Patch $sdk "$fixture/new.patch" $receipt
if ([IO.File]::ReadAllText("$sdk/tool.dart").Replace("`r`n", "`n") -ne "gamma`n") { throw 'Patch update failed.' }
if ((Test-Path "$sdk/bin/cache/flutter_tools.snapshot") -or (Test-Path "$sdk/bin/cache/flutter_tools.stamp")) {
    throw 'The obsolete tool snapshot was retained.'
}
[IO.File]::WriteAllText("$fixture/bad.patch", "--- a/tool.dart`n+++ b/tool.dart`n@@ -1 +1 @@`n-missing`n+bad`n", $utf8)
$failed = $false
try { Set-FlutterVs2026Patch $sdk "$fixture/bad.patch" $receipt } catch { $failed = $true }
if (-not $failed -or [IO.File]::ReadAllText("$sdk/tool.dart").Replace("`r`n", "`n") -ne "gamma`n" -or
    (Get-FileHash $receipt).Hash -ne (Get-FileHash "$fixture/new.patch").Hash) {
    throw 'A failed update did not preserve the previous SDK patch and receipt.'
}
[IO.File]::WriteAllText("$sdk/tool.dart", "unrelated change`n", $utf8)
$failed = $false
try { Set-FlutterVs2026Patch $sdk "$fixture/old.patch" $receipt } catch { $failed = $true }
if (-not $failed -or [IO.File]::ReadAllText("$sdk/tool.dart").Replace("`r`n", "`n") -ne "unrelated change`n") {
    throw 'Unrecognized local SDK changes were overwritten.'
}
Write-Host 'Flutter patch update, idempotence, rollback and snapshot invalidation passed; no build was run.'
