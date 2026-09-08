[CmdletBinding()]
param(
    [string]$OutputRoot,
    [string]$WorkerCasePath,
    [string]$Phase,
    [string]$CheckPattern='*'
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')

if($WorkerCasePath){
    $worker=[IO.Path]::GetFullPath($WorkerCasePath)
    $caseRoot=Split-Path -Parent $worker
    $casesRoot=Split-Path -Parent $caseRoot
    $runRoot=Split-Path -Parent $casesRoot
    $allowedRoot=Join-Path $repo '.tmp\dual-product'
    if([IO.Path]::GetFileName($worker) -cne 'worker.json' -or
        (Split-Path -Leaf $casesRoot) -cne 'cases' -or
        (Split-Path -Leaf $caseRoot) -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' -or
        (Split-Path -Leaf $runRoot) -cnotmatch '^dp1-package-receipt-v2-test-dp1n-[A-Za-z0-9][A-Za-z0-9._-]*$' -or
        (Split-Path -Parent $runRoot) -ine $allowedRoot){
        throw 'Transaction worker is fixture-only.'
    }
    Import-Module (Join-Path $PSScriptRoot 'rime-pime-installer-receipt-transaction.psm1') -Force
    $module=Get-Module rime-pime-installer-receipt-transaction
    & $module {
        param($AllowedRoot,$RunRoot,$CasesRoot,$CaseRoot,$Worker)
        foreach($path in @($AllowedRoot,$RunRoot,$CasesRoot,$CaseRoot,$Worker)){
            Assert-RimePimeNoReparsePath $path
        }
    } $allowedRoot $runRoot $casesRoot $caseRoot $worker
    $workerRecord=& $module {param($Path) Get-YimePimePayloadFileRecord $Path} $worker
    $workerText=[IO.File]::ReadAllText($worker)
    & $module {param($Text) Assert-RimePimeReceiptJsonSyntax $Text} $workerText
    $case=$workerText|ConvertFrom-Json
    & $module {
        param($Value)
        Assert-RimePimeExactProperties $Value @(
            'schema_version','Root','NextDigest','Before','HistoricalV1Path'
        ) 'transaction worker input'
    } $case
    if($case.schema_version -isnot [string] -or
        [string]$case.schema_version -cne 'yime-rime-pime-installer-receipt-worker-v1'){
        throw 'Transaction worker schema is invalid.'
    }
    foreach($name in @('Root','NextDigest','Before','HistoricalV1Path')){
        if($case.$name -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$case.$name)){
            throw 'Transaction worker input is invalid.'
        }
    }
    $expectedRoot=Join-Path $caseRoot 'repo'
    if([IO.Path]::GetFullPath([string]$case.Root).TrimEnd('\') -ine $expectedRoot){
        throw 'Transaction worker root is not bound to its own fixture case.'
    }
    $workerAfter=& $module {param($Path) Get-YimePimePayloadFileRecord $Path} $worker
    if([string]$workerAfter.sha256 -cne [string]$workerRecord.sha256 -or
        [long]$workerAfter.bytes -ne [long]$workerRecord.bytes -or
        [string]$workerAfter.file_id -cne [string]$workerRecord.file_id){
        throw 'Transaction worker input changed while it was read.'
    }
    $allowedPhases=@(
        'objects','installer-copy','installer-temp','intent-copy','intent-temp','intent',
        'installer-before-move','installer','receipt','sidecar','complete',
        'recover','publish','locked'
    )
    if($Phase -cnotin $allowedPhases){throw 'Transaction worker phase is invalid.'}
    & $module {
        param($StopPhase)
        $script:TransactionStopPhase=$StopPhase
        function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint([string]$Checkpoint){
            if($Checkpoint -ceq $script:TransactionStopPhase){[Environment]::Exit(73)}
        }
    } $Phase
    if($Phase -ceq 'recover'){
        $null=Resume-RimePimeInstallerReceiptTransaction -RepoRoot $case.Root
    }elseif($Phase -ceq 'locked'){
        try{
            $null=Publish-RimePimeInstallerReceiptTransaction -RepoRoot $case.Root `
                -NextReceiptDigest $case.NextDigest -ExpectedPreviousDigest $case.Before `
                -HistoricalV1Path $case.HistoricalV1Path
        }catch{
            [IO.File]::WriteAllText($worker+'.lock-error.txt',($_|Out-String))
            for($errorValue=$_.Exception;$null -ne $errorValue;$errorValue=$errorValue.InnerException){
                if(($errorValue.HResult -band 65535) -in @(32,33) -or
                    ($errorValue -is [ComponentModel.Win32Exception] -and $errorValue.NativeErrorCode -in @(32,33))){exit 74}
            }
            throw
        }
    }else{
        $null=Publish-RimePimeInstallerReceiptTransaction -RepoRoot $case.Root `
            -NextReceiptDigest $case.NextDigest -ExpectedPreviousDigest $case.Before `
            -HistoricalV1Path $case.HistoricalV1Path
    }
    exit 0
}

if([string]::IsNullOrWhiteSpace($OutputRoot)){throw 'OutputRoot is required outside worker mode.'}
$leaf=Split-Path -Leaf ([IO.Path]::GetFullPath($OutputRoot))
if($leaf -cnotmatch '^dp1-package-receipt-v2-test-dp1n-[A-Za-z0-9-]+$'){
    throw 'Use a fresh dp1-package-receipt-v2-test-dp1n-* output root.'
}
. (Join-Path $PSScriptRoot 'test-rime-pime-package-receipt-v2.ps1') -OutputRoot $OutputRoot -DefinitionsOnly
Import-Module (Join-Path $PSScriptRoot 'rime-pime-installer-receipt-transaction.psm1') -Force

$declaredChecks=[Collections.Generic.List[string]]::new()
$caseDirectories=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Body){
    if($declaredChecks.Contains($Name)){throw "Duplicate transaction check name: $Name"}
    $declaredChecks.Add($Name)
    if($Name -notlike $CheckPattern){return}
    try{& $Body;$checks.Add([pscustomobject]@{name=$Name;passed=$true;detail='ok'})}
    catch{$checks.Add([pscustomobject]@{name=$Name;passed=$false;detail=$_.Exception.Message})}
}

