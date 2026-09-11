# Pure scheduling metadata; never grants installed-product acceptance.
function Get-CIShardNames([string[]]$Names,[int]$Index,[int]$Count){
    if($Count -notin @(1,3) -or $Index -lt 0 -or $Index -ge $Count){throw 'Invalid CI shard coordinate.'}
    if($Names.Count -lt $Count -or @($Names|Sort-Object -Unique -CaseSensitive).Count -ne $Names.Count){throw 'Empty or duplicate CI test inventory.'}
    $selected=@();for($i=0;$i -lt $Names.Count;$i++){if($i % $Count -eq $Index){$selected+=,$Names[$i]}}
    return ,$selected
}
function New-CIShardResult([string]$Suite,[string[]]$Names,[string[]]$Executed,[int]$Index,[int]$Count,[bool]$Passed,[string]$ScriptPath){
    $selected=Get-CIShardNames $Names $Index $Count
    if((@($selected|Sort-Object -CaseSensitive) -join "`n") -cne (@($Executed|Sort-Object -CaseSensitive) -join "`n")){throw 'Shard executed set differs from its assigned test set.'}
    $commit=$env:GITHUB_SHA
    if(-not $commit){$commit=(& git rev-parse HEAD).Trim();if($LASTEXITCODE -ne 0){throw 'Cannot bind shard source commit.'}}
    [pscustomobject][ordered]@{schema_version='yime-ci-test-shard-v1';suite=$Suite;index=$Index;count=$Count;
        shell=$(if($PSVersionTable.PSVersion.Major -eq 5){'powershell'}else{'pwsh'});commit=$commit;
        source_sha256=(Get-FileHash -LiteralPath $ScriptPath -Algorithm SHA256).Hash.ToLowerInvariant();
        all_names=@($Names);executed_names=@($Executed);passed=$Passed;installed_acceptance_passed=$false}
}
Export-ModuleMember -Function Get-CIShardNames,New-CIShardResult
