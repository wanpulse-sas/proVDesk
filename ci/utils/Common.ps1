# Shared paths, Authenticode validation and WanPulse signing.
# Uses the WanPulse signing framework command-line interface.
$script:root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:work = Join-Path $root 'signing-work'
$script:payload = Join-Path $root 'source/artifacts/ci-payload'
Set-Location $root
. (Join-Path $PSScriptRoot 'VisualStudio.ps1')
. (Join-Path $PSScriptRoot 'BuildResources.ps1')
$script:verifiedCatalogMembers = @()

function Assert-NativeSuccess([string]$Operation) {
    if ($LASTEXITCODE -ne 0) { throw "$Operation (code $LASTEXITCODE)" }
}
function Assert-Signature([string]$FilePath, [switch]$ThirdParty) {
    # Require timestamps for WanPulse signatures; preserve valid third-party signatures unchanged.
    $verifyArgs = @('verify', '/pa', '/all', '/v')
    if (-not $ThirdParty) { $verifyArgs += '/tw' }
    & $env:SIGNTOOL_VERIFY_PATH @verifyArgs $FilePath | Out-Host
    Assert-NativeSuccess "Verification Authenticode : $FilePath"
    $signature = Get-AuthenticodeSignature -LiteralPath $FilePath
    if ($signature.Status -ne 'Valid' -or
        $null -eq $signature.SignerCertificate -or
        (-not $ThirdParty -and ($signature.SignerCertificate.Thumbprint -ne $script:expectedThumbprint -or
        $null -eq $signature.TimeStamperCertificate))) {
        throw "Signature, signataire ou horodatage incorrect : $FilePath"
    }
}
function Invoke-WanPulseSign([string]$FilePath) {
    # Call the WanPulse signing framework.
    # Do not log the command or raw framework output:
    # they may contain the signing password passed as an argument.
    $arguments = @(
        "/container:$env:SIGNING_CONTAINER"
        "/password:$env:SIGNING_PASSWORD"
        "/thumbprint:$script:expectedThumbprint"
        "/filepath:$FilePath"
        "/timestamp:$script:timestampUrl"
    )
    Write-Host "Signature : $FilePath"
    try {
        $previousPreference = $ErrorActionPreference
        try {
            # Windows PowerShell 5.1 wraps native stderr as error records.
            # Discard all output, but decide success from the exit code and Authenticode.
            $ErrorActionPreference = 'Continue'
            $global:LASTEXITCODE = $null
            $null = & $env:WP_SIGNTOOL_PATH @arguments 2>&1
            $signExitCode = $global:LASTEXITCODE
        } finally { $ErrorActionPreference = $previousPreference }
    } catch {
        throw "Echec d'appel du WP SignTool : $FilePath (sortie masquee)."
    }
    if ($null -eq $signExitCode -or $signExitCode -ne 0) {
        throw "Echec du WP SignTool : $FilePath (code $signExitCode)."
    }
    Assert-Signature $FilePath
}
function Get-PayloadManifest {
    @(Get-ChildItem -LiteralPath $script:payload -File -Recurse -Force |
        Sort-Object FullName | ForEach-Object {
            [pscustomobject]@{
                Path = $_.FullName.Substring($script:payload.Length + 1).Replace('\', '/')
                SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                Length = $_.Length
            }
        })
}

function Initialize-Signing {
    # This dedicated pipeline always signs, regardless of inherited workspace flags.
    $env:SKIP_SIGNATURE = 'false'
    foreach ($name in @('SIGNING_CONTAINER', 'SIGNING_PASSWORD', 'SIGNING_THUMBPRINT')) {
        if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
            throw "Variable requise manquante : $name"
        }
    }
    if ([string]::IsNullOrWhiteSpace($env:SIGNTOOL_VERIFY_PATH)) {
        $sdkBin = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin'
        $candidates = @(Get-ChildItem -LiteralPath $sdkBin -Directory -ErrorAction SilentlyContinue |
            Where-Object Name -Match '^10\.\d+\.\d+\.\d+$' |
            Sort-Object { [version]$_.Name } -Descending |
            ForEach-Object { Join-Path $_.FullName 'x64/signtool.exe' } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
        if ($candidates.Count -eq 0) { throw 'SignTool de verification introuvable : installer les outils de signature du SDK Windows.' }
        $env:SIGNTOOL_VERIFY_PATH = $candidates[0]
    }
    foreach ($name in @('WP_SIGNTOOL_PATH', 'SIGNTOOL_VERIFY_PATH')) {
        $toolPath = [Environment]::GetEnvironmentVariable($name)
        if ([string]::IsNullOrWhiteSpace($toolPath) -or
            -not [IO.Path]::IsPathRooted($toolPath) -or
            -not (Test-Path -LiteralPath $toolPath -PathType Leaf)) {
            throw "Chemin absolu d'outil requis : $name"
        }
    }
    $script:expectedThumbprint = ($env:SIGNING_THUMBPRINT -replace '\s', '').ToUpperInvariant()
    if ($script:expectedThumbprint -notmatch '^[A-F0-9]{40}$') { throw 'Empreinte de certificat incorrecte.' }
    $script:timestampUrl = 'http://timestamp.digicert.com'
    if ($env:SIGNING_TIMESTAMP_URL) { $script:timestampUrl = $env:SIGNING_TIMESTAMP_URL }
    $timestampUri = [Uri]$script:timestampUrl
    if (-not $timestampUri.IsAbsoluteUri -or $timestampUri.Scheme -notin @('http', 'https')) {
        throw 'URL de service d horodatage incorrecte.'
    }
}

function Get-PayloadBinaries {
    @(Get-ChildItem -LiteralPath $script:payload -File -Recurse -Force |
        Where-Object { $_.Extension -in '.exe', '.dll' } | Sort-Object FullName)
}

function Assert-PayloadMatchesManifest([string]$ManifestPath) {
    $expected = @((Get-Content -Encoding UTF8 -LiteralPath $ManifestPath -Raw | ConvertFrom-Json))
    $actual = @(Get-PayloadManifest)
    if ($expected.Count -eq 0 -or $actual.Count -eq 0 -or
        (Compare-Object $expected $actual -Property Path,SHA256,Length)) {
        throw "Le payload ne correspond plus au manifeste : $ManifestPath"
    }
}

function Get-SigningAction([string]$RelativePath, [string]$Status, [string]$Thumbprint) {
    if ($RelativePath -match '^(usbmmidd_v2/|drivers/RustDeskPrinterDriver/)') {
        if ($RelativePath -notin $script:verifiedCatalogMembers) { throw "Unverified driver binary: $RelativePath" }
        return 'DriverCatalog'
    }
    $ownBinary = $RelativePath -in @('ProVDesk.exe', 'librustdesk.dll', 'dylib_virtual_display.dll')
    if ($Status -eq 'NotSigned') { return 'WanPulse' }
    if ($Status -ne 'Valid') { throw "Signature existante invalide : $RelativePath ($Status)" }
    if ($Thumbprint -eq $script:expectedThumbprint) { return 'WanPulseExisting' }
    if ($ownBinary) { throw "Signataire tiers inattendu sur un binaire ProVDesk : $RelativePath" }
    return 'ThirdParty'
}

function Assert-DriverCatalogs {
    $script:verifiedCatalogMembers = @()
    $verified = @()
    $packages = @(
        @{ Root = 'usbmmidd_v2'; Catalog = 'usbmmidd.cat'; Members = @('usbmmIdd.inf', 'x64/usbmmIdd.dll') },
        @{ Root = 'drivers/RustDeskPrinterDriver'; Catalog = 'rustdeskprinterdriver.cat'; Members = @(
            'RustDeskPrinterDriver.inf', 'RustDeskPrinterDriver.gpd', 'RustDeskPrinterDriver-manifest.ini',
            'RustDeskPrinterDriverRenderFilter-PipelineConfig.xml', 'RustDeskPrinterDriverRenderFilter.dll') }
    )
    foreach ($package in $packages) {
        $directory = Join-Path $payload $package.Root
        $catalog = Join-Path $directory $package.Catalog
        $allowed = @($package.Catalog) + $package.Members
        if ($package.Root -eq 'usbmmidd_v2') { $allowed += @('License.txt', 'idd_instructions.txt') }
        foreach ($file in Get-ChildItem -LiteralPath $directory -File -Recurse -Force) {
            $relative = $file.FullName.Substring($directory.Length + 1).Replace('\', '/')
            if ($relative -notin $allowed) { throw "Unexpected driver package file: $relative" }
        }
        Assert-Signature $catalog -ThirdParty
        foreach ($member in $package.Members) {
            & $env:SIGNTOOL_VERIFY_PATH verify /kp /v /c $catalog (Join-Path $directory $member) | Out-Host
            Assert-NativeSuccess "Catalogue pilote : $member"
            $verified += "$($package.Root)/$member"
        }
    }
    $script:verifiedCatalogMembers = $verified
}

function Assert-SignedPayload {
    Assert-PayloadMatchesManifest "$work/payload-signed.json"
    Assert-DriverCatalogs
    $report = @((Get-Content -Encoding UTF8 "$work/signatures.json" -Raw | ConvertFrom-Json))
    $binaries = @(Get-PayloadBinaries)
    if ($report.Count -ne $binaries.Count) { throw 'Inventaire de signatures incomplet.' }
    foreach ($entry in $report) {
        $filePath = Join-Path $payload $entry.Path
        switch ($entry.Action) {
            'WanPulse' { Assert-Signature $filePath }
            'WanPulseExisting' { Assert-Signature $filePath }
            'ThirdParty' { Assert-Signature $filePath -ThirdParty }
            'DriverCatalog' { if ($entry.Path -notin $script:verifiedCatalogMembers) { throw 'Driver catalog membership not verified.' } }
            default { throw "Politique de signature inconnue : $($entry.Action)" }
        }
        if ($entry.Action -in @('ThirdParty', 'DriverCatalog', 'WanPulseExisting') -and
            (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash -ne $entry.OriginalSHA256) {
            throw "Composant signe preexistant modifie : $($entry.Path)"
        }
    }
}

function Use-BuildTools([switch]$SkipVisualStudio) {
    if (-not $SkipVisualStudio) { $script:visualStudio = Enable-Vs2026Environment }
    $env:RUSTUP_TOOLCHAIN = (Get-Content -LiteralPath "$root/ci/rust-tools.json" -Raw -Encoding UTF8 | ConvertFrom-Json).toolchain
    $env:VCPKG_ROOT = Join-Path $root 'build-tools/vcpkg'
    $env:VCPKG_DEFAULT_TRIPLET = 'x64-windows-static'
    $env:VCPKG_DEFAULT_HOST_TRIPLET = 'x64-windows-static'
    Remove-Item Env:VCPKG_INSTALLED_ROOT -ErrorAction SilentlyContinue
    $env:PATH = "$root/build-tools/python/Scripts;$root/build-tools/flutter/bin;$root/build-tools/rust/bin;$env:PATH"
    foreach ($name in @('MSBUILD_PATH', 'LIBCLANG_PATH')) {
        if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) { throw "Variable requise : $name" }
    }
    if (-not (Test-Path -LiteralPath $env:MSBUILD_PATH -PathType Leaf)) { throw 'MSBUILD_PATH introuvable.' }
    if (-not (Test-Path -LiteralPath (Join-Path $env:LIBCLANG_PATH 'libclang.dll'))) { throw 'libclang.dll introuvable.' }
}

function Get-LockedAsset([string]$Name) {
    Assert-FreeDiskSpace "Download/extract $Name"
    $lock = Get-Content -Encoding UTF8 "$root/ci/dependencies.json" -Raw | ConvertFrom-Json
    $asset = @($lock.assets | Where-Object name -eq $Name)
    if ($asset.Count -ne 1) { throw "Archive inconnue : $Name" }
    $downloadDir = Join-Path $root 'build-tools/downloads'
    New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
    $zip = Join-Path $downloadDir "$Name.zip"
    if (-not (Test-Path -LiteralPath $zip)) { Invoke-WebRequest -UseBasicParsing -Uri $asset[0].url -OutFile $zip }
    if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $asset[0].sha256) { throw "SHA256 incorrect : $Name" }
    $destination = Join-Path $downloadDir $Name
    if (Test-Path -LiteralPath $destination) { throw "Archive deja extraite : $Name" }
    Expand-Archive -LiteralPath $zip -DestinationPath $destination
    return $destination
}