function Get-TestReceiptObjectPath([string]$Root,[string]$Digest){
    return Join-Path $Root ('installer\receipt-evidence\sha256\'+$Digest.Substring(0,2)+'\'+$Digest+'.blob')
}

function Get-TestPathObservation([string]$Path){
    $full=[IO.Path]::GetFullPath($Path)
    if(-not(Test-Path -LiteralPath $full)){
        return [pscustomobject][ordered]@{path=$full;kind='absent'}
    }
    $item=Get-Item -LiteralPath $full -Force
    if($item.PSIsContainer){
        return [pscustomobject][ordered]@{
            path=$full;kind='directory';attributes=[int64]$item.Attributes
            target=[string](@($item.Target)-join '|')
        }
    }
    $native=$null
    if('YimePime.Payload.NativeInspection' -as [type]){
        $native=[YimePime.Payload.NativeInspection]::Inspect($full)
    }
    $fileId=if($null -eq $native){''}else{[string]$native.FileId}
    $linkCount=if($null -eq $native){0}else{[uint32]$native.LinkCount}
    $streams=if($null -eq $native){@()}else{@($native.Streams|Sort-Object)}
    return [pscustomobject][ordered]@{
        path=$full;kind='file';attributes=[int64]$item.Attributes
        bytes=[long]$item.Length;sha256=(Hash $full)
        file_id=$fileId;link_count=$linkCount;streams=$streams
    }
}

function Get-TestDirectoryFileInventory([string]$Root,[switch]$Recurse){
    if(-not(Test-Path -LiteralPath $Root -PathType Container)){return @()}
    $parameters=@{LiteralPath=$Root;Force=$true;File=$true}
    if($Recurse){$parameters.Recurse=$true}
    $rows=[Collections.Generic.List[object]]::new()
    foreach($file in @(Get-ChildItem @parameters|Sort-Object FullName)){
        $observation=Get-TestPathObservation $file.FullName
        $rows.Add([pscustomobject][ordered]@{
            relative=$file.FullName.Substring([IO.Path]::GetFullPath($Root).TrimEnd('\').Length+1)
            observation=$observation
        })
    }
    return @($rows)
}

function Get-TestRetainedStoreSnapshot($Case){
    $store=Join-Path $Case.Root 'installer\receipt-evidence\sha256'
    return (Get-TestDirectoryFileInventory $store -Recurse|ConvertTo-Json -Depth 8 -Compress)
}

function Get-TestProtectedSnapshot($Case){
    $installer=Join-Path $Case.Root 'installer'
    $evidence=Join-Path $installer 'receipt-evidence'
    $known=@(
        $Case.Canonical,($Case.Canonical+'.sha256'),$Case.OldInstaller,$Case.NewInstaller,
        $Case.Pending,$Case.Stage,$Case.Completed,
        (Join-Path $installer '.rime-pime-publication.lock')
    )
    $value=[pscustomobject][ordered]@{
        known=@($known|ForEach-Object{Get-TestPathObservation $_})
        installer_files=@(Get-TestDirectoryFileInventory $installer)
        evidence_files=@(Get-TestDirectoryFileInventory $evidence)
        retained_files=@(Get-TestDirectoryFileInventory (Join-Path $evidence 'sha256') -Recurse)
    }
    return ($value|ConvertTo-Json -Depth 12 -Compress)
}

function Assert-TestProtectedUnchanged($Case,[string]$Before,[string]$Context){
    $after=Get-TestProtectedSnapshot $Case
    Assert-True ($after -ceq $Before) "$Context changed the protected transaction set."
}

function Get-TestReceiptPairSnapshot([string]$Canonical){
    $value=@(
        Get-TestPathObservation $Canonical
        Get-TestPathObservation ($Canonical+'.sha256')
    )
    return ($value|ConvertTo-Json -Depth 8 -Compress)
}

function Get-ActualCheckoutSnapshot {
    return Get-TestReceiptPairSnapshot (Join-Path $repo 'installer\package-build-receipt.json')
}

function Assert-ActualCheckoutPreserved([string]$Before,[string]$Context){
    Assert-True ((Get-ActualCheckoutSnapshot) -ceq $Before) "$Context changed the actual checkout canonical receipt pair."
}

function Assert-TestLeafAbsent([string]$Path,[string]$Context){
    Assert-True (-not(Test-Path -LiteralPath $Path)) "$Context should be absent."
}

function Assert-TestNormalLeafExact([string]$Path,[string]$Sha256,[long]$Bytes,[string]$Context){
    $record=Get-YimePimePayloadFileRecord $Path
    Assert-True ([string]$record.sha256 -ceq $Sha256) "$Context SHA-256 changed."
    Assert-True ([long]$record.bytes -eq $Bytes) "$Context byte count changed."
    Assert-True ([uint32]$record.link_count -eq 1) "$Context is hard-linked."
    Assert-True (@($record.streams).Count -eq 1 -and [string]$record.streams[0] -ceq '::$DATA') "$Context has an alternate data stream."
    return $record
}

function Assert-TestIntentLeafExact([string]$Path,$Case,[string]$Context){
    $record=Assert-TestNormalLeafExact $Path $Case.IntentDigest $Case.IntentBytes $Context
    $intent=ConvertFrom-TestJson ([IO.File]::ReadAllText($Path))
    $module=Get-Module rime-pime-installer-receipt-transaction
    $validated=& $module {param($Value) Assert-RimePimeInstallerReceiptTransactionIntent $Value} $intent
    Assert-True ([string]$validated.operation_id -ceq $Case.OperationId) "$Context operation id changed."
    return $record
}

function Assert-TestCanonicalPair($Case,[string]$ReceiptDigest,[string]$SidecarDigest,[string]$Context){
    $null=Assert-TestNormalLeafExact $Case.Canonical $ReceiptDigest `
        ([long](Get-Item -LiteralPath $Case.Canonical).Length) "$Context canonical receipt"
    $sidecar=Get-YimePimePayloadFileRecord ($Case.Canonical+'.sha256')
    $expected=$SidecarDigest+'  package-build-receipt.json'+"`n"
    Assert-True ([IO.File]::ReadAllText($Case.Canonical+'.sha256') -ceq $expected) "$Context canonical sidecar binding changed."
    Assert-True ([long]$sidecar.bytes -eq [Text.Encoding]::ASCII.GetByteCount($expected)) "$Context canonical sidecar byte count changed."
}

function Get-TestUniqueInstallerCopies($Case){
    $parent=Split-Path -Parent $Case.NewInstaller
    return @(Get-ChildItem -LiteralPath $parent -Filter '.rime-pime-copy-*.tmp' -Force -File -ErrorAction SilentlyContinue|Sort-Object FullName)
}

function Get-TestUniqueIntentCopies($Case){
    $parent=Split-Path -Parent $Case.Pending
    return @(Get-ChildItem -LiteralPath $parent -Filter '.rime-pime-intent-*.tmp' -Force -File -ErrorAction SilentlyContinue|Sort-Object FullName)
}

function New-TestGeneration([string]$Name,[string]$Version,[int]$Seed){
    $case=New-Case -Name $Name -ProductVersion $Version -InstallerSeed $Seed
    $prepared=$null
    try{
        $prepared=Prepare $case
        $published=Publish-RimePimePackageReceiptV2 $prepared $case.V1Path
    }finally{Close-RimePimePackageReceiptV2Preparation $prepared}
    $history=Join-Path $case.V2Output 'historical\package-build-receipt-v1.json'
    $retained=Publish-RimePimePackageReceiptV2Supersession -RepoRoot $case.Root `
        -ReceiptPath $case.V1Path -ExpectedPreviousDigest $published.Digest -HistoricalV1Path $history
    return [pscustomobject]@{Case=$case;Receipt=$retained;History=$history}
}

function Merge-TestEvidenceStore([string]$SourceRoot,[string]$DestinationRoot){
    if(-not(Test-Path -LiteralPath $SourceRoot -PathType Container)){throw 'Source evidence store is missing.'}
    foreach($source in @(Get-ChildItem -LiteralPath $SourceRoot -Recurse -File)){
        $relative=$source.FullName.Substring($SourceRoot.Length+1)
        $destination=Join-Path $DestinationRoot $relative
        $parent=Split-Path -Parent $destination
        if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
        if(Test-Path -LiteralPath $destination){
            if((Hash $source.FullName) -cne (Hash $destination)){throw "Evidence object collision: $relative"}
        }else{[IO.File]::Copy($source.FullName,$destination,$false)}
    }
}

function New-ReplacementCase(
    [string]$Name,
    [string]$NewVersion='2.0-new',
    [ValidateRange(0,255)][int]$NewSeed=2,
    [string]$OldVersion='1.0-old',
    [ValidateRange(0,255)][int]$OldSeed=1,
    [switch]$OldReceiptNonDurable,
    [switch]$AllowSameInstallerPath
){
    # Keep labels in the result rather than repeating them in both the case
    # directory and receipt-v2 output. PS5 must also move the complete tree
    # into snapshots, including its deepest SHA-256 sidecars.
    $caseLabel=$Name
    $Name='c{0}' -f ($script:caseDirectories.Count+1)
    $snapshotRepo=Join-Path $output ('snapshots\'+$Name+'\repo')
    $receiptOutput='.tmp\dual-product\dp1-package-receipt-v2-'+$Name
    $budgetPaths=@(
        ($receiptOutput+'\publication-recovery\previous\package-build-receipt.json.sha256'),
        ($receiptOutput+'\historical\package-build-receipt-v1.json.sha256'),
        ('installer\receipt-evidence\sha256\aa\'+('a'*64)+'.blob.sha256'),
        ('installer\receipt-evidence\completed-'+('a'*64)+'.json'),
        ('installer\.rime-pime-installer-'+('a'*64)+'.staged')
    )
    foreach($relative in $budgetPaths){
        if((Join-Path $snapshotRepo $relative).Length -ge 260){
            throw 'DP1-N fixture exceeds the Win32 path budget; use a shorter checkout or fresh output root.'
        }
    }
    $script:caseDirectories.Add([pscustomobject][ordered]@{
        name=$caseLabel;relative_directory=('cases/'+$Name);snapshot_relative_directory=('snapshots/'+$Name)
    })
    $newGeneration=New-TestGeneration -Name $Name -Version $NewVersion -Seed $NewSeed
    $caseRoot=Split-Path -Parent $newGeneration.Case.Root
    $snapshotParent=Join-Path $output 'snapshots'
    if(-not(Test-Path -LiteralPath $snapshotParent)){New-Item -ItemType Directory -Path $snapshotParent|Out-Null}
    $snapshot=Join-Path $snapshotParent $Name
    [IO.Directory]::Move($caseRoot,$snapshot)

    if($OldReceiptNonDurable){
        $oldCase=New-Case -Name $Name -ProductVersion $OldVersion -InstallerSeed $OldSeed
        $prepared=$null
        try{
            $prepared=Prepare $oldCase
            $published=Publish-RimePimePackageReceiptV2 $prepared $oldCase.V1Path
        }finally{Close-RimePimePackageReceiptV2Preparation $prepared}
        $oldGeneration=[pscustomobject]@{
            Case=$oldCase;Receipt=$published
            History=Join-Path $oldCase.V2Output 'historical\package-build-receipt-v1.json'
        }
    }else{
        $oldGeneration=New-TestGeneration -Name $Name -Version $OldVersion -Seed $OldSeed
    }
    $sourceStore=Join-Path $snapshot 'repo\installer\receipt-evidence\sha256'
    $destinationStore=Join-Path $oldGeneration.Case.Root 'installer\receipt-evidence\sha256'
    Merge-TestEvidenceStore $sourceStore $destinationStore
    $nextPath=Get-TestReceiptObjectPath $oldGeneration.Case.Root $newGeneration.Receipt.Digest
    $next=Read-RimePimePackageBuildReceiptV2 $oldGeneration.Case.Root $nextPath
    $current=Read-RimePimePackageBuildReceiptV2 $oldGeneration.Case.Root $oldGeneration.Case.V1Path
    $oldPath=Join-Path $oldGeneration.Case.Root $current.Receipt.installer.path.Replace('/','\')
    $newPath=Join-Path $oldGeneration.Case.Root $next.Receipt.installer.path.Replace('/','\')
    Assert-True (Test-Path -LiteralPath $oldPath -PathType Leaf) 'Old installer fixture is missing.'
    if($AllowSameInstallerPath){
        Assert-True ($oldPath -ieq $newPath) 'Shared-path fixture did not resolve both strict receipts to one installer path.'
    }else{
        Assert-True ($oldPath -ine $newPath) 'Replacement fixture requires distinct versioned installer paths.'
        Assert-True (-not(Test-Path -LiteralPath $newPath)) 'New installer fixture must be absent before transaction intent.'
    }
    Assert-True ($current.Digest -ceq $oldGeneration.Receipt.Digest) 'Current retained receipt changed during fixture assembly.'
    Assert-True ($next.Digest -ceq $newGeneration.Receipt.Digest) 'Merged next retained receipt changed identity.'
    $oldRecord=Get-YimePimePayloadFileRecord $oldPath
    $oldIdentity=[pscustomobject]@{
        RelativePath=[string]$current.Receipt.installer.path
        Path=$oldPath;Sha256=[string]$current.Receipt.installer.sha256
        Bytes=[long]$current.Receipt.installer.bytes
    }
    $newIdentity=[pscustomobject]@{
        RelativePath=[string]$next.Receipt.installer.path
        Path=$newPath;Sha256=[string]$next.Receipt.installer.sha256
        Bytes=[long]$next.Receipt.installer.bytes
    }
    $module=Get-Module rime-pime-installer-receipt-transaction
    $retainedValue=ConvertFrom-TestJson ($current.Receipt|ConvertTo-Json -Depth 30 -Compress)
    $retainedValue.evidence_artifacts_durable=$true
    $retainedDigest=& $module {
        param($Value)
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-RimePimeStageCanonicalJson $Value)+"`n")
        return Get-RimePimeReceiptV2Sha256Bytes $bytes
    } $retainedValue
    $intent=& $module {
        param($OldDigest,$OldRetainedDigest,$NextDigest,$OldInstaller,$NewInstaller)
        New-RimePimeInstallerReceiptTransactionIntent $OldDigest $OldRetainedDigest $NextDigest $OldInstaller $NewInstaller
    } $current.Digest $retainedDigest $next.Digest $oldIdentity $newIdentity
    $intentInfo=& $module {
        param($Value)
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-RimePimeStageCanonicalJson $Value)+"`n")
        return [pscustomobject]@{
            Digest=(Get-RimePimeReceiptV2Sha256Bytes $bytes);Bytes=[long]$bytes.Length
        }
    } $intent
    $operationId=[string]$intent.operation_id
    $case=[pscustomobject]@{
        Root=$oldGeneration.Case.Root
        Canonical=$oldGeneration.Case.V1Path
        Before=$current.Digest
        OldReceiptOriginalDigest=$current.Digest
        OldReceiptRetainedDigest=$retainedDigest
        NextDigest=$next.Digest
        HistoricalV1Path=$oldGeneration.History
        OldInstaller=$oldPath
        OldInstallerSha256=[string]$current.Receipt.installer.sha256
        OldInstallerBytes=[long]$current.Receipt.installer.bytes
        OldInstallerRecord=$oldRecord
        NewInstaller=$newPath
        NewInstallerSha256=[string]$next.Receipt.installer.sha256
        NewInstallerBytes=[long]$next.Receipt.installer.bytes
        OperationId=$operationId
        IntentDigest=[string]$intentInfo.Digest
        IntentBytes=[long]$intentInfo.Bytes
        Pending=Join-Path $oldGeneration.Case.Root 'installer\receipt-evidence\pending.json'
        Stage=Join-Path (Split-Path -Parent $newPath) ('.rime-pime-installer-'+$operationId+'.staged')
        Completed=Join-Path $oldGeneration.Case.Root ('installer\receipt-evidence\completed-'+$operationId+'.json')
        Snapshot=$snapshot
    }
    $case|Add-Member -NotePropertyName RetainedStoreSnapshot -NotePropertyValue (Get-TestRetainedStoreSnapshot $case)
    return $case
}

