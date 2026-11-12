# Apply the maintained patch to a fresh SDK or update a previously patched local SDK.
function Set-FlutterVs2026Patch([string]$Sdk, [string]$Patch, [string]$Receipt) {
    function Invoke-PatchGit([string[]]$Arguments) {
        $previous = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $output = & git -C $Sdk apply @Arguments 2>&1
            $code = $LASTEXITCODE
        } finally { $ErrorActionPreference = $previous }
        return [pscustomobject]@{ Code = $code; Output = ($output -join "`n") }
    }
    $alreadyApplied = (Invoke-PatchGit -Arguments @('--reverse', '--check', $Patch)).Code -eq 0
    $sameReceipt = (Test-Path -LiteralPath $Receipt) -and
        ((Get-FileHash -LiteralPath $Receipt).Hash -eq (Get-FileHash -LiteralPath $Patch).Hash)
    if ($alreadyApplied -and $sameReceipt) { return }
    if (-not $alreadyApplied) {
        $reverted = $false
        if (Test-Path -LiteralPath $Receipt) {
            if ((Invoke-PatchGit -Arguments @('--reverse', '--check', $Receipt)).Code -ne 0) {
                throw 'The installed Flutter patch does not match its receipt; refusing to overwrite SDK changes.'
            }
            $result = Invoke-PatchGit -Arguments @('--reverse', $Receipt)
            if ($result.Code -ne 0) { throw "Cannot revert previous Flutter patch: $($result.Output)" }
            $reverted = $true
        }
        try {
            $result = Invoke-PatchGit -Arguments @('--check', $Patch)
            if ($result.Code -ne 0) { throw "Flutter patch check failed: $($result.Output)" }
            $result = Invoke-PatchGit -Arguments @($Patch)
            if ($result.Code -ne 0) { throw "Flutter patch application failed: $($result.Output)" }
        } catch {
            $failure = $_
            if ($reverted) {
                $rollback = Invoke-PatchGit -Arguments @($Receipt)
                if ($rollback.Code -ne 0) { throw "Flutter patch rollback failed: $($rollback.Output)" }
            }
            throw $failure
        }
    }
    # Flutter keys this snapshot on the SDK revision, which does not change for a local patch.
    # Invalidate it now; the next authorized Flutter invocation will rebuild it.
    foreach ($name in @('flutter_tools.snapshot', 'flutter_tools.stamp')) {
        $cached = Join-Path $Sdk "bin/cache/$name"
        if (Test-Path -LiteralPath $cached -PathType Leaf) { Remove-Item -LiteralPath $cached }
    }
    Copy-Item -LiteralPath $Patch -Destination $Receipt -Force
}
