# DP1-P: versioned successor isolated Rime/PIME candidate

Affected product: the independent Rime/PIME product. YimeCore, installed products, the default input method and production user data are outside this change. DP1-P added a pure-data version-identity admission gate, advanced the reviewed development identity from `1.4.0-dev` to `1.4.0-dev.1`, and rebuilt one unsigned, disabled x86/x64 successor in a detached exact-HEAD clone. The identity transition is admitted; actual canonical migration remains explicitly unadmitted and was not performed.

## Narrow outcome

The passing result is limited to the following statement:

- exact-HEAD isolated successor candidate: **PASS**;
- strict version and installer-leaf identity transition: **admitted**;
- actual canonical installer-plus-receipt migration: **not admitted and not executed**.

The tracked [DP1-P evidence record](../testing/dual-product/2026-09-07-dp1-p-versioned-successor-candidate.json), SHA-256 `216eed8b6cabfdd5b1fa5c084cae0747a7132206dd04647ec2807a8117bf65c4`, binds the final result, exact source, candidate chain, actual-checkout protection and explicit non-claims. Its sidecar is stored alongside it. The runner's detailed output remains under `.tmp/dual-product`; that outer directory is transient evidence, not an archive.

## Source and version identity

| Role | Exact identity |
| --- | --- |
| version-identity gate commit | `6b7b7332979ae03a810df6a40a0ccd2bb3130279` |
| reviewed version identity commit and exact build HEAD | `9f536635f29960365afac32a2561bfaa62f84d1b` |
| exact tree | `25952901b3cca25591fc88e23f6723583bd7bbba` |
| runner HEAD and worktree blob | `d5ac007d5ebaae91d14ccd5a61c301454838cd9b` |
| predecessor identity | `1.4.0-dev`; `installer/YIME-1.4.0-dev-setup.exe` |
| successor identity | `1.4.0-dev.1`; `installer/YIME-1.4.0-dev.1-setup.exe` |
| formal release target | unreleased `v1.4.0`; fixed PE numeric version remains `1.4.0.0` |

The admission layer requires supported strict SemVer on both sides, canonical installer paths, strict receipts, a strictly increasing successor version, and a different Windows installer leaf using case-insensitive path semantics. The successor must additionally carry durable current membership-interval evidence. It is a pure decision function: its output always keeps `actual_canonical_migration_admitted=false` and performs no migration.

The isolated runner also requires exact-HEAD `version.txt` to equal the reviewed version in the same HEAD's `tools/dual-product/contract.json`. It used a detached clone with clone-local `core.autocrlf=false`; the tracked runner blob matched exact HEAD.

## Candidate and evidence chain

The final runner output is `.tmp/dual-product/dp1-o-candidate-20260907-d/result.json`, 6,177 bytes, SHA-256 `9833ebe569a3ebf4e6962b22f820e4cf42abffb88db07e740794b434917848c8`; its sidecar verified and its status is `pass`.

| Evidence | Exact result |
| --- | --- |
| successor candidate | `repo/installer/YIME-1.4.0-dev.1-setup.exe`; 41,455,231 bytes; SHA-256 `ac97f65af80e9686525a3c2f289670aaa14edb60a6effc80ce7cc3580333970d`; unsigned, disabled and not executed |
| package plan | 4,758 bytes; SHA-256 `0999fec6a2799e923118ce6cb047821eb1c2e5beff1c939df34e1888ce5a418e` |
| current build result | 7,990 bytes; SHA-256 `65ab931e7238e59855d1ccf27abc7aa371406073a9d27220132608d899bd7195`; membership-interval schema; 20 plan artifacts and 22 matching stage bindings |
| static build manifest | 5,547 bytes; SHA-256 `537d396bbc99f4142670bdc29e49a1f6153cac1ae749dd9964bfc67a13928128`; passed |
| PowerShell 7 postbuild result | 47,934 bytes; SHA-256 `7dd531596cc4fe943596c4782e54670330b63055e9e0b7177f1ffa419b202c49` |
| PS5-labeled independent postbuild result | 47,856 bytes; SHA-256 `548333f4dd096061eabfffd2283a64e903c5ceaff26a9ff82623fe9ecb817b10` |
| static archive membership | 181 outer installer entries and 11 nested-uninstaller entries in both postbuild reads |
| generated uninstaller | 585,292 bytes; SHA-256 `ffd37a56d45b8c108c0c8e1c5780cfdcc41babcb435012aac7c88a6a6416fb26`; static archive member verified, but generated-uninstaller verification and trust remain false |
| retained strict receipt-v2 | 6,185 bytes; SHA-256 `185d9056e11a89c7ed5f425147e91b66a677a043e9234a1702acdda5372567fa`; strict reader passed under Windows PowerShell 5.1 and PowerShell 7 |

The retained receipt reports `evidence_artifacts_durable=true` only for `isolated-clone-content-addressed-process-interruption-protocol`. That scope does not establish retention of the outer `.tmp` root, evidence archival outside `.tmp`, directory-metadata durability or hardware power-loss survival.

The existing build also emitted and statically identified ARM64 cross-compiled PIMETextService artifacts. The admitted package profile remains x86/x64. This is not an ARM64-native package, execution, compatibility, registered-host or live-host result.

## Cross-shell and baseline checks