function Write-WorkerCase($Case){
    $path=Join-Path (Split-Path -Parent $Case.Root) 'worker.json'
    $value=[pscustomobject][ordered]@{
        schema_version='yime-rime-pime-installer-receipt-worker-v1'
        Root=[string]$Case.Root;NextDigest=[string]$Case.NextDigest;Before=[string]$Case.Before
        HistoricalV1Path=[string]$Case.HistoricalV1Path
    }
    $stream=[IO.FileStream]::new($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,
        [IO.FileShare]::None,4096,[IO.FileOptions]::WriteThrough)
    try{
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($value|ConvertTo-Json -Compress)+"`n")
        $stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)
    }finally{$stream.Dispose()}
    return $path
}

function Invoke-TestTransaction($Case){
    return Publish-RimePimeInstallerReceiptTransaction -RepoRoot $Case.Root `
        -NextReceiptDigest $Case.NextDigest -ExpectedPreviousDigest $Case.Before `
        -HistoricalV1Path $Case.HistoricalV1Path
}

function Assert-TestIntentBindings($Intent,$Case,[string]$Context){
    Assert-True ([string]$Intent.old_receipt_original_sha256 -ceq $Case.OldReceiptOriginalDigest) `
        "$Context old original receipt binding changed."
    Assert-True ([string]$Intent.old_receipt_retained_sha256 -ceq $Case.OldReceiptRetainedDigest) `
        "$Context old retained receipt binding changed."
    Assert-True ([string]$Intent.new_receipt_sha256 -ceq $Case.NextDigest) `
        "$Context new receipt binding changed."
    Assert-True ([string]$Intent.old_installer_path -ceq `
        $Case.OldInstaller.Substring($Case.Root.Length+1).Replace('\','/')) `
        "$Context old installer path binding changed."
    Assert-True ([string]$Intent.old_installer_sha256 -ceq $Case.OldInstallerSha256 -and
        [long]$Intent.old_installer_bytes -eq $Case.OldInstallerBytes) `
        "$Context old installer identity binding changed."
    Assert-True ([string]$Intent.new_installer_path -ceq `
        $Case.NewInstaller.Substring($Case.Root.Length+1).Replace('\','/')) `
        "$Context new installer path binding changed."
    Assert-True ([string]$Intent.new_installer_sha256 -ceq $Case.NewInstallerSha256 -and
        [long]$Intent.new_installer_bytes -eq $Case.NewInstallerBytes) `
        "$Context new installer identity binding changed."
}

function Assert-OldInstallerPreserved($Case){
    $record=Assert-TestNormalLeafExact $Case.OldInstaller $Case.OldInstallerSha256 $Case.OldInstallerBytes 'old installer'
    Assert-True ([string]$record.file_id -ceq [string]$Case.OldInstallerRecord.file_id) 'Old installer was deleted and recreated.'
}

function Assert-RetainedStorePreserved($Case){
    Assert-True ((Get-TestRetainedStoreSnapshot $Case) -ceq [string]$Case.RetainedStoreSnapshot) 'Retained evidence store changed.'
}

function Assert-TransactionCommitted($Case){
    $read=Read-RimePimePackageBuildReceiptV2 $Case.Root $Case.Canonical
    Assert-True ($read.Digest -ceq $Case.NextDigest) 'Canonical receipt did not converge to next identity.'
    $null=Assert-TestNormalLeafExact $Case.NewInstaller $Case.NewInstallerSha256 $Case.NewInstallerBytes 'new physical installer'
    Assert-OldInstallerPreserved $Case
    Assert-RetainedStorePreserved $Case
    Assert-TestLeafAbsent $Case.Pending 'Committed pending intent'
    Assert-TestLeafAbsent $Case.Stage 'Committed deterministic installer stage'
    $null=Assert-TestIntentLeafExact $Case.Completed $Case 'completed transaction record'
    return $read
}

# Initialize native identity observations without requiring a locally built
# receipt. Clean CI checkouts legitimately have no canonical receipt pair.
Initialize-YimePimePayloadNativeInspection
$actualCheckoutBaseline=Get-ActualCheckoutSnapshot

function Assert-HardExitState($Case,[string]$Stop,[string]$ActualBefore){
    $receiptDigest=if($Stop -in @('receipt','sidecar','complete')){$Case.NextDigest}else{$Case.Before}
    $sidecarDigest=if($Stop -in @('sidecar','complete')){$Case.NextDigest}else{$Case.Before}
    Assert-TestCanonicalPair $Case $receiptDigest $sidecarDigest ("hard-exit $Stop")

    $stageExpected=$Stop -in @('installer-temp','intent-copy','intent-temp','intent','installer-before-move')
    $newExpected=$Stop -in @('installer','receipt','sidecar','complete')
    $pendingExpected=$Stop -in @('intent','installer-before-move','installer','receipt','sidecar')
    $completedExpected=$Stop -ceq 'complete'

    if($stageExpected){$null=Assert-TestNormalLeafExact $Case.Stage $Case.NewInstallerSha256 $Case.NewInstallerBytes "hard-exit $Stop deterministic stage"}
    else{Assert-TestLeafAbsent $Case.Stage "hard-exit $Stop deterministic stage"}
    if($newExpected){$null=Assert-TestNormalLeafExact $Case.NewInstaller $Case.NewInstallerSha256 $Case.NewInstallerBytes "hard-exit $Stop new installer"}
    else{Assert-TestLeafAbsent $Case.NewInstaller "hard-exit $Stop new installer"}
    if($pendingExpected){$null=Assert-TestIntentLeafExact $Case.Pending $Case "hard-exit $Stop pending intent"}
    else{Assert-TestLeafAbsent $Case.Pending "hard-exit $Stop pending intent"}
    if($completedExpected){$null=Assert-TestIntentLeafExact $Case.Completed $Case "hard-exit $Stop completed record"}
    else{Assert-TestLeafAbsent $Case.Completed "hard-exit $Stop completed record"}

    $copies=Get-TestUniqueInstallerCopies $Case
    if($Stop -ceq 'installer-copy'){
        Assert-True ($copies.Count -eq 1) 'Mid-copy hard exit did not retain exactly one unique attempt leaf.'
        $partial=Get-TestPathObservation $copies[0].FullName
        Assert-True ([long]$partial.bytes -gt 0 -and [long]$partial.bytes -lt $Case.NewInstallerBytes) 'Mid-copy hard exit leaf is not a partial copy.'
    }else{
        Assert-True ($copies.Count -eq 0) ("hard-exit $Stop left an unexpected unique copy leaf.")
    }
    $intentCopies=Get-TestUniqueIntentCopies $Case
    if($Stop -ceq 'intent-copy'){
        Assert-True ($intentCopies.Count -eq 1) 'Mid-copy hard exit did not retain exactly one unique intent leaf.'
        $partial=Get-TestPathObservation $intentCopies[0].FullName
        Assert-True ([long]$partial.bytes -gt 0 -and [long]$partial.bytes -lt $Case.IntentBytes) 'Mid-copy intent leaf is not partial.'
    }elseif($Stop -ceq 'intent-temp'){
        Assert-True ($intentCopies.Count -eq 1) 'Intent-temp hard exit did not retain exactly one unique intent leaf.'
        $null=Assert-TestIntentLeafExact $intentCopies[0].FullName $Case 'hard-exit intent-temp unique intent leaf'
    }else{
        Assert-True ($intentCopies.Count -eq 0) ("hard-exit $Stop left an unexpected unique intent leaf.")
    }
    Assert-OldInstallerPreserved $Case
    Assert-RetainedStorePreserved $Case
    Assert-ActualCheckoutPreserved $ActualBefore ("hard-exit $Stop")
}

Check 'module-exports-only-two-isolated-transaction-apis' {
    $expected=@('Publish-RimePimeInstallerReceiptTransaction','Resume-RimePimeInstallerReceiptTransaction')|Sort-Object
    $actual=@((Get-Module rime-pime-installer-receipt-transaction).ExportedCommands.Keys|Sort-Object)
    Assert-True (($expected -join "`n") -ceq ($actual -join "`n")) ('Unexpected transaction exports: '+($actual -join ', '))
}

Check 'absent-checkout-receipt-pair-is-observed-without-creating-files' {
    $fixture=Join-Path $output 'checkout-observation-absent'
    [IO.Directory]::CreateDirectory($fixture)|Out-Null
    $canonical=Join-Path $fixture 'package-build-receipt.json'
    $before=Get-TestReceiptPairSnapshot $canonical
    $records=ConvertFrom-TestJson $before
    Assert-True ($records.Count -eq 2) 'Absent receipt pair did not produce two observations.'
    Assert-True ($records[0].kind -ceq 'absent' -and $records[1].kind -ceq 'absent') 'Missing receipt pair was not recorded as absent.'
    Assert-True ((Get-TestReceiptPairSnapshot $canonical) -ceq $before) 'Read-only absent observations changed.'
    Assert-True (@(Get-ChildItem -LiteralPath $fixture -Force).Count -eq 0) 'Absent observation created a file.'
    Assert-Rejected {Get-YimePimePayloadFileRecord $canonical} '*Payload file is missing:*'
}

Check 'present-checkout-receipt-pair-keeps-native-identity-and-detects-content-change' {
    $fixture=Join-Path $output 'checkout-observation-present'
    [IO.Directory]::CreateDirectory($fixture)|Out-Null
    $canonical=Join-Path $fixture 'package-build-receipt.json'
    [IO.File]::WriteAllBytes($canonical,[byte[]]@(1,2,3,4))
    [IO.File]::WriteAllText($canonical+'.sha256','fixture sidecar',[Text.Encoding]::ASCII)
    $before=Get-TestReceiptPairSnapshot $canonical
    $records=ConvertFrom-TestJson $before
    Assert-True ($records.Count -eq 2) 'Present receipt pair did not produce two observations.'
    foreach($record in $records){
        Assert-True ($record.kind -ceq 'file' -and -not [string]::IsNullOrEmpty($record.file_id)) 'Present observation omitted native file identity.'
        Assert-True ($record.link_count -eq 1 -and @($record.streams).Count -eq 1 -and @($record.streams)[0] -ceq '::$DATA') 'Present observation omitted native link/stream facts.'
    }
    Assert-True ((Get-TestReceiptPairSnapshot $canonical) -ceq $before) 'Read-only present observations changed.'
    [IO.File]::WriteAllBytes($canonical,[byte[]]@(4,3,2,1))
    Assert-True ((Get-TestReceiptPairSnapshot $canonical) -cne $before) 'Same-length receipt content change was not observed.'
    [IO.File]::WriteAllBytes($canonical,[byte[]]@(1,2,3,4))
    $beforeSidecar=Get-TestReceiptPairSnapshot $canonical
    [IO.File]::WriteAllText($canonical+'.sha256','fixture changed',[Text.Encoding]::ASCII)
    Assert-True ((Get-TestReceiptPairSnapshot $canonical) -cne $beforeSidecar) 'Sidecar content change was not observed.'
}

Check 'two-generations-pass-the-real-strict-reader-at-one-absolute-fixture-root' {
    $case=New-ReplacementCase 'strict-generations'
    Assert-True ($case.Before -cne $case.NextDigest) 'Fixture receipts are not distinct.'
    Assert-True ($case.OldInstallerSha256 -cne $case.NewInstallerSha256) 'Fixture installers are not distinct.'
    Assert-OldInstallerPreserved $case
}

Check 'clean-installer-and-receipt-identity-replacement-rolls-forward' {
    $case=New-ReplacementCase 'clean'
    $result=Invoke-TestTransaction $case
    Assert-True ($result.Digest -ceq $case.NextDigest) 'Publish returned the wrong receipt.'
    $null=Assert-TransactionCommitted $case
    $again=Resume-RimePimeInstallerReceiptTransaction -RepoRoot $case.Root
    Assert-True ($again.Digest -ceq $case.NextDigest) 'Repeated Resume is not idempotent.'
}

Check 'non-durable-old-clean-publish-binds-distinct-retention-and-history' {
    $case=New-ReplacementCase -Name 'nondurable-clean' -OldReceiptNonDurable
    $current=Read-RimePimePackageBuildReceiptV2 $case.Root $case.Canonical
    Assert-True (-not [bool]$current.Receipt.evidence_artifacts_durable) `
        'Non-durable old fixture unexpectedly entered the transaction as durable.'
    Assert-True ($case.OldReceiptOriginalDigest -cne $case.OldReceiptRetainedDigest) `
        'Non-durable old fixture did not derive a distinct retention-only receipt identity.'
    Assert-True (Test-Path -LiteralPath $case.HistoricalV1Path -PathType Leaf) `
        'Non-durable old fixture historical v1 input is missing.'
    $predecessorDigest=[string]$current.Receipt.predecessor_v1.sha256
    $predecessorObject=Get-TestReceiptObjectPath $case.Root $predecessorDigest
    $originalObject=Get-TestReceiptObjectPath $case.Root $case.OldReceiptOriginalDigest
    $retainedObject=Get-TestReceiptObjectPath $case.Root $case.OldReceiptRetainedDigest
    foreach($path in @($predecessorObject,$originalObject,$retainedObject)){
        Assert-TestLeafAbsent $path 'Pre-transaction non-durable old retained object'
    }
    $historyBefore=Get-TestPathObservation $case.HistoricalV1Path
    $result=Invoke-TestTransaction $case
    Assert-True ($result.Digest -ceq $case.NextDigest) 'Non-durable clean publish returned the wrong receipt.'
    foreach($pair in @(
        @($predecessorObject,$predecessorDigest,'historical v1 retained object'),
        @($originalObject,$case.OldReceiptOriginalDigest,'old original receipt object'),
        @($retainedObject,$case.OldReceiptRetainedDigest,'old retention-only receipt object'))){
        $record=Get-YimePimePayloadFileRecord $pair[0]
        Assert-True ([string]$record.sha256 -ceq [string]$pair[1]) `
            ("Non-durable clean publish changed the "+[string]$pair[2]+'.')
    }
    Assert-True ((Get-TestPathObservation $case.HistoricalV1Path|ConvertTo-Json -Depth 8 -Compress) -ceq
        ($historyBefore|ConvertTo-Json -Depth 8 -Compress)) `
        'Non-durable clean publish changed its historical v1 input.'
    $completed=ConvertFrom-TestJson ([IO.File]::ReadAllText($case.Completed))
    Assert-TestIntentBindings $completed $case 'Non-durable clean completed intent'
    $case.RetainedStoreSnapshot=Get-TestRetainedStoreSnapshot $case
    $null=Assert-TransactionCommitted $case
    Assert-ActualCheckoutPreserved $actualCheckoutBaseline 'Non-durable clean publish'
}

Check 'non-durable-old-intent-hard-exit-resumes-in-fresh-process' {
    $case=New-ReplacementCase -Name 'nondurable-intent-resume' -OldReceiptNonDurable
    Assert-True ($case.OldReceiptOriginalDigest -cne $case.OldReceiptRetainedDigest) `
        'Non-durable recovery fixture did not derive distinct old receipt identities.'
    $worker=Write-WorkerCase $case
    $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -WorkerCasePath "'+$worker+'" -Phase intent'
    $child=Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
    Assert-True ($child.ExitCode -eq 73) 'Non-durable worker did not stop after durable intent publication.'
    Assert-TestCanonicalPair $case $case.Before $case.Before 'non-durable hard-exit intent'
    $null=Assert-TestNormalLeafExact $case.Stage $case.NewInstallerSha256 $case.NewInstallerBytes `
        'non-durable hard-exit deterministic stage'
    Assert-TestLeafAbsent $case.NewInstaller 'non-durable hard-exit new installer'
    $null=Assert-TestIntentLeafExact $case.Pending $case 'non-durable hard-exit pending intent'
    $pending=ConvertFrom-TestJson ([IO.File]::ReadAllText($case.Pending))
    Assert-TestIntentBindings $pending $case 'Non-durable pending intent'
    Assert-TestLeafAbsent $case.Completed 'non-durable hard-exit completed record'
    Assert-OldInstallerPreserved $case
    $case.RetainedStoreSnapshot=Get-TestRetainedStoreSnapshot $case
    $protectedBefore=[pscustomobject][ordered]@{
        historical=Get-TestPathObservation $case.HistoricalV1Path
        original=Get-TestPathObservation (Get-TestReceiptObjectPath $case.Root $case.OldReceiptOriginalDigest)
        retained=Get-TestPathObservation (Get-TestReceiptObjectPath $case.Root $case.OldReceiptRetainedDigest)
        old_installer=Get-TestPathObservation $case.OldInstaller
    }|ConvertTo-Json -Depth 10 -Compress
    Assert-ActualCheckoutPreserved $actualCheckoutBaseline 'Non-durable durable-intent hard exit'

    $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -WorkerCasePath "'+$worker+'" -Phase recover'
    $recovery=Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
    Assert-True ($recovery.ExitCode -eq 0) 'Fresh-process Resume failed for the non-durable old intent.'
    $null=Assert-TransactionCommitted $case
    $completed=ConvertFrom-TestJson ([IO.File]::ReadAllText($case.Completed))
    Assert-TestIntentBindings $completed $case 'Non-durable recovered completed intent'
    $protectedAfter=[pscustomobject][ordered]@{
        historical=Get-TestPathObservation $case.HistoricalV1Path
        original=Get-TestPathObservation (Get-TestReceiptObjectPath $case.Root $case.OldReceiptOriginalDigest)
        retained=Get-TestPathObservation (Get-TestReceiptObjectPath $case.Root $case.OldReceiptRetainedDigest)
        old_installer=Get-TestPathObservation $case.OldInstaller
    }|ConvertTo-Json -Depth 10 -Compress
    Assert-True ($protectedAfter -ceq $protectedBefore) `
        'Fresh-process Resume changed the non-durable transaction protected inputs.'
    Assert-ActualCheckoutPreserved $actualCheckoutBaseline 'Non-durable fresh-process Resume'
}

Check 'stale-expected-current-receipt-is-rejected-before-intent' {
    $case=New-ReplacementCase 'stale'
    $before=Get-TestProtectedSnapshot $case
    Assert-Rejected {Publish-RimePimeInstallerReceiptTransaction $case.Root $case.NextDigest ('0'*64)} '*Stale*'
    Assert-TestProtectedUnchanged $case $before 'Stale CAS rejection'
    Assert-OldInstallerPreserved $case
}

Check 'same-installer-path-is-rejected-before-intent' {
    $case=New-ReplacementCase -Name 'same-path' `
        -NewVersion '1.0-same-path' -NewSeed 2 `
        -OldVersion '1.0-same-path' -OldSeed 1 -AllowSameInstallerPath
    $current=Read-RimePimePackageBuildReceiptV2 $case.Root $case.Canonical
    $next=Read-RimePimePackageBuildReceiptV2 $case.Root (Get-TestReceiptObjectPath $case.Root $case.NextDigest)
    Assert-True ($current.Digest -cne $next.Digest) 'Shared-path fixture receipts are not two distinct strict identities.'
    Assert-True ($case.OldInstaller -ieq $case.NewInstaller) 'Shared-path fixture did not use one physical installer path.'
    Assert-True ($case.OldInstallerSha256 -cne $case.NewInstallerSha256) 'Shared-path fixture installer SHA-256 identities are not distinct.'
    Assert-True ([string]$current.Receipt.installer.path -ceq [string]$next.Receipt.installer.path) 'Strict receipts do not bind the same installer path.'
    Assert-True ([string]$current.Receipt.installer.sha256 -cne [string]$next.Receipt.installer.sha256) 'Strict receipts do not bind distinct installer SHA-256 values.'
    $before=Get-TestProtectedSnapshot $case
    Assert-Rejected {Invoke-TestTransaction $case} '*distinct old/new versioned paths*'
    Assert-TestProtectedUnchanged $case $before 'Same-path rejection'
    Assert-OldInstallerPreserved $case
    Assert-RetainedStorePreserved $case
    Assert-ActualCheckoutPreserved $actualCheckoutBaseline 'Same-path rejection'
}

Check 'preexisting-exact-new-installer-is-rejected-before-intent' {
    $case=New-ReplacementCase 'preexisting-exact'
    $object=Get-TestReceiptObjectPath $case.Root $case.NewInstallerSha256
    [IO.File]::Copy($object,$case.NewInstaller,$false)
    $before=Get-TestProtectedSnapshot $case
    Assert-Rejected {Invoke-TestTransaction $case} '*already exists*'
    Assert-TestProtectedUnchanged $case $before 'Pre-existing exact new installer rejection'
    Assert-OldInstallerPreserved $case
}

Check 'preexisting-foreign-new-installer-is-rejected-and-preserved' {
    $case=New-ReplacementCase 'preexisting-foreign'
    [IO.File]::WriteAllText($case.NewInstaller,'foreign',[Text.UTF8Encoding]::new($false))
    $before=Get-TestProtectedSnapshot $case
    Assert-Rejected {Invoke-TestTransaction $case} '*already exists*'
    Assert-TestProtectedUnchanged $case $before 'Pre-existing foreign new installer rejection'
    Assert-OldInstallerPreserved $case
}

Check 'foreign-old-installer-is-rejected-and-preserved' {
    $case=New-ReplacementCase 'foreign-old'
    [IO.File]::WriteAllText($case.OldInstaller,'foreign-old',[Text.UTF8Encoding]::new($false))
    $before=Get-TestProtectedSnapshot $case
    Assert-Rejected {Invoke-TestTransaction $case} '*old*installer*'
    Assert-TestProtectedUnchanged $case $before 'Foreign old installer rejection'
}

Check 'hardlinked-new-installer-is-rejected-after-intent-state' {
    $case=New-ReplacementCase 'hardlink-new'
    $module=Get-Module rime-pime-installer-receipt-transaction
    & $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){if($Checkpoint -ceq 'intent'){throw 'test interruption'}}}
    try{Assert-Rejected {Invoke-TestTransaction $case} '*test interruption*'}finally{& $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){}}}
    $object=Get-TestReceiptObjectPath $case.Root $case.NewInstallerSha256
    $null=New-Item -ItemType HardLink -Path $case.NewInstaller -Target $object
    $before=Get-TestProtectedSnapshot $case
    Assert-Rejected {Resume-RimePimeInstallerReceiptTransaction $case.Root} '*Hard-linked*'
    Assert-TestProtectedUnchanged $case $before 'Hard-linked new installer rejection'
    Assert-OldInstallerPreserved $case
}

Check 'alternate-data-stream-on-new-installer-is-rejected-after-intent-state' {
    $case=New-ReplacementCase 'ads-new'
    $module=Get-Module rime-pime-installer-receipt-transaction
    & $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){if($Checkpoint -ceq 'intent'){throw 'test interruption'}}}
    try{Assert-Rejected {Invoke-TestTransaction $case} '*test interruption*'}finally{& $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){}}}
    $object=Get-TestReceiptObjectPath $case.Root $case.NewInstallerSha256
    [IO.File]::Copy($object,$case.NewInstaller,$false)
    # System.IO.File.WriteAllText on Windows PowerShell 5.1 rejects an ADS
    # suffix as an unsupported path format.  Use the FileSystem provider's
    # stream parameter so this negative fixture is exercised on both PS5/PS7.
    Set-Content -LiteralPath $case.NewInstaller -Stream foreign -Value 'ads' -Encoding Ascii
    $before=Get-TestProtectedSnapshot $case
    Assert-Rejected {Resume-RimePimeInstallerReceiptTransaction $case.Root} '*Alternate data stream*'
    Assert-TestProtectedUnchanged $case $before 'ADS-bearing new installer rejection'
    Assert-OldInstallerPreserved $case
}

Check 'directory-reparse-occupancy-is-rejected-after-intent-state' {
    $case=New-ReplacementCase 'reparse-new'
    $module=Get-Module rime-pime-installer-receipt-transaction
    & $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){if($Checkpoint -ceq 'intent'){throw 'test interruption'}}}
    try{Assert-Rejected {Invoke-TestTransaction $case} '*test interruption*'}finally{& $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){}}}
    $target=Join-Path (Split-Path -Parent $case.Root) 'junction-target';New-Item -ItemType Directory -Path $target|Out-Null
    $null=New-Item -ItemType Junction -Path $case.NewInstaller -Target $target
    $before=Get-TestProtectedSnapshot $case
    Assert-Rejected {Resume-RimePimeInstallerReceiptTransaction $case.Root}
    Assert-TestProtectedUnchanged $case $before 'Reparse occupancy rejection'
    Assert-OldInstallerPreserved $case
}

Check 'shared-publication-lock-blocks-an-independent-process' {
    $case=New-ReplacementCase 'lock'
    $worker=Write-WorkerCase $case
    $module=Get-Module rime-pime-installer-receipt-transaction
    $before=Get-TestProtectedSnapshot $case
    $lock=& $module {param($Root) Open-RimePimePublicationLock (Join-Path $Root 'installer\YIME-receipt-setup.exe') (Join-Path $Root 'installer\package-build-receipt.json')} $case.Root
    try{
        $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -WorkerCasePath "'+$worker+'" -Phase locked'
        $child=Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
        Assert-True ($child.ExitCode -eq 74) 'Independent worker did not observe the shared lock.'
    }finally{$lock.Stream.Dispose()}
    Assert-TestProtectedUnchanged $case $before 'Busy shared publication lock rejection'
    Assert-OldInstallerPreserved $case
}

Check 'cross-case-worker-root-is-rejected-before-transaction-access' {
    $caseA=New-ReplacementCase 'worker-root-case-a'
    $caseB=New-ReplacementCase 'worker-root-case-b'
    Assert-True ($caseA.Root -ine $caseB.Root) 'Worker binding fixture cases unexpectedly share one root.'
    $worker=Write-WorkerCase $caseA
    $workerValue=ConvertFrom-TestJson ([IO.File]::ReadAllText($worker))
    $workerValue.Root=[string]$caseB.Root
    [IO.File]::WriteAllText($worker,(($workerValue|ConvertTo-Json -Compress)+"`n"),[Text.UTF8Encoding]::new($false))
    $beforeA=Get-TestProtectedSnapshot $caseA
    $beforeB=Get-TestProtectedSnapshot $caseB
    $stdout=$worker+'.stdout.txt';$stderr=$worker+'.stderr.txt'
    $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -WorkerCasePath "'+$worker+'" -Phase publish'
    $child=Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $arguments `
        -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -Wait
    Assert-True ($child.ExitCode -ne 0) 'Cross-case worker root was accepted.'
    $diagnostic=''
    foreach($path in @($stdout,$stderr)){if(Test-Path -LiteralPath $path){$diagnostic+=[IO.File]::ReadAllText($path)}}
    Assert-True ($diagnostic -like '*root is not bound to its own fixture case*') 'Worker rejection did not prove same-case root binding.'
    Assert-TestProtectedUnchanged $caseA $beforeA 'Cross-case worker rejection case A'
    Assert-TestProtectedUnchanged $caseB $beforeB 'Cross-case worker rejection case B'
    Assert-OldInstallerPreserved $caseA
    Assert-OldInstallerPreserved $caseB
    Assert-RetainedStorePreserved $caseA
    Assert-RetainedStorePreserved $caseB
    Assert-ActualCheckoutPreserved $actualCheckoutBaseline 'Cross-case worker rejection'
}

$hardExitPhases=@(
    'objects','installer-copy','installer-temp','intent-copy','intent-temp','intent',
    'installer-before-move','installer','receipt','sidecar','complete'
)
foreach($stop in $hardExitPhases){
    Check ('hard-exit-'+$stop+'-converges-in-a-fresh-process') {
        $case=New-ReplacementCase ('crash-'+$stop)
        $worker=Write-WorkerCase $case
        $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -WorkerCasePath "'+$worker+'" -Phase '+$stop
        $child=Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
        Assert-True ($child.ExitCode -eq 73) ('Worker did not stop at '+$stop)
        Assert-HardExitState $case $stop $actualCheckoutBaseline
        $orphanPath=$null;$orphanBefore=$null
        if($stop -ceq 'installer-copy'){$orphanPath=(Get-TestUniqueInstallerCopies $case)[0].FullName}
        elseif($stop -in @('intent-copy','intent-temp')){$orphanPath=(Get-TestUniqueIntentCopies $case)[0].FullName}
        if($null -ne $orphanPath){$orphanBefore=(Get-TestPathObservation $orphanPath|ConvertTo-Json -Depth 8 -Compress)}
        $nextPhase=if($stop -in @('objects','installer-copy','installer-temp','intent-copy','intent-temp')){'publish'}else{'recover'}
        $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -WorkerCasePath "'+$worker+'" -Phase '+$nextPhase
        $recovery=Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
        Assert-True ($recovery.ExitCode -eq 0) ('Fresh-process convergence failed after '+$stop)
        $null=Assert-TransactionCommitted $case
        if($null -ne $orphanPath){
            Assert-True ((Get-TestPathObservation $orphanPath|ConvertTo-Json -Depth 8 -Compress) -ceq $orphanBefore) ('Fresh publish changed or adopted the pre-intent orphan after '+$stop)
            if($stop -ceq 'intent-temp'){
                $orphan=Get-TestPathObservation $orphanPath
                $completed=Get-TestPathObservation $case.Completed
                Assert-True ([string]$orphan.file_id -cne [string]$completed.file_id) 'Fresh publish adopted the old exact intent orphan instead of creating a new intent leaf.'
            }
        }
        Assert-ActualCheckoutPreserved $actualCheckoutBaseline ('fresh-process recovery after '+$stop)
        $again=Resume-RimePimeInstallerReceiptTransaction -RepoRoot $case.Root
        Assert-True ($again.Digest -ceq $case.NextDigest) ('Resume was not idempotent after '+$stop)
    }
}

Check 'foreign-completion-leaf-is-rejected-before-any-transaction-write' {
    $case=New-ReplacementCase 'foreign-completed'
    $module=Get-Module rime-pime-installer-receipt-transaction
    & $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){if($Checkpoint -ceq 'intent'){throw 'test interruption'}}}
    try{Assert-Rejected {Invoke-TestTransaction $case} '*test interruption*'}finally{& $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){}}}
    [IO.File]::WriteAllText($case.Completed,'foreign-completed',[Text.UTF8Encoding]::new($false))
    $before=Get-TestProtectedSnapshot $case
    Assert-Rejected {Resume-RimePimeInstallerReceiptTransaction $case.Root} '*already exists*'
    Assert-TestProtectedUnchanged $case $before 'Foreign completion preflight rejection'
    Assert-OldInstallerPreserved $case
    Assert-RetainedStorePreserved $case
    Assert-ActualCheckoutPreserved $actualCheckoutBaseline 'Foreign completion preflight rejection'
}

Check 'installer-no-replace-preserves-foreign-before-move-race' {
    $case=New-ReplacementCase 'move-race-foreign'
    $module=Get-Module rime-pime-installer-receipt-transaction
    & $module {
        param($Target)
        $script:InstallerRaceTarget=$Target
        function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){
            if($Checkpoint -ceq 'installer-before-move'){
                [IO.File]::WriteAllText($script:InstallerRaceTarget,'foreign-race',[Text.UTF8Encoding]::new($false))
            }
        }
    } $case.NewInstaller
    try{Assert-Rejected {Invoke-TestTransaction $case}}
    finally{& $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){}}}
    Assert-True ([IO.File]::ReadAllText($case.NewInstaller) -ceq 'foreign-race') 'No-replace move overwrote the foreign race target.'
    $null=Assert-TestNormalLeafExact $case.Stage $case.NewInstallerSha256 $case.NewInstallerBytes 'foreign-race deterministic stage'
    $null=Assert-TestIntentLeafExact $case.Pending $case 'foreign-race pending intent'
    Assert-TestCanonicalPair $case $case.Before $case.Before 'foreign-race rejection'
    Assert-TestLeafAbsent $case.Completed 'foreign-race completed record'
    Assert-OldInstallerPreserved $case
    Assert-RetainedStorePreserved $case
    Assert-ActualCheckoutPreserved $actualCheckoutBaseline 'foreign-race rejection'
}

Check 'installer-no-replace-preserves-exact-before-move-race' {
    $case=New-ReplacementCase 'move-race-exact'
    $object=Get-TestReceiptObjectPath $case.Root $case.NewInstallerSha256
    $module=Get-Module rime-pime-installer-receipt-transaction
    & $module {
        param($Source,$Target)
        $script:InstallerRaceSource=$Source;$script:InstallerRaceTarget=$Target
        function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){
            if($Checkpoint -ceq 'installer-before-move'){
                [IO.File]::Copy($script:InstallerRaceSource,$script:InstallerRaceTarget,$false)
            }
        }
    } $object $case.NewInstaller
    try{Assert-Rejected {Invoke-TestTransaction $case}}
    finally{& $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){}}}
    $null=Assert-TestNormalLeafExact $case.NewInstaller $case.NewInstallerSha256 $case.NewInstallerBytes 'exact race target'
    $null=Assert-TestNormalLeafExact $case.Stage $case.NewInstallerSha256 $case.NewInstallerBytes 'exact-race deterministic stage'
    $null=Assert-TestIntentLeafExact $case.Pending $case 'exact-race pending intent'
    Assert-TestCanonicalPair $case $case.Before $case.Before 'exact-race rejection'
    Assert-TestLeafAbsent $case.Completed 'exact-race completed record'
    Assert-OldInstallerPreserved $case
    Assert-RetainedStorePreserved $case
    Assert-ActualCheckoutPreserved $actualCheckoutBaseline 'exact-race rejection'
}

Check 'missing-preintent-stage-after-intent-is-rejected-without-writing' {
    $case=New-ReplacementCase 'missing-stage-after-intent'
    $module=Get-Module rime-pime-installer-receipt-transaction
    & $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){if($Checkpoint -ceq 'intent'){throw 'test interruption'}}}
    try{Assert-Rejected {Invoke-TestTransaction $case} '*test interruption*'}finally{& $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){}}}
    [IO.File]::Delete($case.Stage)
    $before=Get-TestProtectedSnapshot $case
    Assert-Rejected {Resume-RimePimeInstallerReceiptTransaction $case.Root} '*missing*'
    Assert-TestProtectedUnchanged $case $before 'Missing deterministic stage rejection'
    Assert-OldInstallerPreserved $case
    Assert-RetainedStorePreserved $case
    Assert-ActualCheckoutPreserved $actualCheckoutBaseline 'Missing deterministic stage rejection'
}

Check 'completion-no-replace-rename-preserves-pending-file-id' {
    $case=New-ReplacementCase 'completion-file-id'
    $module=Get-Module rime-pime-installer-receipt-transaction
    & $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){if($Checkpoint -ceq 'sidecar'){throw 'test interruption'}}}
    try{Assert-Rejected {Invoke-TestTransaction $case} '*test interruption*'}finally{& $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){}}}
    $pending=Assert-TestIntentLeafExact $case.Pending $case 'pending intent before completion rename'
    $result=Resume-RimePimeInstallerReceiptTransaction $case.Root
    Assert-True ($result.Digest -ceq $case.NextDigest) 'Completion replay returned the wrong receipt.'
    $completed=Assert-TestIntentLeafExact $case.Completed $case 'completed intent after completion rename'
    Assert-True ([string]$completed.file_id -ceq [string]$pending.file_id) 'Completion rename did not preserve the pending intent file id.'
    $null=Assert-TransactionCommitted $case
    Assert-ActualCheckoutPreserved $actualCheckoutBaseline 'Completion rename replay'
}

Check 'receipt-state-with-missing-new-installer-is-rejected-without-writing' {
    $case=New-ReplacementCase 'missing-new-after-receipt'
    $module=Get-Module rime-pime-installer-receipt-transaction
    & $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){if($Checkpoint -ceq 'receipt'){throw 'test interruption'}}}
    try{Assert-Rejected {Invoke-TestTransaction $case} '*test interruption*'}finally{& $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){}}}
    [IO.File]::Delete($case.NewInstaller)
    $before=Get-TestProtectedSnapshot $case
    Assert-Rejected {Resume-RimePimeInstallerReceiptTransaction $case.Root} '*without the exact physical new installer*'
    Assert-TestProtectedUnchanged $case $before 'Missing new installer rejection'
    Assert-OldInstallerPreserved $case
}

Check 'old-receipt-with-new-sidecar-is-rejected-without-writing' {
    $case=New-ReplacementCase 'old-new-marker'
    $module=Get-Module rime-pime-installer-receipt-transaction
    & $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){if($Checkpoint -ceq 'intent'){throw 'test interruption'}}}
    try{Assert-Rejected {Invoke-TestTransaction $case} '*test interruption*'}finally{& $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){}}}
    [IO.File]::WriteAllText($case.Canonical+'.sha256',($case.NextDigest+'  package-build-receipt.json'+"`n"),[Text.Encoding]::ASCII)
    $before=Get-TestProtectedSnapshot $case
    Assert-Rejected {Resume-RimePimeInstallerReceiptTransaction $case.Root} '*outside the allowed*'
    Assert-TestProtectedUnchanged $case $before 'Old-receipt/new-sidecar rejection'
    Assert-OldInstallerPreserved $case
}

Check 'foreign-canonical-receipt-after-intent-is-rejected-and-preserved' {
    $case=New-ReplacementCase 'foreign-canonical'
    $module=Get-Module rime-pime-installer-receipt-transaction
    & $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){if($Checkpoint -ceq 'intent'){throw 'test interruption'}}}
    try{Assert-Rejected {Invoke-TestTransaction $case} '*test interruption*'}finally{& $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){}}}
    [IO.File]::WriteAllText($case.Canonical,'foreign receipt',[Text.UTF8Encoding]::new($false))
    $before=Get-TestProtectedSnapshot $case
    Assert-Rejected {Resume-RimePimeInstallerReceiptTransaction $case.Root}
    Assert-TestProtectedUnchanged $case $before 'Foreign canonical receipt rejection'
    Assert-OldInstallerPreserved $case
}

