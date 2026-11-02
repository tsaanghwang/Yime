# Windows registry adapter test scope (not executed)

This is a development test with an explicitly authorized one-shot cloud execution;
the actual Windows result is still pending and must be verified separately.
The production `OwnedResidueRegistry.h` shares RegOpenKeyEx/RegQueryInfoKey/
RegQueryValueEx/recheck and nonrecursive RegDeleteKeyEx with the test. The production
fixed-path allowlist, ledger-v4 requirement, generation checks and cleanup policy
are unchanged; legacy v2 does not acquire cleanup eligibility.

`YIME_OWNED_RESIDUE_REGISTRY_TESTS` defaults OFF. The target
`YimeOwnedResidueRegistryTests` is EXCLUDE_FROM_ALL and not registered with CTest.
The dedicated reusable workflow is reachable only through ci.yaml's explicit
`confirm_18u_registry_adapter=once-18u-registry-adapter` manual gate, with the
reviewed SHA, fixed branch, attempt 1, and all three older confirmations empty.
Push does not execute this test; do not create a second dispatch or rerun it.
No arguments or any unrecognized arguments return
blocked/exit 3 before registry access. The only accepted runtime argument is
`--confirm-disposable-hkcu-adapter-test`; it is not authorization to run it now.

The test opens preexisting HKCU\\Software, then creates exactly one random root:
`HKCU\\Software\\YimeOwnedResidueAdapterTest-{CoCreateGuid GUID}`. It creates no
shared parent containers, touches neither Classes nor CTF nor product GUIDs,
requires native AMD64, and rejects preexisting items. There is no arbitrary-path
CLI, registry ACL change, registration, TSF activation, or administrator requirement.
Children: empty, disabled, extra, parent/child, first, second/racing-child, third.
Only test DWORD values Enable=0 and Extra=1 are written. Every confirmed-created
item is tracked and cleaned in reverse order with nonrecursive deletion; the first
unknown shape or cleanup error stops all further deletion, retains remaining items
and makes the test fail. Failed creation
with uncertain ownership is not adopted. Crash/power loss can leave the unique root;
this executable is not a crash-recovery installer and does not later adopt old roots.

Coverage planned on Windows: absent/empty/Enable DWORD 0/extra value/subkey shapes,
query access denial using KEY_SET_VALUE-only handle, successful empty/disabled
single deletions, rejection of extra values, then injected child arrival after the
last observation causing real nonrecursive deletion failure. Earlier deletion remains
deleted and later target is untouched. No rollback is claimed. Actual 32/64 view
observations report whether the test key aliases; shared keys ignore view flags,
so two separate stores are not assumed. Query denial is NOT DELETE-ACL denial:
RegDeleteKeyEx independently checks target DELETE access; a read-only parent handle
cannot provide a reliable deletion-denied test. No ACL change was authorized.

The final query-to-delete race remains: Windows does not provide atomic shape-
compare-and-delete here. A newly inserted value in the last window may be deleted;
these tests and unchanged policy do not eliminate that limitation.

Local validation: existing portable OwnedResiduePolicyTests compiled/run on Linux;
these are in-memory fault tests, NOT Win32 adapter execution. No MSVC/Windows SDK
is available here; the new native target has not been compiled or executed.

Evidence schema `owned-residue-registry-test-v1` emits and flushes the generated
full HKCU root before the first create. Terminal output preserves writesAttempted,
creationUnknown, fixed first-failure stage/original HRESULT, separate cleanup
failure, and only completed case names. View alias is null until actually observed.
A missing terminal result is not a pass or proof of no write/cleanup.
