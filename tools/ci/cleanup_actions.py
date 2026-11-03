import datetime as dt
import json
import os
import urllib.error
import urllib.request

from pathlib import Path
import argparse
import re

def load_protection(path, repository):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if data["version"] != 1 or data["repository"] != repository:
        raise ValueError("Protection manifest version/repository mismatch")
    artifacts, runs = set(), set()
    for item in data["artifacts"]:
        for key in ("id", "run_id"):
            if type(item[key]) is not int or item[key] <= 0:
                raise ValueError("Protection IDs must be positive integers")
        if item["id"] in artifacts or not item["reason"].strip() or not re.fullmatch(r"[0-9a-f]{64}", item["sha256"]):
            raise ValueError("Invalid or duplicate protected artifact")
        artifacts.add(item["id"])
        runs.add(item["run_id"])
    return artifacts, runs

def cleanup(api, protected_artifacts, protected_runs, cutoff, current_run_id, delete=False):
    def listing(path, key):
        # Snapshot every page before deleting, so pagination cannot skip entries.
        result = []
        page = 1
        while True:
            data = api(f"{path}?per_page=100&page={page}")
            if data is None:
                raise RuntimeError(f"Cannot list {path}")
            items = data[key]
            result.extend(items)
            if len(items) < 100:
                return result
            page += 1

    def old(timestamp):
        return dt.datetime.fromisoformat(timestamp.replace("Z", "+00:00")) < cutoff

    def eligible_run(run):
        return (run["status"] == "completed"
                and old(run["created_at"]) and old(run["updated_at"])
                and str(run["id"]) != str(current_run_id)
                and run["id"] not in protected_runs)

    artifacts = listing("/actions/artifacts", "artifacts")
    runs = listing("/actions/runs", "workflow_runs")
    counts = {"artifacts": 0, "runs": 0}
    print(f"Evaluating completed CI data older than {cutoff.isoformat()}", flush=True)
    for artifact in artifacts:
        if artifact["id"] in protected_artifacts or not old(artifact["created_at"]):
            continue
        path = f'/actions/artifacts/{artifact["id"]}'
        current = api(path)
        if current is not None and old(current["created_at"]):
            if delete:
                api(path, "DELETE")
            counts["artifacts"] += 1
            print(f'Selected artifact {artifact["id"]}', flush=True)

    for run in runs:
        if not eligible_run(run):
            continue
        path = f'/actions/runs/{run["id"]}'
        current = api(path)
        if current is None or not eligible_run(current):
            continue
        # Deleting a run also removes its artifacts; preserve any recent upload.
        attached = listing(path + "/artifacts", "artifacts")
        if any(a["id"] in protected_artifacts or not old(a["created_at"]) for a in attached):
            continue
        if delete:
            api(path, "DELETE")
        counts["runs"] += 1
        print(f'Selected run {run["id"]}', flush=True)

    summary = (f"Delete enabled: {delete}; protected artifacts: {sorted(protected_artifacts)}; protected runs: {sorted(protected_runs)}\n\n"
               f"Cutoff (UTC): {cutoff.isoformat()}\n\n"
               f"Selected runs: {counts['runs']}\n\n"
               f"Selected artifacts: {counts['artifacts']}\n")
    print(summary)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as stream:
            stream.write(summary)
    return counts

def main():
    parser = argparse.ArgumentParser(description="Seven-day CI cleanup with exact evidence holds")
    parser.add_argument("--delete", action="store_true", help="Execute deletions; default is read-only")
    args = parser.parse_args()
    protected_artifacts, protected_runs = load_protection(
        Path(__file__).with_name("retention-protected.json"), os.environ["GITHUB_REPOSITORY"])
    base = os.environ["GITHUB_API_URL"] + "/repos/" + os.environ["GITHUB_REPOSITORY"]
    headers = {
        "Authorization": "Bearer " + os.environ["GH_TOKEN"],
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "Yime-CI-cleanup",
    }

    def api(path, method="GET"):
        request = urllib.request.Request(base + path, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.loads(response.read() or "null")
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return None  # Already removed by another cleanup.
            raise
    cleanup(api, protected_artifacts, protected_runs,
            dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=7),
            os.environ["GITHUB_RUN_ID"], args.delete)

if __name__ == "__main__":
    main()
