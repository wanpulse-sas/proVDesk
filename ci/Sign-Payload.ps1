#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'utils/Common.ps1')
Assert-FreeDiskSpace 'Sign-Payload'
Initialize-Signing
Assert-PayloadMatchesManifest "$work/payload-unsigned.json"
Assert-DriverCatalogs
$beforeSigning = @(Get-PayloadManifest)
$binaries = @(Get-PayloadBinaries)
$signatureReport = @(
    foreach ($file in $binaries) {
        $relative = $file.FullName.Substring($payload.Length + 1).Replace('\', '/')
        $originalHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
        $thumbprint = if ($signature.SignerCertificate) { $signature.SignerCertificate.Thumbprint } else { '' }
        $action = Get-SigningAction $relative ([string]$signature.Status) $thumbprint
        switch ($action) {
            'WanPulse' { Invoke-WanPulseSign $file.FullName }
            'WanPulseExisting' { Assert-Signature $file.FullName }
            'ThirdParty' { Assert-Signature $file.FullName -ThirdParty }
            'DriverCatalog' { } # Never modify files covered by a driver catalog.
        }
        if ($action -ne 'WanPulse' -and (Get-FileHash $file.FullName -Algorithm SHA256).Hash -ne $originalHash) {
            throw "Signature tierce modifiee : $relative"
        }
        $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
        [pscustomobject]@{
            Path = $relative
            Action = $action
            OriginalSHA256 = $originalHash
            Signer = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { 'Catalog' }
            Thumbprint = if ($signature.SignerCertificate) { $signature.SignerCertificate.Thumbprint } else { '' }
        }
    }
)
$signed = @(Get-PayloadManifest)
if (Compare-Object @($beforeSigning.Path) @($signed.Path)) { throw 'Liste du payload modifiee.' }
$changedPaths = @($signatureReport | Where-Object Action -eq 'WanPulse' | ForEach-Object Path)
$preservedBefore = @($beforeSigning | Where-Object Path -notin $changedPaths)
$preservedAfter = @($signed | Where-Object Path -notin $changedPaths)
if ($preservedBefore.Count -gt 0 -and
    (Compare-Object $preservedBefore $preservedAfter -Property Path,SHA256,Length)) { throw 'Fichier a conserver modifie.' }
ConvertTo-Json -InputObject $signatureReport -Depth 4 | Set-Content "$work/signatures.json" -Encoding UTF8
ConvertTo-Json -InputObject $signed -Depth 4 | Set-Content "$work/payload-signed.json" -Encoding UTF8
Assert-SignedPayload
