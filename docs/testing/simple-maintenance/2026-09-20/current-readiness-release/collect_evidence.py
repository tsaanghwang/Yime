"""Read-only Git/GitHub and original-path audit; never execute product payloads.

Run from the repository root. Output is a new directory, preserving prior captures.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess


REPO = "tsaanghwang/Yime"
BASE = "0ab8631266736775bf1386f456d4a1d53e8e2eb3"
SOURCE_CANDIDATE = "53b409d7713ad47e0ae1039e060462012614d7b2"
RUNS = [35410109813, 35410743586, 35411599859, 35413263479,
        35415060417, 35418522827]
ORIGINAL_ROOT = Path("C:/dev/Yime.worktrees/current-readiness-gates")
ADMISSION = ORIGINAL_ROOT / ".tmp/yimecore-experiment/speech-admission-20260919-090936-2aeb909bb94a41c9b1ed6f61186c0a58"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)

    def capture(name, command):
        result = subprocess.run(command, capture_output=True, check=False)
        (args.output / (name + ".stdout")).write_bytes(result.stdout)
        (args.output / (name + ".stderr")).write_bytes(result.stderr)
        record = {"command": command, "exit_code": result.returncode,
                  "stdout_sha256": hashlib.sha256(result.stdout).hexdigest(),
                  "stderr_sha256": hashlib.sha256(result.stderr).hexdigest()}
        (args.output / (name + ".result.json")).write_text(
            json.dumps(record, indent=2) + "\n", encoding="utf-8")
        if result.returncode:
            raise RuntimeError(f"{name}: exit {result.returncode}; see captured stderr")
        return result.stdout

    queries = {
        "remote-main": ["git", "ls-remote", "origin", "refs/heads/main"],
        "source-delta": ["git", "diff", "--name-status", SOURCE_CANDIDATE, BASE],
        "source-ancestry": ["git", "merge-base", "--is-ancestor", SOURCE_CANDIDATE, BASE],
        "pr62": ["gh", "api", f"repos/{REPO}/pulls/62"],
        "releases": ["gh", "api", f"repos/{REPO}/releases", "--paginate", "--slurp"],
        "source-artifacts": ["gh", "api", f"repos/{REPO}/actions/runs/35411599859/artifacts"],
        "main-artifacts": ["gh", "api", f"repos/{REPO}/actions/runs/35418522827/artifacts"],
    }
    for run in RUNS:
        queries[f"ci-{run}"] = ["gh", "run", "view", str(run), "--repo", REPO,
                                  "--json", "headSha,status,conclusion,url,jobs,event,createdAt,updatedAt"]
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = dict(pool.map(lambda item: (item[0], capture(*item)), queries.items()))

    path_checks = [ORIGINAL_ROOT, ORIGINAL_ROOT / ".tmp/dual-package/r1-complete",
                   ADMISSION, ORIGINAL_ROOT / ".tmp/installed-audit-pre-reboot.json"]
    history = Path("docs/testing/simple-maintenance/2026-09-19/current-readiness")
    summary = {
        "observed_at_utc": datetime.now(timezone.utc).isoformat(),
        "base_main": BASE,
        "source_candidate_from_report_not_package_attestation": SOURCE_CANDIDATE,
        "original_paths": [{"path": str(p), "exists": p.exists()} for p in path_checks],
        "historical_reports": [{"path": str(p), "bytes": p.stat().st_size,
                                "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
                               for p in sorted(history.iterdir()) if p.is_file()],
        "ci": [],
        "boundaries": {"product_execution": False, "installed_payload_read": False,
                       "installation_mutation": False, "user_data_mutation": False,
                       "release_created": False},
    }
    for run in RUNS:
        ci = json.loads(results[f"ci-{run}"])
        summary["ci"].append({"run": run, "head_sha": ci["headSha"], "url": ci["url"],
                              "status": ci["status"], "conclusion": ci["conclusion"],
                              "jobs": [{"name": j["name"], "conclusion": j["conclusion"]}
                                       for j in ci["jobs"]]})
    (args.output / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(args.output), "ci_runs": len(summary["ci"]),
                      "all_ci_success": all(c["conclusion"] == "success" and
                          len(c["jobs"]) == 12 and
                          all(j["conclusion"] == "success" for j in c["jobs"])
                          for c in summary["ci"]),
                      "original_paths": summary["original_paths"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
