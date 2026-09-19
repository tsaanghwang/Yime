# YimeCore E3 score-sequence optimization result (2026-09-19)

## Scope

This change addresses the E3 learned-model latency gate only. It does not
change the gate (`p95 <= 1.10`, `p99 <= 1.20`), candidate scores, ordering,
learning persistence, package identities, ARM64 scope, or signing policy.

The benchmark is the repository's native-host interleaved E3 experiment with
100 samples and 5,000 replays per sample, using the installed x64 development
indexes. Static and learned batches alternate in chunks of at most 50 replays.

## Baseline

| Mode | p95 learned/static | p99 learned/static | Gate |
| --- | ---: | ---: | --- |
| full | 1.079 | 1.191 | pass |
| variable | 1.158 | 1.239 | fail |
| shorthand | 1.161 | 1.200 | fail |

CPU profiling identified repeated `userCandidateModelScore` hash lookups as a
material learned-only cost. A replay revisits the same small input and context
states while the user-model generation normally remains unchanged.

## Change

For each input, previous-commit context, page and active-segment state, the
engine records the observed candidate-score sequence. A later visit replays
that sequence only while every full candidate identity matches. Any identity
or ordering mismatch immediately falls back to the existing score cache.

All sequences are discarded when the user-model generation changes. The
ordinary cache remains the source of truth on first observation and on every
mismatch. The unit test covers successful recording, mismatch safety and
generation invalidation.

## Result

Three complete post-change runs all passed all three modes:

| Run | full p95 / p99 | variable p95 / p99 | shorthand p95 / p99 |
| --- | --- | --- | --- |
| 1 | 1.090 / 1.085 | 1.071 / 1.035 | 1.049 / 0.991 |
| 2 | 1.076 / 1.091 | 1.060 / 0.942 | 1.074 / 0.988 |
| 3 | 1.032 / 1.019 | 1.027 / 0.998 | 0.996 / 1.017 |
| final code | 1.056 / 1.075 | 1.055 / 1.127 | 0.996 / 1.031 |

Worst observed post-change ratios were 1.090 at p95 and 1.127 at p99, inside
the unchanged E3 gates. `go test ./...` also passed for the complete Go backend.

These results close the reproducible E3 software bottleneck on the current
development host. They do not substitute for ARM64 or signed-release evidence.
