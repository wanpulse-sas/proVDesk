#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repository = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixture = Join-Path $repository ('work/env-probe-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path "$fixture/bin" | Out-Null
[IO.File]::WriteAllBytes("$fixture/bin/cl.exe", [byte[]]@())
$selection = "$fixture/selection.json"
[pscustomobject]@{ V143Version = '14.44.35207'; Compiler = "$fixture\bin\cl.exe" } |
    ConvertTo-Json | Set-Content -LiteralPath $selection -Encoding UTF8
$savedPath = $env:PATH
$savedVersion = $env:VCToolsVersion
try {
    $env:PATH = "$fixture/bin;$env:PATH"
    foreach ($version in @('14.44.35207', '14.51.36231')) {
        $env:VCToolsVersion = $version
        $preference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $null = & "$PSHOME/powershell.exe" -NoProfile -File "$repository/ci/probes/Test-VcpkgEnvironment.ps1" -SelectionFile $selection 2>&1
            $code = $LASTEXITCODE
        } finally { $ErrorActionPreference = $preference }
        if (($code -eq 0) -ne ($version -eq '14.44.35207')) { throw 'Environment probe accepted the wrong toolset.' }
    }
} finally {
    $env:PATH = $savedPath
    $env:VCToolsVersion = $savedVersion
}
Write-Host 'Actual vcpkg environment probe version guard passed with synthetic environment.'
