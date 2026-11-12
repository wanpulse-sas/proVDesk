#Requires -Version 5.1
# Opt-in SMB integration test. Uses real UNC I/O and an isolated directory; never run against product output.
param(
    [Parameter(Mandatory = $true)][string]$TestShareRoot,
    [pscredential]$TestCredential = [pscredential]::Empty,
    [string]$BaselineHelperPath = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) {
    throw 'Run this integration test using Windows PowerShell 5.1.'
}
if ($TestShareRoot -notmatch '^\\\\[^\\]+\\[^\\]+') { throw 'A real UNC test root is required.' }
$testRoot = [IO.Path]::GetFullPath($TestShareRoot).TrimEnd('\')
$fixture = $testRoot + '\provdesk-unc-test-' + [guid]::NewGuid().ToString('N')
$resolved = [IO.Path]::GetFullPath($fixture)
if (-not $resolved.StartsWith($testRoot + '\provdesk-unc-test-', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The temporary test directory is outside the requested UNC root.'
}
# This connection also allows creating the isolated test directory with explicit credentials.
$testDrive = 'ProVDeskUncTest' + [guid]::NewGuid().ToString('N')
$originalDrives = @((Get-PSDrive -PSProvider FileSystem).Name)
$created = $false
$mounted = $false
try {
    New-PSDrive -Name $testDrive -PSProvider FileSystem -Root $testRoot -Credential $TestCredential -ErrorAction Stop | Out-Null
    $mounted = $true
    New-Item -ItemType Directory -Path $fixture -ErrorAction Stop | Out-Null
    $created = $true
    Write-Host "PowerShell $($PSVersionTable.PSVersion); real SMB fixture: $fixture"
    if ($BaselineHelperPath) {
        . $BaselineHelperPath
        function Get-PublicationShareRoot { return $fixture }
        function Get-PublicationCredential { return $TestCredential }
        $failure = ''
        try { Assert-PublicationAccess } catch { $failure = $_.Exception.Message }
        if (-not $failure.Contains('[write]')) { throw 'The old helper did not reproduce the expected UNC write failure.' }
        Write-Host "Baseline failure reproduced: $failure"
    }
    . (Join-Path $PSScriptRoot '../utils/Publication.ps1')
    # Only test configuration and cryptographic policy are substituted, never filesystem/SMB commands.
    function Get-PublicationShareRoot { return $fixture }
    function Get-PublicationCredential { return $TestCredential }
    Assert-PublicationAccess
    $directory = "$fixture\WanPulse\ProVDesk"
    if (@(Get-ChildItem -LiteralPath $directory -Force).Count -ne 0) { throw 'Preflight left temporary files.' }
    $inputDirectory = New-Item -ItemType Directory -Path "$fixture\input"
    $exe = Join-Path $inputDirectory.FullName 'ProVDesk.exe'
    Set-Content -LiteralPath $exe -Value 'test executable bytes; not a release' -Encoding ASCII -NoNewline
    $hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
    function Assert-Signature([string]$FilePath) { if ($FilePath -ne $exe) { throw 'Unexpected test executable.' } }
    function Get-InstallerVersion([string]$FilePath) { return '1.5.0' }
    $published = "$directory\ProVDesk-1.5.0.exe"
    foreach ($attempt in 1..2) {
        Publish-SignedInstaller $exe $hash $TestCredential '1.5.0'
        if ((Get-FileHash -LiteralPath $published -Algorithm SHA256).Hash -ne $hash) { throw 'UNC publication changed file bytes.' }
        if (@(Get-ChildItem -LiteralPath $directory -Force).Count -ne 1) { throw 'Unexpected files after UNC publication.' }
    }
    Assert-PublicationAccess
    if ((Get-FileHash -LiteralPath $published -Algorithm SHA256).Hash -ne $hash) { throw 'Preflight changed an existing executable.' }
    if (@(Get-ChildItem -LiteralPath $directory -Force).Count -ne 1) { throw 'Preflight leaked temporary files.' }
    Write-Host 'Real UNC preflight, write/read/hash, publication/replacement and existing-file preservation passed.'
} finally {
    try {
        if ($created) {
            # Delete only the unique test subtree whose absolute UNC boundary was checked above.
            if ([IO.Path]::GetFullPath($fixture) -ne $resolved) { throw 'Test cleanup boundary changed.' }
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction Stop
        }
    } finally {
        if ($mounted) { Remove-PSDrive -Name $testDrive -Force -ErrorAction Stop }
    }
}
$remaining = @((Get-PSDrive -PSProvider FileSystem).Name | Where-Object { $_ -notin $originalDrives })
if ($remaining.Count) { throw "UNC test leaked PowerShell drives: $($remaining -join ', ')" }
if (Test-Path -LiteralPath $fixture) { throw 'UNC test directory was not removed.' }
Write-Host 'UNC fixture and all temporary drives cleaned up; production share was not contacted.'
