#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'native-core-benchmark.psm1'
$tokens = $null; $errors = $null
$null = [Management.Automation.Language.Parser]::ParseFile($modulePath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$module = Import-Module $modulePath -Force -PassThru
$root = Join-Path ([IO.Path]::GetTempPath()) ('yimecore-native-contract-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $root
try {
    & $module {
        param($Root)
        $script:checks = 0
        function Check([bool]$Condition, [string]$Name) {
            if (-not $Condition) { throw "FAIL: $Name" }; $script:checks++
        }
        function Reject([scriptblock]$Operation, [string]$Name) {
            $rejected = $false
            try { & $Operation | Out-Null } catch { $rejected = $true }
            Check $rejected $Name
        }
        foreach ($relative in @('../escape', '..\escape', 'a/../escape', '/absolute', 'C:\absolute', 'a:b', 'a//b', 'a./b', 'a /b')) {
            Reject { Resolve-NBChild $Root $relative } "relative path $relative"
        }
        Check ((Resolve-NBChild $Root 'a/b.txt').StartsWith($Root)) 'ordinary child'
        Reject { Assert-NBLocalRoot '\\server\share\bench' } 'network output rejected'
        $gitRoot = Join-Path $Root 'repo'; $null = New-Item -ItemType Directory -Path (Join-Path $gitRoot '.git') -Force
        Reject { Assert-NBLocalRoot (Join-Path $gitRoot 'inside') } 'output under git rejected'
        $plain = Join-Path $Root 'plain'; $null = New-Item -ItemType Directory -Path $plain
        [IO.File]::WriteAllText((Join-Path $plain 'file.txt'), 'original')
        $records = @(Get-NBFileRecord $plain 'file.txt')
        Assert-NBRecords $plain $records; Check $true 'original hash verified'
        [IO.File]::WriteAllText((Join-Path $plain 'file.txt'), 'modified')
        Reject { Assert-NBRecords $plain $records } 'same-length modification detected'
        Reject { Assert-NBNames @('one') @('one', 'new') } 'new source detected'
        Reject { Assert-NBNames @('one', 'old') @('one') } 'deleted source detected'
        $junction = Join-Path $Root 'junction'
        $null = New-Item -ItemType Junction -Path $junction -Target $plain
        Reject { Get-NBFileNames $junction } 'junction root rejected'
        Reject { Resolve-NBChild $Root 'junction/file.txt' } 'junction ancestor rejected'
        [IO.Directory]::Delete($junction)

        $facts = @{ native_architecture=9; process_64bit=$true; cpu='Intel(R) Core(TM) i7-7820X CPU @ 3.60GHz';
            cores=8; logical_processors=16; process_affinity=65535; process_priority='Normal'; os_visible_memory_bytes=[uint64](95.6GB) }
        Assert-NBHostFacts $facts 'baseline'; Check $true 'identified physical host'
        $facts.cpu='Intel i9-13900K'; Reject { Assert-NBHostFacts $facts 'baseline' } 'old development cpu rejected'
        $facts.cpu='Intel i7-7820X'; $facts.native_architecture=12
        Reject { Assert-NBHostFacts $facts 'baseline' } 'ARM64 emulation not x64 evidence'
        $facts.native_architecture=9; $facts.process_64bit=$false
        Reject { Assert-NBHostFacts $facts 'baseline' } '32-bit shell rejected'
        $facts.process_64bit=$true; $facts.process_affinity=1
        Reject { Assert-NBHostFacts $facts 'baseline' } 'inherited affinity detected'
        $facts.process_affinity=65535
        Reject { Assert-NBHostFacts $facts 'os16gb' } '96GB cannot be labelled 16GB'
        $facts.os_visible_memory_bytes=[uint64](15.7GB)
        Assert-NBHostFacts $facts 'os16gb'; Check $true 'observed 16GB profile'
        Reject { Assert-NBHostFacts $facts 'invented' } 'unknown memory profile'

        $q = [pscustomobject]@{mode='full'; iterations=1000; probe_count=9; passed=$true;
            latency=[pscustomobject]@{samples=100;batch_size=10;p95_ns=2000000;p99_ns=3000000};
            process_memory=[pscustomobject]@{private_bytes=100MB}}
        Check (Get-NBQueryRow $q 0 'e1' 'full' 1000 50 1GB).passed 'complete query evidence'
        Check (-not (Get-NBQueryRow $q 7 'e1' 'full' 1000 50 1GB).passed) 'nonzero exit overrides passed JSON'
        $q.passed='false'; Reject { Get-NBQueryRow $q 0 'e1' 'full' 1000 50 1GB } 'string boolean rejected'
        $q.passed=$true; $q.latency.samples=99
        Reject { Get-NBQueryRow $q 0 'e1' 'full' 1000 50 1GB } 'partial samples rejected'
        $q.latency.samples=100; $q.latency.p95_ns=60000000
        Check (-not (Get-NBQueryRow $q 0 'e1' 'full' 1000 50 1GB).passed) 'query latency budget retained'
        $q.latency.p95_ns=2000000; $q.process_memory.private_bytes=2GB
        Check (-not (Get-NBQueryRow $q 0 'e1' 'full' 1000 50 1GB).passed) 'private memory budget retained'
        $learn = [pscustomobject]@{mode='full';promotion_passed=$true;persistence_passed=$true;context_passed=$true;
            forget_passed=$true;latency_gate_passed=$true;passed=$true;
            static_latency=[pscustomobject]@{samples=100;batch_size=5000;p95_ns=1000;p99_ns=1000};
            learned_latency=[pscustomobject]@{samples=100;batch_size=5000;p95_ns=1050;p99_ns=1100}}
        Check (Get-NBLearningRow $learn 0 'full' 100 1.10 1.20).passed 'complete learning evidence'
        $learn.learned_latency.p95_ns=1200
        Check (-not (Get-NBLearningRow $learn 0 'full' 100 1.10 1.20).passed) 'learning ratio recomputed'
        $learn.learned_latency.p95_ns=1050
        Check (-not (Get-NBLearningRow $learn 1 'full' 100 1.10 1.20).passed) 'learning exit code retained'

        $pe = Join-Path $Root 'fixture.exe'; $bytes = New-Object byte[] 128
        $bytes[0]=0x4d; $bytes[1]=0x5a; $bytes[0x3c]=0x40; $bytes[0x40]=0x50; $bytes[0x41]=0x45
        $bytes[0x44]=0x64; $bytes[0x45]=0x86
        [IO.File]::WriteAllBytes($pe,$bytes); Assert-NBPE $pe; Check $true 'x64 PE machine'
        $bytes[0x44]=0x64; $bytes[0x45]=0xaa; [IO.File]::WriteAllBytes($pe,$bytes)
        Reject { Assert-NBPE $pe } 'ARM64 PE rejected'
        $bytes[0x3c]=0xff; [IO.File]::WriteAllBytes($pe,$bytes)
        Reject { Assert-NBPE $pe } 'invalid PE offset rejected'
        $pkg=Join-Path $Root 'package'; $null=New-Item -ItemType Directory -Path $pkg
        $requiredPackage=@('native-core-benchmark.psm1','support/native-maintenance-evidence.psm1','performance-tiers.json',
            'source-state.json','bin/yimecore-index-bench.exe','bin/yimecore-learning-experiment.exe',
            'indexes/full.yidx','indexes/variable.yidx','indexes/shorthand.yidx','probes/e1_probes.json','probes/e2_sentence_probes.json')
        foreach($name in $requiredPackage){$p=Resolve-NBChild $pkg $name;$null=New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p);[IO.File]::WriteAllText($p,'fixture')}
        Copy-Item -LiteralPath $script:NBModulePath -Destination (Join-Path $pkg 'native-core-benchmark.psm1')
        $bytes[0x3c]=0x40; $bytes[0x44]=0x64; $bytes[0x45]=0x86
        foreach($name in @('yimecore-index-bench','yimecore-learning-experiment')){[IO.File]::WriteAllBytes((Join-Path $pkg "bin/$name.exe"),$bytes)}
        $inventory=@(Get-NBFileNames $pkg|ForEach-Object{Get-NBFileRecord $pkg $_})
        $m=[ordered]@{schema_version='yimecore-native-core-benchmark-v1';target='mainstream_x64';cpu_model='i7-7820X';installable=$false;build_passed=$true;files=$inventory}
        $mp=Join-Path $pkg 'package-manifest.json'; Write-NBJson $m $mp; $mh=Get-NBDigest $mp
        $null=Assert-NBPackage $pkg $mh; Check $true 'fixed fixture package verified without execution'
        [IO.File]::AppendAllText((Join-Path $pkg 'indexes/full.yidx'),'changed')
        Reject { Assert-NBPackage $pkg $mh } 'package input tampering detected'
        [IO.File]::WriteAllText((Join-Path $pkg 'indexes/full.yidx'),'fixture')
        $m.build_passed=$false; Write-NBJson $m $mp
        Reject { Assert-NBPackage $pkg $mh } 'manifest hash change detected'
        Reject { Assert-NBPackage $pkg (Get-NBDigest $mp) } 'incomplete build never accepted'
        $code=Invoke-NBTool $env:ComSpec @('/d','/c','exit','7') (Join-Path $Root 'exit.log')
        Check ($code -eq 7) 'native process exit propagation'

        # Exercise real git reads and snapshotting, including dirty and new Go files.
        $source=Join-Path $Root 'source'; $snap=Join-Path $Root 'snapshot'
        $null=New-Item -ItemType Directory -Path $source,$snap
        & git -C $source init --quiet
        if($LASTEXITCODE -ne 0){throw 'Fixture git init failed'}
        $required=@('go-backend/go.mod','AGENTS.md','tools/yimecore/development-scope.json',
            'tools/yimecore/performance-tiers.json','tools/yimecore/native-maintenance-evidence.psm1',
            'go-backend/input_methods/yime/data/yime_full.dict.yaml','go-backend/input_methods/yime/data/yime_variable.dict.yaml',
            'go-backend/input_methods/yime/data/yime_shorthand.dict.yaml',
            'go-backend/input_methods/yime/yimecore/testdata/e1_probes.json',
            'go-backend/input_methods/yime/yimecore/testdata/e2_sentence_probes.json','go-backend/example.go')
        foreach($name in $required){$p=Resolve-NBChild $source $name;$null=New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p);[IO.File]::WriteAllText($p,'fixture')}
        & git -C $source add --all
        if($LASTEXITCODE -ne 0){throw 'Fixture git add failed'}
        & git -C $source -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false commit --quiet -m fixture
        if($LASTEXITCODE -ne 0){throw 'Fixture git commit failed'}
        [IO.File]::WriteAllText((Join-Path $source 'go-backend/example.go'),'edited')
        [IO.File]::WriteAllText((Join-Path $source 'go-backend/new.go'),'new Go source')
        [IO.File]::WriteAllText((Join-Path $source 'go-backend/old.exe'),'historical payload')
        $state=Copy-NBSourceSnapshot $source $snap
        Check $state.git_dirty 'dirty working tree recorded'
        Check (@($state.files.path) -contains 'go-backend/new.go') 'untracked Go source included'
        Check (-not(Test-Path -LiteralPath (Join-Path $snap 'go-backend/old.exe'))) 'historical executable not copied'
        Check ([IO.File]::ReadAllText((Join-Path $snap 'go-backend/example.go')) -ceq 'edited') 'working bytes copied rather than HEAD'
        $savedHead=$state.git_commit
        $savedHash=Get-NBDigest (Join-Path $source 'go-backend/example.go')
        $null=Copy-NBSourceSnapshot $source (Join-Path $Root 'snapshot-again')
        Check ((@(Invoke-NBGit $source @('rev-parse','HEAD')) -join '').Trim() -ceq $savedHead) 'source HEAD preserved'
        Check ((Get-NBDigest (Join-Path $source 'go-backend/example.go')) -ceq $savedHash) 'source bytes preserved'
        $script:mutateSnapshotFile=Join-Path $source 'go-backend/example.go'
        $script:injectSnapshotEdit=$true
        function script:Copy-Item {
            param([string]$LiteralPath,[string]$Destination)
            Microsoft.PowerShell.Management\Copy-Item -LiteralPath $LiteralPath -Destination $Destination
            if($script:injectSnapshotEdit){$script:injectSnapshotEdit=$false;[IO.File]::AppendAllText($script:mutateSnapshotFile,'concurrent change')}
        }
        try { Reject { Copy-NBSourceSnapshot $source (Join-Path $Root 'racing-snapshot') } 'concurrent source edit rejects snapshot' }
        finally { Remove-Item Function:script:Copy-Item }
        Write-Host "PASS: $script:checks native benchmark contracts; fixture evidence only, no physical acceptance."
    } $root
} finally {
    Remove-Module $module
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
