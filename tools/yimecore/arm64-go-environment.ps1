# ARM product build scope only. No persistent Go configuration is read or written.
function Invoke-Arm64ProductGoEnvironment {
    [CmdletBinding()]
    param([Parameter(Mandatory)][scriptblock]$Action)
    $isolatedGo = [ordered]@{GOENV='off';GOFLAGS='';GOWORK='off';GOTOOLCHAIN='local'}
    $previousGo = @{}
    foreach ($name in $isolatedGo.Keys) {
        $previousGo[$name] = [Environment]::GetEnvironmentVariable($name,'Process')
    }
    try {
        foreach ($name in $isolatedGo.Keys) {
            [Environment]::SetEnvironmentVariable($name,$isolatedGo[$name],'Process')
        }
        & $Action
    } finally {
        foreach ($name in $isolatedGo.Keys) {
            if ($null -eq $previousGo[$name]) {
                [Environment]::SetEnvironmentVariable($name,[NullString]::Value,'Process')
            } else {
                [Environment]::SetEnvironmentVariable($name,$previousGo[$name],'Process')
            }
        }
    }
}
