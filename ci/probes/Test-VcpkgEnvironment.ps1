#Requires -Version 5.1
param([Parameter(Mandatory = $true)][string]$SelectionFile)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$selection = Get-Content -LiteralPath $SelectionFile -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $env:VCToolsVersion -or $env:VCToolsVersion.TrimEnd('\', '/') -ne $selection.V143Version) {
    throw 'vcpkg did not initialize the expected v143 version.'
}
$compiler = (Get-Command cl.exe -ErrorAction Stop).Source
if ([IO.Path]::GetFullPath($compiler) -ne [IO.Path]::GetFullPath($selection.Compiler)) { throw 'vcpkg selected another compiler executable.' }
Write-Host "vcpkg environment verified: $($selection.V143Version), $compiler"
