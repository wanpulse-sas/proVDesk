#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'utils/Common.ps1')
. (Join-Path $PSScriptRoot 'utils/Publication.ps1')
Assert-FreeDiskSpace 'Sign-Installer'

# Sign the wrapper, then produce distribution artifacts and hashes.
Initialize-Signing
Use-BuildTools
Assert-SignedPayload
$binaries = @(Get-PayloadBinaries)
$sourceCommit = (Get-Content -Encoding UTF8 "$work/source-commit.txt" -Raw).Trim()
$finalExe = Join-Path $work 'ProVDesk.exe'

Invoke-WanPulseSign $finalExe
python "$root/ci/Verify-Package.py" "$root/source/libs/portable/data.bin" "$work/payload-signed.json" $finalExe
Assert-NativeSuccess 'Verification du contenu apres signature finale'
# Compute the distribution hash AFTER final signing.
$finalHash = (Get-FileHash -LiteralPath $finalExe -Algorithm SHA256).Hash
Set-Content "$work/ProVDesk.exe.sha256" "$finalHash  ProVDesk.exe" -Encoding ASCII
$finalSignature = Get-AuthenticodeSignature -LiteralPath $finalExe
[pscustomobject]@{
    Version = Get-InstallerVersion $finalExe
    SourceCommit = $sourceCommit
    PipelineCommit = $env:BITBUCKET_COMMIT
    BuildNumber = $env:BITBUCKET_BUILD_NUMBER
    PayloadBinaryCount = $binaries.Count
    FinalSHA256 = $finalHash
    Signer = $finalSignature.SignerCertificate.Subject
    Thumbprint = $finalSignature.SignerCertificate.Thumbprint
    TimestampSigner = $finalSignature.TimeStamperCertificate.Subject
} | ConvertTo-Json | Set-Content "$work/build.json" -Encoding UTF8
# Archive the entire directory, including hidden files.
Add-Type -AssemblyName System.IO.Compression.FileSystem
Assert-FreeDiskSpace 'Archive signed payload'
[IO.Compression.ZipFile]::CreateFromDirectory($payload, "$work/payload-signed.zip")
$zipHash = (Get-FileHash "$work/payload-signed.zip" -Algorithm SHA256).Hash
Set-Content "$work/payload-signed.zip.sha256" "$zipHash  payload-signed.zip" -Encoding ASCII
Set-Location $root
# Expose output artifacts only after all checks have passed.
Move-Item -LiteralPath $work -Destination (Join-Path $root 'out')
Write-Host "ProVDesk signe : $($binaries.Count) EXE/DLL internes + EXE final. Tests VM requis avant diffusion."