Check 'foreign-new-installer-after-intent-is-rejected-and-preserved' {
    $case=New-ReplacementCase 'foreign-new-after-intent'
    $module=Get-Module rime-pime-installer-receipt-transaction
    & $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){if($Checkpoint -ceq 'intent'){throw 'test interruption'}}}
    try{Assert-Rejected {Invoke-TestTransaction $case} '*test interruption*'}finally{& $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){}}}
    [IO.File]::WriteAllText($case.NewInstaller,'foreign-after-intent',[Text.UTF8Encoding]::new($false))
    $before=Get-TestProtectedSnapshot $case
    Assert-Rejected {Resume-RimePimeInstallerReceiptTransaction $case.Root} '*new physical installer*'
    Assert-TestProtectedUnchanged $case $before 'Foreign post-intent new installer rejection'
    Assert-OldInstallerPreserved $case
}

Check 'exact-new-installer-after-intent-is-an-idempotent-recovery-state' {
    $case=New-ReplacementCase 'exact-new-after-intent'
    $module=Get-Module rime-pime-installer-receipt-transaction
    & $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){if($Checkpoint -ceq 'installer'){throw 'test interruption'}}}
    try{Assert-Rejected {Invoke-TestTransaction $case} '*test interruption*'}finally{& $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){}}}
    $null=Assert-TestNormalLeafExact $case.NewInstaller $case.NewInstallerSha256 $case.NewInstallerBytes 'post-intent new installer'
    Assert-TestLeafAbsent $case.Stage 'post-intent deterministic stage'
    $result=Resume-RimePimeInstallerReceiptTransaction $case.Root
    Assert-True ($result.Digest -ceq $case.NextDigest) 'Exact post-intent new leaf did not converge.'
    $null=Assert-TransactionCommitted $case
}

