# i7-7820X native core benchmark result (2026-09-09)

Affected product: YimeCore core only. This report publishes the evidence produced
on the user-identified physical test PC named `计算机`. It does not replace the
separate installed-product and reboot acceptance performed later.

## Outcome

The test PC completed two baseline runs from the same immutable package. In both
runs all E1 and E2 rows passed correctness, latency and memory gates. The overall
native core gate did **not** pass because the E3 learned/static overhead gate was
not met consistently. Package integrity and protected production registration
were unchanged in both runs.

The follow-up CPU profile completed for all three modes with 1,000,000 static and
1,000,000 learned replays per mode. It is diagnostic evidence only and is not
eligible to change the failed benchmark gate into an acceptance pass.

## Provenance

- Test date: 2026-09-09 (Asia/Shanghai)
- Host: `计算机`, Intel Core i7-7820X, 8 cores / 16 logical processors
- OS: Windows 11 Home, build 26300, x64
- Visible memory: 102,731,558,912 bytes (about 95.7 GiB)
- Power plan: High performance
- Go: `go1.27.1 windows/amd64`
- Source commit measured: `222f2d5f6411df1a942b12d0a11735a7205fe7df`
- Package ID: `i7-7820x-20260909-151806-fb97a7db`
- Package manifest SHA-256: `086172b22c94933b727e8afebd156b29a581312bbeb61e5b78047518a1c1d842`

## Baseline results

The values below are copied from the two retained `summary.json` files. E1/E2
times are batch-amortized probe-set times, not per-key end-to-end input latency.

| Run (local time) | Stage/mode | p95 | p99 | Private memory | Result |
| --- | --- | ---: | ---: | ---: | --- |
| 15:26 | E1 full | 2.42222 ms | 2.46343 ms | 66.27 MiB | PASS |
| 15:26 | E1 variable | 5.86395 ms | 6.00963 ms | 66.15 MiB | PASS |
| 15:26 | E1 shorthand | 5.88594 ms | 5.97799 ms | 65.91 MiB | PASS |
| 15:26 | E2 full | 12.73926 ms | 12.84201 ms | 69.02 MiB | PASS |
| 15:26 | E2 variable | 16.00594 ms | 16.55670 ms | 68.08 MiB | PASS |
| 15:26 | E2 shorthand | 15.82964 ms | 16.23198 ms | 67.14 MiB | PASS |
| 15:26 | E3 full | 1.106738 ratio | 1.125874 ratio | n/a | FAIL |
| 15:26 | E3 variable | 1.153068 ratio | 1.125819 ratio | n/a | FAIL |
| 15:26 | E3 shorthand | 1.099760 ratio | 1.083563 ratio | n/a | PASS |
| 16:34 | E1 full | 2.41074 ms | 2.69171 ms | 67.53 MiB | PASS |
| 16:34 | E1 variable | 5.86271 ms | 6.02365 ms | 66.25 MiB | PASS |
| 16:34 | E1 shorthand | 5.75508 ms | 5.87404 ms | 65.65 MiB | PASS |
| 16:34 | E2 full | 12.83758 ms | 13.19442 ms | 69.48 MiB | PASS |
| 16:34 | E2 variable | 15.81918 ms | 16.31315 ms | 67.34 MiB | PASS |
| 16:34 | E2 shorthand | 16.07345 ms | 16.21232 ms | 68.07 MiB | PASS |
| 16:34 | E3 full | 1.117492 ratio | 1.106734 ratio | n/a | FAIL |
| 16:34 | E3 variable | 1.138739 ratio | 1.132287 ratio | n/a | FAIL |
| 16:34 | E3 shorthand | 1.123199 ratio | 1.137360 ratio | n/a | FAIL |

The E3 limits were p95 <= 1.10 and p99 <= 1.20. A row passes only when both
limits pass. Thus the first run failed overall on E3 full and variable, and the
repeat failed overall on all three E3 modes. Correctness still passed in every
E3 row; the failure is specifically the provisional learning-overhead budget.

## CPU diagnostic

The diagnostic run completed without failure and preserved package and protected
registration integrity. Its per-mode profile hashes are:

| Mode | Replays per engine | CPU profile SHA-256 |
| --- | ---: | --- |
| full | 1,000,000 | `06d54af2bc6bd676055d7a2c7b88089c663746ea6d21329b99910d0be95464c3` |
| variable | 1,000,000 | `f608c7008ba96dcb1a2469029eb3b451afe5912d456a3717718afb03d4ef5834` |
| shorthand | 1,000,000 | `3aeecf83b2e7dd44ea73fd001eb126f38c672de695d3c84d31072b0ca9ed182d` |

The concise reports consistently point to `Engine.refresh`, `Engine.bestSentence`,
allocation/growth work and learned-model map lookup/scoring as investigation
areas. These sampled CPU percentages are not latency measurements.

## Scope and interpretation

This evidence supports the narrower conclusion that the older i7-7820X machine
has ample capacity for E1/E2 YimeCore core workloads under the tested baseline.
It does not support declaring the complete core performance gate passed, because
E3 failed reproducibly. It also does not cover IPC, TSF, installed desktop hosts,
Rime comparison, reboot persistence or broad mainstream-x64 compatibility.

The later installed-product/reboot acceptance is a different test layer and may
pass without contradicting this E3 performance result.

## Published evidence

Exact retained summaries and path-scrubbed concise CPU reports are under
`docs/testing/yimecore/native-core/2026-09-09-i7-7820x/`. Raw `.pprof` files,
generated executables, copied source trees and synthetic learning state remain
local under `C:\YimeBench`; they are not required to read this result and are not
committed as repository payloads.
