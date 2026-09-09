# i7-7820X physical core benchmark

Affected product: YimeCore. This is a separate, core-only experiment for the
user-identified physical x64 PC. The existing MYCOMPUTER build/install lane and
its guards remain intact. This package cannot be installed as an input method.

## Confirmed setup

User-reported hardware: Intel i7-7820X, 8 cores / 16 logical processors, 96 GB
installed RAM, Windows 11 Home 10.0.26300 x64. `C:` is the Samsung 980 1 TB SSD;
the reported free space was 720.5 GiB. The Intel 256 GB SSD is `D:` and the USB
device is `E:`. The test root is `C:\YimeBench`.

The canonical source remains `Z:\`, mapped to `\\192.168.1.21\Yime`. The test PC
is `192.168.3.35`. At the source check, HEAD was
`d5d0670473ef6df540dd10f00e37a2b2c4da6c9d`; four tracked CI/dual-product files
were modified and two dual-product helper files were untracked. This is a
historical observation, not an assertion about later working-tree contents.
`go1.27.1 windows/amd64` was subsequently reported on the test PC. `amd64` is
Go's x86-64 architecture name and applies to this Intel CPU.

## Prepare once, measure independently

Use a normal-priority, 64-bit PowerShell on the test PC. Import the reviewed
module from a fixed revision, then prepare a fresh package:

```powershell
Import-Module 'C:\YimeBench\tools\native-core-benchmark.psm1' -Force
$package = New-YimeCoreNativeBenchmark -SourceRoot 'Z:\' -BenchmarkRoot 'C:\YimeBench'
$package | Format-List
```

During the initial copy/hash phase, coordinate source edits with the development
machine. The module captures actual selected working files, including modified
and untracked Go source, rather than exporting only HEAD. It checks source and
copied bytes, file membership, HEAD and Git status again before proceeding.
This detects observed concurrent changes; it is not an atomic filesystem
snapshot. Any failure preserves the preparation directory for inspection.

After `Source snapshot verified`, development can continue. Compilation, Go
tests, generated indexes and caches then use only the local snapshot. No Git
write, source clean/reset, installed-binary reuse, source-repository cache or
network dependency download is performed. The package records its complete
file hashes, source hashes, actual Go version and `GOAMD64=v1`. It also uses the
existing independent 32/64-bit system-registry evidence module before and after
preparation and measurement; provider or preservation failures fail the run.

Once compilation/index generation has finished and the test PC is idle, run:

```powershell
Import-Module (Join-Path $package.PackageRoot 'native-core-benchmark.psm1') -Force
Invoke-YimeCoreNativeBenchmark -PackageRoot $package.PackageRoot -ManifestSHA256 $package.ManifestSHA256
```

The preparation directory retains `receipt.json` with the exact package path
and manifest hash. In a new PowerShell session, restore `$package` from that
specific receipt with `Get-Content -Raw ... | ConvertFrom-Json`. Measurements
read no shared files and require neither Git nor Go. Each run writes a new
`C:\YimeBench\results\...\summary.json`; synthetic learning state is kept there.
Never interpret package preparation alone as a passed performance run.

## Coverage and interpretation

The package invokes the existing core tools for E1, E2 and E3 in full, variable
and shorthand modes. E1/E2 default to 1000 full-set iterations (100 batch
samples), retaining the provisional 50/100 ms p95 budgets and 1024 MiB private
memory budget from the snapshot's mainstream profile. E3 uses 100 interleaved
samples of 5000 replays and retains the 1.10 p95 / 1.20 p99 overhead limits.
Native exit status, report completeness, all nine rows, immutable package
verification and protected registration checks contribute to the final gate.

These are batch-amortized core probe-set latencies, not per-key or end-to-end
input latency. Private memory is a post-workload snapshot, not a measured peak.
Index-open time is not a controlled cold-boot measurement. This does not test
Rime comparison, Broker IPC, registered TSF surfaces, installed desktop hosts
or general compatibility across all mainstream x64 machines. Those acceptance
fields remain null; release readiness remains false.

## Subsequent memory runs

First use the existing 96 GB configuration (`baseline`). The runner changes no
CPU quota, affinity, power plan, priority, boot configuration or OS memory limit.
It rejects a reduced inherited affinity or changed process priority and records
the actual CPU, OS-visible RAM, disk information and power plan.

After a separately configured and verified Windows memory limit, reuse the
same package and manifest hash with `-MemoryProfile os32gb` or `os16gb`. These
labels are accepted only when observed OS-visible memory falls in 30–33 or
14–17 GiB respectively. A memory label is not a memory limiter. Reducing visible
RAM does not reproduce another CPU/cache, DIMM/channel arrangement or SSD.