Check 'foreign-staged-installer-after-intent-is-rejected-and-preserved' {
    $case=New-ReplacementCase 'foreign-stage'
    $module=Get-Module rime-pime-installer-receipt-transaction
    & $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){if($Checkpoint -ceq 'intent'){throw 'test interruption'}}}
    try{Assert-Rejected {Invoke-TestTransaction $case} '*test interruption*'}finally{& $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){}}}
    $pending=Join-Path $case.Root 'installer\receipt-evidence\pending.json'
    $intent=ConvertFrom-TestJson ([IO.File]::ReadAllText($pending))
    $stage=Join-Path (Split-Path -Parent $case.NewInstaller) ('.rime-pime-installer-'+[string]$intent.operation_id+'.staged')
    [IO.File]::WriteAllText($stage,'foreign-stage',[Text.UTF8Encoding]::new($false));$foreign=Hash $stage
    $before=Get-TestProtectedSnapshot $case
    Assert-Rejected {Resume-RimePimeInstallerReceiptTransaction $case.Root} '*staged new installer*'
    Assert-TestProtectedUnchanged $case $before 'Foreign deterministic stage rejection'
    Assert-OldInstallerPreserved $case
}

$intentFaults=@('operation-array','byte-string','extra-property')
foreach($fault in $intentFaults){
    Check ('strict-intent-rejects-'+$fault+'-without-writing') {
        $case=New-ReplacementCase ('intent-'+$fault)
        $module=Get-Module rime-pime-installer-receipt-transaction
        & $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){if($Checkpoint -ceq 'intent'){throw 'test interruption'}}}
        try{Assert-Rejected {Invoke-TestTransaction $case} '*test interruption*'}finally{& $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){}}}
        $pending=Join-Path $case.Root 'installer\receipt-evidence\pending.json'
        $intent=ConvertFrom-TestJson ([IO.File]::ReadAllText($pending))
        if($fault -ceq 'operation-array'){$intent.operation_id=@([string]$intent.operation_id)}
        elseif($fault -ceq 'byte-string'){$intent.new_installer_bytes=[string]$intent.new_installer_bytes}
        else{$intent|Add-Member -NotePropertyName unreviewed -NotePropertyValue $true}
        [IO.File]::WriteAllText($pending,($intent|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
        $before=Get-TestProtectedSnapshot $case
        Assert-Rejected {Resume-RimePimeInstallerReceiptTransaction $case.Root}
        Assert-TestProtectedUnchanged $case $before 'Strict intent rejection'
        Assert-OldInstallerPreserved $case
    }
}

