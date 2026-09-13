Set-StrictMode -Version 2.0

function Get-MaintenanceApplicationUse {
    param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][AllowEmptyCollection()][string[]]$RelativePaths)
    if(-not ('Yime.Maintenance.ResourceUse' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'maintenance-application-use.cs')}
    $root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
    $paths=@(foreach($relative in $RelativePaths){
        if([IO.Path]::IsPathRooted($relative) -or $relative -match ':|(^|[\\/])\.\.?([\\/]|$)'){throw 'Unsafe maintenance member.'}
        $path=[IO.Path]::GetFullPath((Join-Path $root $relative))
        if(-not $path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Maintenance member escaped product root.'}
        for($cursor=$path;$cursor;$cursor=[IO.Path]::GetDirectoryName($cursor)){
            $item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Indirect maintenance resource.'}
        }
        $path
    })
    $errors=@(foreach($path in $paths){
        $code=[Yime.Maintenance.ResourceUse]::Probe($path)
        if($code -ne 0){[pscustomobject]@{path=$path;native_error=$code}}
    })
    $applications=@([Yime.Maintenance.ResourceUse]::Applications([string[]]$paths))
    [pscustomobject]@{clear=($errors.Count -eq 0 -and $applications.Count -eq 0);applications=$applications;resources=$errors}
}

function Show-MaintenanceApplicationPrompt {
    param($Snapshot)
    Add-Type -AssemblyName System.Windows.Forms
    $lines=@('请保存工作并正常退出占用应用，然后点击“重新检查”。取消会停止继续操作。','')
    foreach($app in $Snapshot.applications){
        if($app.Type -in @(3,4,1000) -or $app.Pid -le 4){
            $lines+=('{0}（PID {1}）：系统或服务持有者，请勿结束此进程；实际应用尚需释放资源。' -f $app.Name,$app.Pid)
        }else{$lines+=('{0}（PID {1}）' -f $app.Name,$app.Pid)}
    }
    if(-not @($Snapshot.applications).Count){$lines+='尚未识别占用应用。可能是权限或其他错误，请勿盲目关闭应用。'}
    foreach($resource in $Snapshot.resources){$lines+=('{0}：检查返回 {1}' -f [IO.Path]::GetFileName($resource.path),$resource.native_error)}
    $lines+='不会强制关闭应用。系统宿主不能正常退出时，请取消；不要直接重启后重复旧操作。'
    $form=New-Object Windows.Forms.Form
    try{
        $form.Text='输入法维护：等待应用退出';$form.Width=640;$form.Height=400;$form.StartPosition='CenterScreen'
        $text=New-Object Windows.Forms.TextBox
        $text.Multiline=$true;$text.ReadOnly=$true;$text.ScrollBars='Vertical';$text.Dock='Fill';$text.Text=$lines -join "`r`n"
        $panel=New-Object Windows.Forms.FlowLayoutPanel;$panel.Dock='Bottom';$panel.Height=48
        $retry=New-Object Windows.Forms.Button;$retry.Text='重新检查';$retry.Width=110;$retry.DialogResult='Retry'
        $cancel=New-Object Windows.Forms.Button;$cancel.Text='取消';$cancel.DialogResult='Cancel'
        $panel.Controls.Add($retry);$panel.Controls.Add($cancel);$form.Controls.Add($text);$form.Controls.Add($panel)
        $form.CancelButton=$cancel
        return ($form.ShowDialog() -eq [Windows.Forms.DialogResult]::Retry)
    }finally{$form.Dispose()}
}

function Wait-MaintenanceApplicationRelease {
    param([Parameter(Mandatory)][scriptblock]$Check,[switch]$Interactive,[Parameter(Mandatory)][string]$EvidenceRoot)
    while($true){
        $snapshot=& $Check
        $path=Join-Path $EvidenceRoot ('application-use-'+[guid]::NewGuid().ToString('N')+'.json')
        [IO.File]::WriteAllText($path,($snapshot|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
        Write-Host ('Application use evidence: '+$path)
        if($snapshot.clear){return}
        if(-not $Interactive){throw 'Maintenance resources are unavailable; no mutation performed. Use the interactive entry to save and close applications.'}
        if(-not (Show-MaintenanceApplicationPrompt $snapshot)){throw [OperationCanceledException]::new('Maintenance cancelled; no further operation performed.')}
        # Only the read-only check repeats. The caller owns all subsequent admission checks.
    }
}
Export-ModuleMember -Function Get-MaintenanceApplicationUse,Wait-MaintenanceApplicationRelease