- The version-identity admission fixture passed 17/17 under Windows PowerShell 5.1 and PowerShell 7; both result files have SHA-256 `b7a0e9f52b146c2699314b1a27532c4e66591f730208ea7f18059c9d3de97feb`.
- The isolated-candidate runner contract passed 15/15 under both shells; both result files have SHA-256 `053e54c96a8ac07b151223b8086edb94beb45296a5ab6834594d178057d5897f`.
- The current-source baseline records 142 sources, 60/60 fixture tests and six still-pending items; SHA-256 `fef3dfbb1543f553b2983f43a08e4ec39269a299939d3b43721d6bdec1ad08c8`. It keeps `dp2_physical_acceptance_passed=false`.
- Build guards passed under both shells, baseline unit tests passed 60/60, and the pinned i686 PIMELauncher test set passed 26/26.

The independent postbuild result is called **PS5-labeled** because the selecting command and output path identify that rerun; its JSON does not record the PowerShell version. It is not bound into the durable successor receipt and remains under the outer `.tmp` root. Those limits prevent treating it as self-proving or archived shell evidence.

## Actual checkout protection

Within the final run, the protected aggregate snapshot was SHA-256 `9f887a07abc684864b221eb8f3d564b1ccee633dee753d8b46e747481803b33f` both before and after. This equality is asserted only within this run; the snapshot format exposes an aggregate hash and is not compared to a different run.

| Actual protected item | Unchanged result |
| --- | --- |
| canonical receipt | `installer/package-build-receipt.json`; 5,688 bytes; SHA-256 `c18d1202ad78dcd6f8c1f74b34859a83489adb01fb156fa4e2546160aff5b0be`; strict reader passed; `evidence_artifacts_durable=false`; version `1.4.0-dev` |
| canonical receipt sidecar | SHA-256 `ae28a8f7ed01aa784ff657f465616d794204ca624c680fa4c159a4fde15d5a74` |
| actual installer | `installer/YIME-1.4.0-dev-setup.exe`; 41,456,428 bytes; SHA-256 `32a7d66e06284d512675e40495b6e244a23630d2e368ac2cf73ce652e623efe2` |
| successor leaf in actual checkout | absent |
| actual `installer/receipt-evidence` | absent |

Old and new installer sizes and hashes in the tracked record come from their strict old and successor receipts; the identity-admission object itself does not carry these byte identities. The three pre-existing user L5 worktree files also retained their previously recorded hashes and were not included in the DP1-P commits.

## Concrete development-gate regressions

No installed-product regression was observed because no product was installed or run. Seven concrete development-gate defects were found and corrected before the passing candidate:

- Windows installer-leaf comparison was case-sensitive; it now uses case-insensitive Windows path semantics and rejects a case-only change.
- The first identity rule required only unequal version strings and could admit a downgrade; strict SemVer precedence now rejects equal or lower successors, including prerelease and arbitrary-size numeric identifier cases.
- The isolated runner did not bind exact-HEAD `version.txt` to the same HEAD's reviewed contract version; it now fails before build on disagreement.
- Baseline validation allowed leading-zero core components and did not lock both Launcher numeric VERSIONINFO calls or the TextService numeric PRODUCTVERSION line; grammar and propagation anchors now fail closed.
- CI selected the first matching installer and could inspect the wrong leaf when several existed; it now requires exactly one case-exact leaf derived from `version.txt`.
- The initial AST purity fixture omitted harmless `Set-StrictMode` from its command allowlist and failed 1 of 17 checks under both shells. The reviewed allowlist was corrected; the final results are identical 17/17. The failed fixture artifact SHA-256 is `879bb6b7bced111b9e84c71bbfa65a9bd281cad5fa120ecde3105df4963d15cf`.
- The first admission-fixture helper passed an empty `Reasons` array through ordinary PowerShell parameter binding and failed all 13 then-current checks before exercising product behavior. The fixture binding was corrected and the expanded final suite passes 17/17.

The final two items are test-fixture defects, not product regressions. None of these findings changes DP1-O's historical candidate, hashes, same-leaf blocker or development corrections.

## Explicit non-claims and next gate

DP1-P does not publish or migrate the actual canonical installer or receipt, wire a real installer transaction adapter, establish final payload or full NSIS/non-OS input closure, trust the generated uninstaller, sign a binary, admit delivery, or prove installed/registered/live-host behavior. It does not guarantee outer `.tmp` retention, archival evidence, hardware power-loss or directory-metadata durability, and it does not physically prevent hostile same-SID replacement.

No installer, uninstaller or signing process was executed. No product process was started or stopped; no registry, default-input-method, production Rime/PIME, installed YimeCore local.12, production user-data or user-text action occurred. Frozen and historical payloads were not executed.

The next ordered gate is a separate review of evidence archival outside `.tmp` and the conditions for an actual canonical installer-plus-receipt migration. This record alone must not invoke DP1-N. Full closure, directory/power-loss durability, a real adapter, signing, delivery, installed/live acceptance and ARM64-native evidence remain independent later gates. DP1, DP2, DP3, L5 and L6 are not promoted.

The dual-product decision remains unchanged: Rime/PIME and YimeCore can be installed alone or together, and each is independent of the other's runtime, installation, maintenance, writable state and recovery. DP1-P creates no shared runtime or cross-product dependency.