Check 'dp1n-pending-blocks-receipt-only-publication' {
    $case=New-ReplacementCase 'blocks-receipt-only'
    $module=Get-Module rime-pime-installer-receipt-transaction
    & $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){if($Checkpoint -ceq 'intent'){throw 'test interruption'}}}
    try{Assert-Rejected {Invoke-TestTransaction $case} '*test interruption*'}finally{& $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){}}}
    $before=Get-TestProtectedSnapshot $case
    Assert-Rejected {Publish-RimePimePackageReceiptV2Supersession $case.Root $case.Canonical $case.Before} '*explicit recovery*'
    Assert-TestProtectedUnchanged $case $before 'Receipt-only publisher blocked by DP1-N pending intent'
    Assert-OldInstallerPreserved $case
}

Check 'dp1n-pending-is-rejected-by-receipt-only-resume-without-writing' {
    $case=New-ReplacementCase 'blocks-receipt-only-resume'
    $module=Get-Module rime-pime-installer-receipt-transaction
    & $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){if($Checkpoint -ceq 'intent'){throw 'test interruption'}}}
    try{Assert-Rejected {Invoke-TestTransaction $case} '*test interruption*'}finally{& $module {function script:Invoke-RimePimeInstallerReceiptTransactionCheckpoint($Checkpoint){}}}
    $before=Get-TestProtectedSnapshot $case
    Assert-Rejected {Resume-RimePimePackageReceiptV2Publication $case.Root} '*receipt publication intent*'
    Assert-TestProtectedUnchanged $case $before 'Receipt-only Resume rejection of DP1-N pending intent'
    Assert-OldInstallerPreserved $case
    Assert-RetainedStorePreserved $case
    Assert-ActualCheckoutPreserved $actualCheckoutBaseline 'Receipt-only Resume rejection of DP1-N pending intent'
}

