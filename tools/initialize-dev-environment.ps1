$ErrorActionPreference = 'Stop'

function ConvertTo-ProxyUri {
    param([string]$ProxyServer)

    if ([string]::IsNullOrWhiteSpace($ProxyServer)) { return $null }
    $value = $ProxyServer.Trim()
    if ($value.Contains('=')) {
        $entries = @{}
        foreach ($entry in $value.Split(';')) {
            $pair = $entry.Split('=', 2)
            if ($pair.Count -eq 2) { $entries[$pair[0].Trim().ToLowerInvariant()] = $pair[1].Trim() }
        }
        $value = if ($entries.ContainsKey('https')) { $entries['https'] } elseif ($entries.ContainsKey('http')) { $entries['http'] } else { $null }
    }
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    if ($value -notmatch '^[a-z]+://') { $value = "http://$value" }
    return $value
}

$cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
if ((Test-Path -LiteralPath (Join-Path $cargoBin 'rustup.exe')) -and (($env:PATH -split ';') -notcontains $cargoBin)) {
    $env:PATH = "$cargoBin;$env:PATH"
    Write-Host "Using Rust tools from $cargoBin"
}

if (-not $env:HTTPS_PROXY -or -not $env:HTTP_PROXY) {
    try {
        $internetSettings = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        if ([int]$internetSettings.ProxyEnable -eq 1) {
            $proxyUri = ConvertTo-ProxyUri ([string]$internetSettings.ProxyServer)
            if ($proxyUri) {
                if (-not $env:HTTPS_PROXY) { $env:HTTPS_PROXY = $proxyUri }
                if (-not $env:HTTP_PROXY) { $env:HTTP_PROXY = $proxyUri }
                Write-Host "Using enabled WinINET proxy for git/cmake: $proxyUri"
            }
        }
    } catch {
        Write-Verbose "WinINET proxy could not be inspected: $($_.Exception.Message)"
    }
}
