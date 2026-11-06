param(
		[Parameter(Mandatory = $false)]
		[string]$AppName = 'ProVDesk',

		[Parameter(Mandatory = $false)]
		[string]$EditorName = 'WanPulse',

		[Parameter(Mandatory = $false)]
		[string]$OutputDir = 'artifacts\ProVDesk',

		[Parameter(Mandatory = $false)]
		[switch]$SkipPortablePack
)

$ErrorActionPreference = 'Stop'

if ($AppName -notmatch '^[a-zA-Z0-9-]+$') {
		throw 'AppName must contain only ASCII letters, digits, or hyphens.'
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Push-Location $repoRoot

$exeName = "$AppName.exe"
$internalName = [System.IO.Path]::GetFileNameWithoutExtension($exeName)
$runnerRcTarget = Join-Path $repoRoot 'flutter\windows\runner\Runner.rc'
$runnerRcBackup = "$runnerRcTarget.bak.appname"
$originalAppNameEnv = [Environment]::GetEnvironmentVariable('RUSTDESK_APP_NAME', 'Process')
$originalEditorNameEnv = [Environment]::GetEnvironmentVariable('RUSTDESK_EDITOR_NAME', 'Process')
$originalForceWebSocketEnv = [Environment]::GetEnvironmentVariable('RUSTDESK_FORCE_WEBSOCKET', 'Process')

function Restore-FileIfBackedUp {
		param(
				[string]$BackupPath,
				[string]$TargetPath
		)
		if (Test-Path $BackupPath) {
				Copy-Item -Path $BackupPath -Destination $TargetPath -Force
				Remove-Item -Path $BackupPath -Force
		}
}

try {
        $patchPath = Join-Path $PSScriptRoot 'provdesk-hbb-common.patch'
        git -C libs/hbb_common apply --reverse --check $patchPath 2>$null
        if ($LASTEXITCODE -ne 0) {
                git -C libs/hbb_common apply --check $patchPath
                if ($LASTEXITCODE -ne 0) { throw 'The hbb_common customization patch cannot be applied.' }
                git -C libs/hbb_common apply $patchPath
                if ($LASTEXITCODE -ne 0) { throw 'Applying the hbb_common customization failed.' }
        }
        if (-not [string]::IsNullOrWhiteSpace($AppName)) {
				# Backup Runner.rc
				Copy-Item -Path $runnerRcTarget -Destination $runnerRcBackup -Force

				# Read and replace CompanyName/FileDescription/InternalName/OriginalFilename/ProductName
				$runnerRcContent = Get-Content -Path $runnerRcTarget -Raw
				$runnerRcContent = $runnerRcContent -replace 'VALUE "CompanyName", "[^"]*" "\\{1,2}0"', ('VALUE "CompanyName", "{0}" "\0"' -f $EditorName)
				$runnerRcContent = $runnerRcContent -replace 'VALUE "FileDescription", ".*" "\\{1,2}0"', ('VALUE "FileDescription", "{0} Remote Desktop" "\0"' -f $AppName)
				$runnerRcContent = $runnerRcContent -replace 'VALUE "InternalName", ".*" "\\{1,2}0"', ('VALUE "InternalName", "{0}" "\0"' -f $internalName)
				$runnerRcContent = $runnerRcContent -replace 'VALUE "OriginalFilename", ".*" "\\{1,2}0"', ('VALUE "OriginalFilename", "{0}" "\0"' -f $exeName)
				$runnerRcContent = $runnerRcContent -replace 'VALUE "ProductName", ".*" "\\{1,2}0"', ('VALUE "ProductName", "{0}" "\0"' -f $AppName)

				Set-Content -Path $runnerRcTarget -Value $runnerRcContent -NoNewline

				# Export env var used by runtime/build
				$env:RUSTDESK_APP_NAME = $AppName
				$env:RUSTDESK_EDITOR_NAME = $EditorName
				$env:RUSTDESK_FORCE_WEBSOCKET = 'Y'
		}

		# Ensure a clean flutter build so the RC changes are embedded
		Push-Location .\flutter
		try {
				flutter clean
				if ($LASTEXITCODE -ne 0) { throw "flutter clean failed with exit code $LASTEXITCODE" }
		} finally {
				Pop-Location
		}

        Push-Location flutter
        try {
                flutter pub get
                if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency resolution failed.' }
        } finally { Pop-Location }
        $originalRustLog = [Environment]::GetEnvironmentVariable('RUST_LOG', 'Process')
        try {
                $env:RUST_LOG = 'info'
                flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./flutter/lib/generated_bridge.dart
                if ($LASTEXITCODE -ne 0) { throw 'Flutter bridge generation failed.' }
        } finally { [Environment]::SetEnvironmentVariable('RUST_LOG', $originalRustLog, 'Process') }
		# Build core and flutter
		$features = python .\build.py --flutter --print-features
		if ($LASTEXITCODE -ne 0) { throw "build.py --print-features failed with exit code $LASTEXITCODE" }
		if ([string]::IsNullOrWhiteSpace($features)) { throw 'Failed to get features from build.py' }

		cargo build --locked --features "$features" --lib --release
		if ($LASTEXITCODE -ne 0) { throw "cargo build failed with exit code $LASTEXITCODE" }
        cargo build --locked --release --manifest-path libs/virtual_display/dylib/Cargo.toml
        if ($LASTEXITCODE -ne 0) { throw 'Virtual display build failed.' }
        Push-Location flutter
        try {
                flutter build windows --release
                if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows build failed.' }
        } finally { Pop-Location }
        $releaseDir = Join-Path $repoRoot 'flutter\build\windows\x64\runner\Release'
        Copy-Item target/release/deps/dylib_virtual_display.dll $releaseDir -Force
        if ($exeName -ne 'rustdesk.exe') {
                Move-Item -LiteralPath (Join-Path $releaseDir 'rustdesk.exe') -Destination (Join-Path $releaseDir $exeName) -Force
        }
        Copy-Item LICENCE,PROVDESK.md $releaseDir -Force
        if (-not $SkipPortablePack) {
                python -m pip install -r libs/portable/requirements.txt
                if ($LASTEXITCODE -ne 0) { throw 'Portable packer dependencies failed.' }
                Push-Location libs/portable
                try {
                        python generate.py -f $releaseDir -o . -e "$releaseDir/$exeName"
                        if ($LASTEXITCODE -ne 0) { throw 'Portable packaging failed.' }
                } finally { Pop-Location }
        }
        $releaseExe = if ($SkipPortablePack) { Join-Path $releaseDir $exeName } else { Join-Path $repoRoot 'target/release/rustdesk-portable-packer.exe' }
        if (-not (Test-Path $releaseExe)) { throw "Built exe not found: $releaseExe" }

		$variantOutputDir = Join-Path $repoRoot $OutputDir
		New-Item -ItemType Directory -Force -Path $variantOutputDir | Out-Null

        if ($SkipPortablePack) {
                Copy-Item "$releaseDir/*" $variantOutputDir -Recurse -Force
        }
        Copy-Item LICENCE,PROVDESK.md $variantOutputDir -Force
        $destExe = Join-Path $variantOutputDir $exeName
		Copy-Item -Path $releaseExe -Destination $destExe -Force

		Write-Host "Custom AppName build finished: $destExe"
		Write-Host "Runtime AppName set via RUSTDESK_APP_NAME; service/logs will use this name at runtime."
}
finally {
		# restore Runner.rc
		if (Test-Path $runnerRcBackup) { Restore-FileIfBackedUp -BackupPath $runnerRcBackup -TargetPath $runnerRcTarget }
		[Environment]::SetEnvironmentVariable('RUSTDESK_APP_NAME', $originalAppNameEnv, 'Process')
		[Environment]::SetEnvironmentVariable('RUSTDESK_EDITOR_NAME', $originalEditorNameEnv, 'Process')
		[Environment]::SetEnvironmentVariable('RUSTDESK_FORCE_WEBSOCKET', $originalForceWebSocketEnv, 'Process')
		Pop-Location
}
