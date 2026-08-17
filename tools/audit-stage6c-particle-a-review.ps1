[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$temporaryRoot = Join-Path $repoRoot '.tmp'
$runnerDir = Join-Path $temporaryRoot 'particle-a-stage6c-runner'
$runnerPath = Join-Path $runnerDir 'main.go'
$goCache = Join-Path $temporaryRoot 'go-particle-a-stage6c-cache'
$goCommand = Get-Command go -ErrorAction Stop
[IO.Directory]::CreateDirectory($runnerDir) | Out-Null
[IO.Directory]::CreateDirectory($goCache) | Out-Null
$runnerSource = @'
package main
import (
    "flag"
    "fmt"
    "os"
    "github.com/tsaanghwang/Yime/go-backend/input_methods/yime/connectedspeech"
)
func main() {
    repo := flag.String("repo", "", "repository root"); flag.Parse()
    result, err := connectedspeech.RunParticleAStage6CReview(connectedspeech.DefaultParticleAStage6CConfig(*repo))
    if err != nil { fmt.Fprintln(os.Stderr, err); os.Exit(1) }
    fmt.Printf("Particle-a Stage 6C review: complete\nreview=%d matched=%d pending=%d semantic_only=%d key_changing=%d unresolved=%d runtime_aliases=%d passed=%t\n",
        result.Summary.ReviewCount, result.Summary.MatchedCount, result.Summary.PendingCount, result.Summary.SemanticOnlyCount,
        result.Summary.KeyChangingCount, result.Summary.UnresolvedCount, result.Summary.RuntimeAliasesGenerated, result.Summary.Passed)
}
'@
[IO.File]::WriteAllText($runnerPath, $runnerSource, [Text.UTF8Encoding]::new($false))
$oldGoCache = $env:GOCACHE; $exitCode = 1
Push-Location (Join-Path $repoRoot 'go-backend')
try { $env:GOCACHE = $goCache; & $goCommand.Source run $runnerPath -repo $repoRoot; $exitCode = $LASTEXITCODE }
finally { $env:GOCACHE = $oldGoCache; Pop-Location; if ([IO.Directory]::Exists($runnerDir)) { [IO.Directory]::Delete($runnerDir, $true) } }
if ($exitCode -ne 0) { throw "Particle-a Stage 6C review failed with exit code $exitCode" }
Write-Host "Report directory: $(Join-Path $temporaryRoot 'particle-a-stage6c-review')"
