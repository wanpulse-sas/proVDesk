#Requires -Version 5.1
# Exercise package extraction, integrity and reuse without network or installed C++ tools.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../utils/VisualStudio.ps1')
. (Join-Path $PSScriptRoot '../utils/MsvcIntegration.ps1')
$repository = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixture = Join-Path $repository ('work/msbuild-restore-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $fixture | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = Join-Path $fixture 'package.zip'
$zip = [IO.Compression.ZipFile]::Open($archive, 'Create')
try {
    foreach ($name in @('Microsoft.Cpp.Default.props', 'Microsoft.Cpp.props', 'Microsoft.Cpp.targets',
            'Microsoft.CppBuild.targets', 'Platforms/x64/PlatformToolsets/v143/Toolset.props',
            'Platforms/x64/PlatformToolsets/v143/Toolset.targets')) {
        $entry = $zip.CreateEntry("Contents/Msbuild/Microsoft/VC/v170/$name")
        $writer = New-Object IO.StreamWriter($entry.Open())
        try { $writer.Write('<Project />') } finally { $writer.Dispose() }
    }
    $null = $zip.CreateEntry('Contents/MSBuild/Current/Bin/unwanted.exe')
} finally { $zip.Dispose() }
$lockFile = Join-Path $fixture 'lock.json'
$lock = @{schema=1; packages=@(@{id='fixture'; version='1'; url='https://download.visualstudio.microsoft.com/fixture'; sha256=(Get-FileHash $archive -Algorithm SHA256).Hash})}
$lock | ConvertTo-Json -Depth 4 | Set-Content $lockFile -Encoding UTF8
$script:downloads = 0
$script:sourceArchive = $archive
function Invoke-WebRequest([switch]$UseBasicParsing, [string]$Uri, [string]$OutFile) {
    $script:downloads++
    Copy-Item -LiteralPath $script:sourceArchive -Destination $OutFile
}
$private = Get-PrivateMsvcIntegration $fixture $lockFile -Prepare
$targets = Get-MsvcTargetsPath $private 'v143'
if (-not $targets.EndsWith('/v170/')) { throw 'Private integration was not selected.' }
if (Test-Path "$private/MSBuild/Current") { throw 'Unrelated package contents were extracted.' }
if ((Get-PrivateMsvcIntegration $fixture $lockFile) -ne $private -or $script:downloads -ne 1) { throw 'Private integration was not reused.' }
Add-Content "$targets/Microsoft.Cpp.props" 'changed'
$rejected = $false
try { $null = Get-PrivateMsvcIntegration $fixture $lockFile } catch { $rejected = $true }
if (-not $rejected) { throw 'Modified integration was accepted.' }
$lock.packages[0].sha256 = '0' * 64
$lock | ConvertTo-Json -Depth 4 | Set-Content $lockFile -Encoding UTF8
$rejected = $false
try { $null = Get-PrivateMsvcIntegration $fixture $lockFile -Prepare } catch { $rejected = $true }
if (-not $rejected) { throw 'Invalid package SHA256 was accepted.' }
Write-Host 'MSBuild package extraction, reuse and integrity rejection tests passed.'