Check 'receipt-only-pending-is-rejected-by-dp1n-resume' {
    $case=New-ReplacementCase 'receipt-pending-blocks-dp1n'
    $receiptModule=Get-Module rime-pime-package-receipt-v2
    & $receiptModule {
        param($Root,$Digest)
        $pending=Join-Path $Root 'installer\receipt-evidence\pending.json'
        $intent=[ordered]@{
            schema_version='yime-rime-pime-retained-publication-v1';previous=$Digest
            previous_retained=$Digest;next=$Digest;installer_path='installer/YIME-1.0-old-setup.exe'
        }
        Write-RimePimeReceiptAtomicBytes $pending ([Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-RimePimeStageCanonicalJson $intent)+"`n"))
    } $case.Root $case.Before
    $before=Get-TestProtectedSnapshot $case
    Assert-Rejected {Resume-RimePimeInstallerReceiptTransaction $case.Root}
    Assert-TestProtectedUnchanged $case $before 'DP1-N Resume rejection of receipt-only pending intent'
    Assert-OldInstallerPreserved $case
}

Check 'actual-checkout-root-is-rejected-before-any-transaction-access' {
    $before=Get-ActualCheckoutSnapshot
    Assert-Rejected {Publish-RimePimeInstallerReceiptTransaction $repo ('0'*64) ('1'*64)} '*allowed only in fresh*'
    Assert-ActualCheckoutPreserved $before 'Actual checkout fixture-gate rejection'
}

