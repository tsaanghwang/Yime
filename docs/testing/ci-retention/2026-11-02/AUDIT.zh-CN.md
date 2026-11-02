# CI retention conflict audit — 2026-11-02

Scope: shared CI source and the isolated 18u touch keyboard lab. No product or installed input method was changed.

## Confirmed conflict

PR #92 merged the daily cleanup at 19:23 UTC. Its original implementation selected artifacts by `created_at < now - 7 days` and completed runs by both creation and update age. It did not check `expires_at`, artifact identity, or package delivery records. Removing a run also removes its attached artifacts. For the PR #87 run, the first eligible scheduled deletion is 2026-11-07 19:23 UTC, if the schedule fires then and the run remains completed. GitHub reports the three artifact expirations on 2026-11-14 06:50–06:51 UTC. Scheduled jobs may start late; this is an earliest risk time, not a guarantee.

## Exact PR #87 evidence held

| ID | Role | GitHub SHA-256 / freshly downloaded ZIP SHA-256 | GitHub expires_at |
| --- | --- | --- | --- |
| 13034145597 | amd64 full package, MyComputer | e790c0fe0e245456e54163f348c969af93b3ac0ed91dda95e53e00655da4e34f | 2026-11-14 06:50:48 UTC |
| 13033634731 | ARM64 full package, ASUS | 9395e994382fe70a30c3bb9beecd57a8c074e88411f4d2b62732b8161c6ada7b | 2026-11-14 06:51:00 UTC |
| 13034360087 | original CI package verification ZIP | e435c3248a1d7fd2b0e42c54170814b927dba75b4263edc055e04f22d5432474 | 2026-11-14 06:50:59 UTC |

All three belong to run [41178044364](https://github.com/tsaanghwang/Yime/actions/runs/41178044364). The GitHub API reported `expired:false` for each on November 2. Fresh original downloads were saved at `C:\dev\Yime-deliveries\ci-retention-20261102\pr87\<artifact ID>.zip`; their lengths and SHA-256 match the API and [PR #87 delivery record](../../touch-keyboard/2026-10-31/candidate-readability/CI_DELIVERY.zh-CN.md). This is a second machine-local copy, not proof that MyComputer and ASUS each received their own independent copy. Keep online access to both architecture packages and the original CI verification report until cross-machine receipt, hash checks, and acceptance evidence are complete. Their run should remain available so the original source and job context can be checked. GitHub itself can expire the artifacts on November 14; the hold does not extend GitHub's own expiry.

## 18u historical failure evidence

The original pen Shift failure, contact traces, root-cause regressions, and retest are in `docs/testing/touch-keyboard/2026-10-26/pen-shift/`. The H02 message-pump before/after logs are in `2026-10-22/h02-navigation/review-fix/`. Earlier P4 and review-fix failure/regression records and taskbar user reports are also committed. [Tracked failure evidence hashes](tracked-failure-evidence-sha256.json) inventory 110 files under these five exact paths; they are accessible through Git and do not require their former Actions runs to remain online.

Queries for older fixed runs #74 (39364723162), #76 (39535478116), and #77 (39751192421) returned 404 from the artifact listing API. Their online artifact retention cannot be verified or restored by this change. Preserve the repository records and any already downloaded original packages; do not present a rebuilt package as those artifacts. PR #82 run 40802706324 (expires November 12) and PR #83 run 41018028276 (expires November 13) were still online on November 2, but both architectures and verification ZIPs already exist under `C:\dev\Yime\.generated\pr82-ci-delivery-40802706324` and `pr83-ci-delivery-41018028276`. They are not granted an exception without a confirmed current online requirement. Their normal seven-day cleanup may delete them before GitHub's expiry. [GitHub API snapshot](github-snapshot.json) records the observations.

## Protection and release

[Policy](../../../../tools/ci/retention-protected.json) names only the three PR #87 artifacts, their parent run, and SHA-256. [Cleanup code](../../../../tools/ci/cleanup_actions.py) protects them both when deleting individual artifacts and when considering a parent run, including if an artifact is omitted from the global listing. Invalid/missing policy stops cleanup. The script defaults to read-only; the scheduled workflow explicitly passes `--delete`. Deleting a normal run still checks its attached artifacts for protected IDs or recent uploads.

Remove the three IDs and their run hold only after independent target-machine receipt and the decision on further online source access are recorded. This exception cannot keep artifacts past GitHub's own `expires_at`; if more time is needed, preserve and distribute the original verified ZIPs through a separately managed archive before that deadline. No blanket retention extension is implied.
