# Rime/PIME candidate maintenance coordination

The executable candidate uses one fixed `Global` kernel-object name for the whole Rime/PIME product. Its identity includes neither the selected install root nor the caller SID, so choosing another root or user cannot create a second independent maintenance interval. Failure to create or open an object is a refusal, not permission to proceed.

The parent creates a named semaphore with count zero and retains the handle for its entire maintenance interval. No code waits on or releases its count. A second parent that finds the object already exists immediately refuses and closes its attempted handle. The parent also creates a second named semaphore with an unpredictable delegation token. A worker opens and retains both objects before checking the exact parent PID, creation time, liveness and SID, plus its own SID. After the parent exits, an admitted worker's handles continue to keep the fixed object alive. Once all holders exit or close their handles, the kernel removes the named object and a fresh parent can create it. There is no persisted lock count to repair and no force-unlock operation.

`Get-RimePimeCandidateCoordinatorHandle` lends the fixed gate handle only from the original live context. The native registration child helper must duplicate and explicitly inherit that handle into its contained registrar/probe process. This keeps a worker's asynchronous job termination from briefly admitting another maintenance process while its child is still exiting. It must not close the borrowed original handle. Other candidate runtime processes do not inherit the gate.

The coordinator is cooperative serialization, not approval authentication or protection against malicious code running as the same SID. Approval, target restrictions, executable and manifest identities, registry ownership and same-SID elevation are separate controller/provider checks. Native registered-host and installed acceptance remain false until actual approved-target evidence exists.

The owned-fixture regression opens only randomized `fixture-*` names. PS5 and PS7 each passed 19 checks, including an actual different worker process retaining exclusion after its parent process was killed, refusal to join a dead parent, automatic fresh acquisition after both processes exit, stale delegation refusal and reference-only handle borrowing/closure. Raw outputs:

- `.tmp/dual-product/coordinator-test-bd84c397ff0c49718ee1b70aae40caf8/result.json` (PS5).
- `.tmp/dual-product/coordinator-test-c8d0ce34c8254a46a62cd5fa0df1470b/result.json` (PS7).

Those tests do not open the production gate, register a product, run an installer, access production user data or touch local.12. Actual different-user admission, full installed maintenance and child-process job/gate integration need their own evidence; the standalone coordinator tests do not imply them.
