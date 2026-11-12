# Restore only MSBuild integration, never compiler binaries or machine installations.
function Get-PrivateMsvcIntegration([string]$Workspace, [string]$LockFile, [switch]$Prepare) {
    $key = (Get-FileHash -LiteralPath $LockFile -Algorithm SHA256).Hash.ToLowerInvariant()
    $destination = Join-Path $Workspace "work/msbuild-integration/$key"
    $receipt = Join-Path $destination 'files.json'
    if (Test-Path -LiteralPath $receipt) {
        $files = @((Get-Content -LiteralPath $receipt -Raw -Encoding UTF8 | ConvertFrom-Json))
        if ($files.Count -eq 0) { throw 'Empty MSBuild integration receipt.' }
        foreach ($file in $files) {
            $path = Join-Path $destination $file.Path
            if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
                (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.SHA256) {
                throw "Private MSBuild integration was modified: $($file.Path)"
            }
        }
        return $destination
    }
    if (-not $Prepare) { throw 'Private v143 MSBuild integration is not prepared. Run Test-Runner first.' }
    if (Test-Path -LiteralPath $destination) { throw 'Incomplete private MSBuild integration; use a clean checkout.' }
    $lock = Get-Content -LiteralPath $LockFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($lock.schema -ne 1) { throw 'Unsupported MSBuild integration lock schema.' }
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    foreach ($package in $lock.packages) {
        if ($package.id -notmatch '^[a-zA-Z0-9.]+$' -or $package.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or
            $package.url -notlike 'https://download.visualstudio.microsoft.com/*') { throw 'Invalid Microsoft package lock.' }
        $archive = Join-Path $destination ($package.id + '.zip')
        Write-Host "Prepare MSBuild integration: $($package.id) $($package.version)"
        Invoke-WebRequest -UseBasicParsing -Uri $package.url -OutFile $archive
        if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $package.sha256) {
            throw "Microsoft package SHA256 mismatch: $($package.id)"
        }
        $zip = [IO.Compression.ZipFile]::OpenRead($archive)
        try {
            foreach ($entry in $zip.Entries) {
                # Keep only the v170 integration tree, not installers, SDK resolvers or metadata.
                if (-not $entry.FullName.StartsWith('Contents/Msbuild/Microsoft/VC/v170/', [StringComparison]::OrdinalIgnoreCase) -or
                    -not $entry.Name) { continue }
                $relative = $entry.FullName.Substring('Contents/'.Length)
                $target = [IO.Path]::GetFullPath((Join-Path $destination $relative))
                if (-not $target.StartsWith([IO.Path]::GetFullPath($destination).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
                    throw 'Unsafe Microsoft package entry.'
                }
                New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $false)
            }
        } finally { $zip.Dispose() }
        Remove-Item -LiteralPath $archive
    }
    $null = Get-MsvcTargetsPath $destination 'v143'
    $files = @(Get-ChildItem -LiteralPath (Join-Path $destination 'MSBuild') -File -Recurse | ForEach-Object {
        [pscustomobject]@{ Path = $_.FullName.Substring($destination.Length + 1); SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    })
    ConvertTo-Json -InputObject $files -Depth 3 | Set-Content -LiteralPath $receipt -Encoding UTF8
    return $destination
}