$hardExitCheckNames=@($hardExitPhases|ForEach-Object{'hard-exit-'+$_+'-converges-in-a-fresh-process'})
$intentFaultCheckNames=@($intentFaults|ForEach-Object{'strict-intent-rejects-'+$_+'-without-writing'})
$noWriteCheckNames=@(
    'stale-expected-current-receipt-is-rejected-before-intent',
    'same-installer-path-is-rejected-before-intent',
    'preexisting-exact-new-installer-is-rejected-before-intent',
    'preexisting-foreign-new-installer-is-rejected-and-preserved',
    'foreign-old-installer-is-rejected-and-preserved',
    'hardlinked-new-installer-is-rejected-after-intent-state',
    'alternate-data-stream-on-new-installer-is-rejected-after-intent-state',
    'directory-reparse-occupancy-is-rejected-after-intent-state',
    'shared-publication-lock-blocks-an-independent-process',
    'cross-case-worker-root-is-rejected-before-transaction-access',
    'foreign-completion-leaf-is-rejected-before-any-transaction-write',
    'missing-preintent-stage-after-intent-is-rejected-without-writing',
    'receipt-state-with-missing-new-installer-is-rejected-without-writing',
    'old-receipt-with-new-sidecar-is-rejected-without-writing',
    'foreign-canonical-receipt-after-intent-is-rejected-and-preserved',
    'foreign-new-installer-after-intent-is-rejected-and-preserved',
    'foreign-staged-installer-after-intent-is-rejected-and-preserved',
    'dp1n-pending-blocks-receipt-only-publication',
    'dp1n-pending-is-rejected-by-receipt-only-resume-without-writing',
    'receipt-only-pending-is-rejected-by-dp1n-resume',
    'actual-checkout-root-is-rejected-before-any-transaction-access'
) + $intentFaultCheckNames
$expectedCheckNames=@(
    'module-exports-only-two-isolated-transaction-apis',
    'absent-checkout-receipt-pair-is-observed-without-creating-files',
    'present-checkout-receipt-pair-keeps-native-identity-and-detects-content-change',
    'two-generations-pass-the-real-strict-reader-at-one-absolute-fixture-root',
    'clean-installer-and-receipt-identity-replacement-rolls-forward',
    'non-durable-old-clean-publish-binds-distinct-retention-and-history',
    'non-durable-old-intent-hard-exit-resumes-in-fresh-process',
    'stale-expected-current-receipt-is-rejected-before-intent',
    'same-installer-path-is-rejected-before-intent',
    'preexisting-exact-new-installer-is-rejected-before-intent',
    'preexisting-foreign-new-installer-is-rejected-and-preserved',
    'foreign-old-installer-is-rejected-and-preserved',
    'hardlinked-new-installer-is-rejected-after-intent-state',
    'alternate-data-stream-on-new-installer-is-rejected-after-intent-state',
    'directory-reparse-occupancy-is-rejected-after-intent-state',
    'shared-publication-lock-blocks-an-independent-process',
    'cross-case-worker-root-is-rejected-before-transaction-access',
    'foreign-completion-leaf-is-rejected-before-any-transaction-write',
    'installer-no-replace-preserves-foreign-before-move-race',
    'installer-no-replace-preserves-exact-before-move-race',
    'missing-preintent-stage-after-intent-is-rejected-without-writing',
    'completion-no-replace-rename-preserves-pending-file-id',
    'receipt-state-with-missing-new-installer-is-rejected-without-writing',
    'old-receipt-with-new-sidecar-is-rejected-without-writing',
    'foreign-canonical-receipt-after-intent-is-rejected-and-preserved',
    'foreign-new-installer-after-intent-is-rejected-and-preserved',
    'exact-new-installer-after-intent-is-an-idempotent-recovery-state',
    'foreign-staged-installer-after-intent-is-rejected-and-preserved',
    'dp1n-pending-blocks-receipt-only-publication',
    'dp1n-pending-is-rejected-by-receipt-only-resume-without-writing',
    'receipt-only-pending-is-rejected-by-dp1n-resume',
    'actual-checkout-root-is-rejected-before-any-transaction-access',
    'declared-transaction-check-name-set-is-exact'
) + $hardExitCheckNames + $intentFaultCheckNames

Check 'declared-transaction-check-name-set-is-exact' {
    $expected=@($expectedCheckNames|Sort-Object)
    $actual=@($declaredChecks|Sort-Object)
    Assert-True (($actual -join "`n") -ceq ($expected -join "`n")) `
        ('Declared transaction checks differ from the reviewed exact set. Expected '+$expected.Count+', got '+$actual.Count+'.')
}

function Test-NamedChecksPassed([string[]]$Names){
    foreach($name in $Names){
        $matches=@($checks|Where-Object{[string]$_.name -ceq $name})
        if($matches.Count -ne 1 -or -not [bool]($matches[0].passed)){return $false}
    }
    return $true
}

$failed=@($checks|Where-Object{-not $_.passed})
if($checks.Count -eq 0){throw 'No checks selected.'}
$selectedNames=@($checks|ForEach-Object{[string]$_.name}|Sort-Object)
$expectedNames=@($expectedCheckNames|Sort-Object)
$fullSuiteExecuted=(($selectedNames -join "`n") -ceq ($expectedNames -join "`n"))
$allChecksPassed=($failed.Count -eq 0)
$fullMatrixVerified=($fullSuiteExecuted -and $allChecksPassed)
$preIntentHardExitNames=@(
    'objects','installer-copy','installer-temp','intent-copy','intent-temp'
)|ForEach-Object{'hard-exit-'+$_+'-converges-in-a-fresh-process'}
$postIntentHardExitNames=@(
    'intent','installer-before-move','installer','receipt','sidecar','complete'
)|ForEach-Object{'hard-exit-'+$_+'-converges-in-a-fresh-process'}
$result=[ordered]@{
    schema_version='yime-rime-pime-installer-receipt-transaction-test-v1'
    total=$checks.Count;passed=$checks.Count-$failed.Count;failed=$failed.Count;checks=@($checks)
    fixture_case_directories=@($caseDirectories)
    selected_check_pattern=$CheckPattern
    expected_check_count=$expectedCheckNames.Count
    full_suite_executed=[bool]$fullSuiteExecuted
    all_executed_checks_passed=[bool]$allChecksPassed
    verified=[ordered]@{
        full_transaction_matrix=[bool]$fullMatrixVerified
        same_root_two_generation_strict_reader=(Test-NamedChecksPassed @('two-generations-pass-the-real-strict-reader-at-one-absolute-fixture-root'))
        non_durable_old_retention_conversion_and_recovery=(Test-NamedChecksPassed @(
            'non-durable-old-clean-publish-binds-distinct-retention-and-history',
            'non-durable-old-intent-hard-exit-resumes-in-fresh-process'))
        pre_intent_fresh_publish_recovery=(Test-NamedChecksPassed $preIntentHardExitNames)
        post_intent_fresh_process_roll_forward=([bool]$fullMatrixVerified -and
            (Test-NamedChecksPassed ($postIntentHardExitNames+@(
                'non-durable-old-intent-hard-exit-resumes-in-fresh-process'))))
        hard_exit_checkpoint_state_matrix=(Test-NamedChecksPassed $hardExitCheckNames)
        illegal_state_protected_set_unchanged=(Test-NamedChecksPassed $noWriteCheckNames)
        installer_target_no_replace_races=(Test-NamedChecksPassed @(
            'installer-no-replace-preserves-foreign-before-move-race',
            'installer-no-replace-preserves-exact-before-move-race'))
        completion_rename_file_id=(Test-NamedChecksPassed @('completion-no-replace-rename-preserves-pending-file-id'))
        old_installer_preserved=[bool]$fullMatrixVerified
        actual_checkout_canonical_pair_unchanged=([bool]$fullMatrixVerified -and
            (Test-NamedChecksPassed @('actual-checkout-root-is-rejected-before-any-transaction-access')))
    }
    scope_declarations=[ordered]@{
        fixture_only=$true
        transaction_policy='fresh publish before intent; roll-forward after durable intent; no rollback path'
        invoked_process_class='PowerShell test workers only'
        installed_product_actions_out_of_scope=$true
        registry_and_default_input_method_actions_out_of_scope=$true
        production_user_data_actions_out_of_scope=$true
    }
    limitations=[ordered]@{
        hardware_power_loss_verified=$false
        directory_metadata_durability_verified=$false
        active_same_sid_physical_replacement_prevention_verified=$false
    }
}
$resultPath=Join-Path $output 'transaction-result.json'
[IO.File]::WriteAllText($resultPath,($result|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
if($failed.Count){$failed|Format-Table -AutoSize|Out-String|Write-Host;throw "Installer/receipt transaction checks failed: $resultPath"}
Write-Host "PASS: $($checks.Count) isolated installer/receipt transaction checks. $resultPath"
