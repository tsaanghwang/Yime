# Independent 18u diagnostics and owned cleanup: local development only

Base: `71a4a252641159753b0eff41b871254233c6efd2` (fixed v2 source).
This is an isolated source snapshot, not a Git worktree/branch. The environment
denied writes to `.git` when creating the branch. The existing branch, delivery
packages, registration receipts and live residue were not changed.

Apply `A-diagnostics.patch` to the exact base, then `B-owned-cleanup.patch`.
Neither patch is a package, release, installation instruction or recovery authorization.

## A: diagnostics without deletion changes

- Keep the first registration/preflight error independently from ordered cleanup
  failures. Preserve HRESULT values and completed mutation/activation stages.
- Include the matched independent identity's hive, view and CTF path for a
  failing key-name absence check. Do not dump other input-method data.
- Propagate native diagnostics into the orchestration receipt even on exit 1.
- Observation, operation and normal-cleanup catches use the same tested
  `CaptureStage` boundary. Direct `Failure` and ordinary exceptions preserve the
  first error; already recorded exceptions are not duplicated by the catch.
- Reject non-object native JSON before field access. Empty/truncated JSON,
  duplicate keys, arrays, null and scalar values retain a failed receipt with
  process/log/ledger binding and do not start independent verification.
- Offline evidence validation rejects primary/cleanup failures even if a summary
  incorrectly claims success. Existing historical evidence remains readable.
- The stage-A `Transaction::cleanup()` body is checked byte-for-byte against the
  fixed base. The diagnostic instrumentation adds no registry deletion.
- Results are observations of reached checks/calls, not proof of execution of
  unreported calls. Abrupt termination can prevent the final native JSON; process
  timeout/completion receipts remain authoritative about that uncertainty.

## B: new transactions only

- New encrypted ledger schema: `18u-mycomputer-ledger-v4`. Persist the ordered
  per-path absence records before the first COM write, alongside the existing
  host/account/DLL/generation binding and durable attempt checkpoints.
- Exact allowlist: the independent TIP root, 0804/profile path, and its own
  keyboard-category/Item paths, in the explicit HKLM/HKCU 32/64 views.
- After successful API cleanup, delete leaf-first only empty keys or the exact
  HKCU profile leaf whose sole value is DWORD `Enable=0`. Unexpected values,
  children, enabled state, identity, provenance or query failures stop cleanup.
- Revalidate ownership and observed shape/revision before every deletion; use
  nonrecursive `RegDeleteKeyExW`, then verify absence. Shared registry views may
  return absence at a later step; absence is not treated as an access error.
- COM deletion is last, with separate nonrecursive server/root deletion and
  checks. No recursive deletion is added to the local MyComputer path. The
  unrelated historical non-local compile path retains its original behavior.
- API cleanup failures now stop further mutations in this local path. There is
  no retry, compensation, default-input change or automatic recovery.

## Fixed v2 compatibility conclusion

Fixed v2 uses `18u-mycomputer-ledger-v3`, without per-item before-state evidence.
The new loader rejects it as `legacy-v2-no-item-provenance` before entering new
cleanup. It neither upgrades the old journal nor infers ownership from today's
empty keys. The current machine's v2 residue is explicitly out of scope.
Recovery of that residue requires a separate design/review and authorization.

## Limits and failure semantics

Rechecks are not an atomic compare-and-delete operation. A concurrent writer can
still race between the last observation and Windows' deletion. This work does
not claim an adversarial same-account isolation boundary. A detected change
stops the sequence; native race behavior still needs authorized disposable-host
validation. Partial deletion remains partial. Keeping COM/ledger evidence does
not restore the previous state or guarantee a future recovery will succeed.

The new final-window tests inject changes inside `eraseOne`, after the final
policy observation: a new child makes nonrecursive deletion fail and stops the
sequence; an access failure after an earlier deletion leaves partial state.
The value-only insertion test deliberately demonstrates the remaining gap:
nonrecursive deletion can delete the newly inserted value without detection.
This is a limitation characterization, not a claim that the race is fixed.

No live registration, activation, verification or recovery entry was run during
this work. Native source is compiled as object-only targets. Executed C++ tests
use only in-memory backends; Python uses synthetic packages/process fixtures.
No broker/full input/physical acceptance is claimed.

## Validation

- MSVC x64 compile-only: A, A+B, and the historical non-local build path.
- Three CTest executables: original pure policy, shared diagnostic-boundary
  tests and in-memory residue fault tests (legacy rejection, missing evidence, owner mismatch, unexpected
  shape, changed revision, permission error, partial failure, recreation and
  view-alias absence).
- 63 offline Python tests: evidence consistency, synthetic orchestration,
  preflight-package validation, package construction fixtures, source guards
  and CI workflow contracts. No synthetic runner starts a native entry.
- The existing nonregistration workflow now builds/runs both new portable
  executables, checks their exit codes and retains individual logs. Its existing
  branch/permission/package scope is unchanged; no CI run was dispatched.
- Test temporary files are confined to `local-validation/tmp`. An initial run
  failed because the default temporary directory denied access; no permissions
  were changed. Subsequent runs use only the source snapshot's writable area.
- During this revision, one Python run failed in a synthetic receipt save with
  `FileExistsError` for `registration.json.tmp`; the preceding cause was not
  retained. A diagnostic run observing save exceptions passed all 63 tests
  without such an error. No production retry or receipt overwrite workaround
  was added. This intermittent filesystem failure remains unexplained.
- An old source guard initially failed because its catch-block delimiter no
  longer matched the new helper. The delimiter now bounds the actual recovery
  branch, retaining the no-ledger-write assertion and adding helper wiring checks.

Still required before any release: peer review of Windows adapter ownership and
race handling, disposable-host real TSF lifecycle/fault validation, and a fresh
immutable package with separately reviewed execution authorization. Neither
non-registering CI nor these local tests prove native cleanup correctness.
