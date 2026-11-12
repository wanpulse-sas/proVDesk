# Export selected text diagnostics only; never export signing framework output.
function Export-BuildDiagnostics([string]$Workspace) {
    $destination = Join-Path $Workspace 'diagnostics'
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    $secrets = @(Get-ChildItem Env: | Where-Object {
        $_.Name -match '(PASSWORD|SECRET|TOKEN|SIGNING_CONTAINER)' -and $_.Value
    } | ForEach-Object { $_.Value; [Uri]::EscapeDataString($_.Value) } | Sort-Object Length -Descending -Unique)
    $files = @()
    foreach ($relative in @('build-tools/vcpkg/buildtrees', 'flutter/build/windows', 'build-tools/probes')) {
        $directory = Join-Path $Workspace $relative
        if (Test-Path -LiteralPath $directory) {
            $files += @(Get-ChildItem -LiteralPath $directory -Recurse -File -Filter *.log -ErrorAction Stop)
            $files += @(Get-ChildItem -LiteralPath $directory -Recurse -File -Filter CMakeConfigureLog.yaml -ErrorAction Stop)
        }
    }
    foreach ($directory in @('signing-work', 'out')) {
        foreach ($name in @('visual-studio.json', 'vcpkg-packages.txt', 'flutter-doctor.txt',
                'rust-version.txt', 'python-packages.txt', 'source-commit.txt', 'vcpkg-selection.cmake',
                'toolchain-probe.log', 'toolchain-preflight.json', 'msbuild-tools.json', 'msbuild-selection.cmake', 'libvpx-msbuild.patch', 'opus-static-runtime.patch')) {
            $path = Join-Path $Workspace "$directory/$name"
            if (Test-Path -LiteralPath $path) { $files += Get-Item -LiteralPath $path }
        }
    }
    $total = 0L
    $index = @()
    foreach ($file in ($files | Sort-Object FullName -Unique)) {
        $relative = $file.FullName.Substring($Workspace.TrimEnd('\', '/').Length + 1)
        if ($file.Length -gt 5MB -or $total + $file.Length -gt 50MB -or
            ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $index += "Skipped (size limit or reparse point): $relative"
            continue
        }
        $text = [IO.File]::ReadAllText($file.FullName)
        foreach ($secret in $secrets) { $text = $text.Replace($secret, '[REDACTED]') }
        # Also remove URL userinfo that could originate from dependency configuration.
        $text = [regex]::Replace($text, '(?i)(https?://)[^\s/]+@', '$1[REDACTED]@')
        $target = Join-Path $destination $relative
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        [IO.File]::WriteAllText($target, $text, (New-Object Text.UTF8Encoding($false)))
        $total += $file.Length
        $index += "Collected: $relative"
    }
    $index | Set-Content -LiteralPath (Join-Path $destination 'index.txt') -Encoding UTF8
    Write-Host "Diagnostics exported: $($files.Count) candidate files."
}
