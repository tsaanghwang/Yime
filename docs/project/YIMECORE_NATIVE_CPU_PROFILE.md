# YimeCore native CPU diagnostics

Affected product: YimeCore core only.

Use this tool after a completed native core baseline identifies a reproducible
learning-overhead failure. It collects CPU samples from static and learned
replay paths, using the existing local preparation snapshot and frozen indexes.
The original E3 functional setup and replay function are retained. The timed
acceptance section is replaced only in a newly generated diagnostic command;
the original snapshot, benchmark package and acceptance tool remain unchanged.

The adapter accepts the reviewed E3 source version by normalized source SHA-256.
It imports the existing benchmark helper only after checking the independently
supplied package-manifest hash, helper inventory hash and reviewed helper code.
The original identified-host, memory-profile, source/package integrity and
independent system-registry checks still run. Unsupported source versions,
changed files, incomplete reports and missing tagged samples fail explicitly.

## Run on the identified physical test PC

Save native-core-profile.psm1 beside the existing local benchmark tools.
Import that module and invoke Invoke-YimeCoreNativeLearningProfile with the
same PackageRoot and externally retained ManifestSHA256 used for the baseline.
The original preparation must still be under the same benchmark root, and the
installed Go version must match the version recorded when the package was built.
The shared repository is not read during this operation.

By default the tool warms each engine with 2000 replays, then records 1,000,000
replays per engine, per mode. Static and learned chunks of at most 50 replays
alternate first position. CPU labels distinguish the two paths. Each run builds
a fresh diagnostic executable with the baseline build environment and writes a
new profiles/learning-* directory under the local benchmark root.

Outputs include:

- summary.json: local provenance, integrity and diagnostic completion.
- Per-mode cpu.pprof: tagged raw CPU samples, plus synthetic E3 model files.
- Per-mode text logs: flat and cumulative CPU tables for static, learned and all
  samples. The all reports include runtime work not attributed to a tagged path.
- share-variable.txt, share-full.txt, share-shorthand.txt: concise tables
  containing the source commit, mode, replay count and function rows. The
  function-row export omits local path headers and machine identity fields.

Nothing is uploaded automatically. Begin analysis with share-variable.txt,
then consult the other modes and raw local profiles as needed. Retain all runs.

## Interpretation and verification

Profiles include instrumentation overhead. CPU samples and percentages identify
investigation targets; they are not p95/p99 input latency, a measured acceptance
ratio, or proof of a particular optimization. Both report schemas explicitly set
diagnostic_only=true and eligible_for_acceptance=false. A completed profile
does not change any prior benchmark result.

The module reuses the existing process lock and preserves protected registration
evidence. It changes no installation, default input method, CPU quota, affinity,
power plan or operating-system memory limit. Only new synthetic model files are
used. Registry and machine details remain in local evidence.

The focused contract suite checks source-version refusal, preservation of E3
functional checks, untrusted-helper refusal before import, path/junction refusal,
evidence completeness and path removal from concise reports. Its real Go smoke
test builds the derived command, creates tiny synthetic indexes for all three
modes, collects both labels, reads flat/cumulative tables with go tool pprof,
and verifies that an attempted rerun cannot overwrite earlier evidence.
These CI fixtures do not establish performance on the user's physical PC.

References: Go's [runtime/pprof API](https://pkg.go.dev/runtime/pprof) and
[pprof guide](https://github.com/google/pprof/blob/main/doc/README.md).
