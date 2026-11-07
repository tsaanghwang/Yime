# PR #105: stable external-memory test fixtures

Date: 2026-11-06. Windows amd64, Go 1.26.4, existing MSYS2 UCRT64 GCC.
Base: `52f28f32b805b6d00968c0278d9e5ea59c212a82` (includes main `1fe1baa4`).

## Failure and cause

The original [Build #809 failure](https://github.com/tsaanghwang/Yime/actions/runs/42131655280/job/127609975028) reported:

```text
--- FAIL: TestRimeAPIFunctionAtValidatesDataSize
librime_memory_windows_test.go:23: truncated API table must be rejected, got 0x12345678
```

The test exported a Go stack object's address as a stored `uintptr`. A later stack growth can move that object without updating the integer. `runtime.KeepAlive` only keeps the object live; it does not stabilize the address. The test then changed the relocated object's `DataSize`, while the saved integer still addressed the old full-size copy. Production reads DLL-owned memory, which is not a Go stack object.

A bounded baseline run of the original test (`-race -count=20`) passed. This did not establish correctness. Adding the final test's `growRimeMemoryTestStack(64)` call after the initial lookup, plus an address diagnostic, reproduced the original assertion failure in one run, before applying pinning:

```text
fixture address: saved=0xc0000c5c48 current=0xc0002dfc48
truncated API table must be rejected, got 0x12345678
```

The raw `before-forced-stack.log` preserves this failing run. No failed GitHub job was rerun.

## Fix and isolation

`librime_memory_windows_test.go` pins each Go-backed external-memory fixture with `runtime.Pinner` before converting its address to `uintptr`, and defers `Unpin` until after all reads. The large recursive stack frame remains in the regression. All original assertions remain, including the truncated-table rejection. New assertions verify the updated pointer after restoring the table size and an updated string after stack growth.

No production code, eligibility logic, workflow gate, race setting or assertion was weakened or changed. See the Go documentation for [uintptr lifetime and relocation](https://go.dev/pkg/unsafe/?m=old) and [runtime.Pinner](https://pkg.go.dev/runtime#Pinner.Pin).

## Local validation

Run from `C:/dev/Yime/go-backend`, with process-local `CGO_ENABLED=1`, `CC=gcc`, existing `C:/msys64/ucrt64/bin` prepended to PATH, and repository `.tmp` Go caches. Each JSON file records the exact command, exit code and cache paths; each paired log is copied byte-for-byte from the captured subprocess output.

| Evidence | Result |
| --- | --- |
| before-race | Original test, race enabled, 20 executions passed; timing-dependent failure not reproduced by repetition alone |
| before-forced-stack | Unpinned fixture plus forced stack growth, one execution failed with the CI assertion and changed address |
| after-race | Pinned fixtures with stack-growth checks, three tests x 20 executions, all 60 passed under race detector |
| after-normal | Same three tests, one execution each, all passed without race detector |

The selected tests exercise only in-memory API-table and bounded-string reads. They do not activate a real TIP, load an installed input method, install/register components, or change the default input method. This is isolated development evidence, not real-host acceptance.

## Evidence preservation

The preceding `../pr101-main-local/` archive remains unchanged: its 13 SHA-256 entries and eight original-source copies are checked separately, as are the 174 files in the five existing untracked directories. This new record does not rewrite those original logs or relabel their results. `SHA256SUMS.txt` covers all other files in this directory; `.gitattributes` disables text conversion so Git stores the original log bytes. GitHub CI for the fix must pass before merge; this local record makes no claim about a future CI result.
