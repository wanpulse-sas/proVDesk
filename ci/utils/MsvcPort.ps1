# Write MSBuild options separately so non-MSBuild vcpkg ports keep their existing cache keys.
function Write-MsvcPortSelection([string]$Destination, $Configuration) {
    $values = [ordered]@{
        PROVDESK_VCTARGETS_PATH = $Configuration.V143TargetsPath
        PROVDESK_VS_INSTALL_DIR = $Configuration.InstallationPath.Replace('\', '/').TrimEnd('/') + '/'
        PROVDESK_MSVC_VERSION = $Configuration.V143Version
    }
    $lines = @('# Generated MSBuild selection for the libvpx overlay.')
    foreach ($item in $values.GetEnumerator()) {
        if (-not $item.Value -or $item.Value -match '[\r\n]' -or $item.Value.Contains(']==]')) { throw 'Invalid MSBuild port selection.' }
        $lines += "set($($item.Key) [==[$($item.Value)]==])"
    }
    [IO.File]::WriteAllText($Destination, ($lines -join "`n") + "`n", (New-Object Text.UTF8Encoding($false)))
}
