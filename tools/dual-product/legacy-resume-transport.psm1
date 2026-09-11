function Get-LegacyResumeCommandBound($Parameters,[string]$TempRoot,[string]$WindowsRoot){
    # Original 6321067de NSIS template. Reserve 16 characters for its temp leaf.
    $plugin=Join-Path $TempRoot ('n' * 12 + '.tmp')
    $hostPath=Join-Path $WindowsRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    $p=$Parameters
    $manifest='3f676b80b86f4c752e96c5ed06655bddb3b5b4aedd762ca8369483e7ae14b01d'
    $command='"'+$hostPath+'" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$plugin+'\bundle\maintenance\invoke-rime-pime-candidate.ps1" -Mode "Resume" -PackageRoot "'+$plugin+'\bundle" -ExpectedManifestSha256 "'+$manifest+'" -InstallerPath "'+$p.InstallerPath+'" -AuthorizationPath "'+$p.AuthorizationPath+'" -TrustedApprovalSha256 "'+$p.TrustedApprovalSha256+'" -BoundaryPath "'+$p.BoundaryPath+'" -ReceiptPath "'+$p.ReceiptPath+'" -PreparedSha256 "'+$p.PreparedSha256+'"'
    return $command.Length
}
Export-ModuleMember -Function Get-LegacyResumeCommandBound
