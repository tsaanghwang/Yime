import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import urllib.error
import urllib.request


ARTIFACT_DAYS = 5
RUN_DAYS = 7
SELECTED_NAME = re.compile(
    r"selected-(delivery|reproduction)-(installed-18u|touch-terminal)-"
    r"(x64|arm64|receipt|receipt-x64|receipt-arm64)-([0-9a-f]{40})-attempt-([1-9][0-9]*)"
)
SELECTED_WORKFLOWS = {
    "installed-18u": ".github/workflows/installed-18u-compile.yml",
    "touch-terminal": ".github/workflows/touch-terminal.yml",
}


def load_protection(path, repository):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if data["version"] != 1 or data["repository"] != repository:
        raise ValueError("Protection manifest version/repository mismatch")
    artifacts, runs = set(), set()
    for item in data["artifacts"]:
        for key in ("id", "run_id"):
            if type(item[key]) is not int or item[key] <= 0:
                raise ValueError("Protection IDs must be positive integers")
        if (item["id"] in artifacts or not item["reason"].strip()
                or not re.fullmatch(r"[0-9a-f]{64}", item["sha256"])):
            raise ValueError("Invalid or duplicate protected artifact")
        artifacts.add(item["id"])
        runs.add(item["run_id"])
    return artifacts, runs


def timestamp(value):
    result = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    if result.tzinfo is None:
        raise ValueError("CI timestamps must have a timezone")
    return result


def cleanup(api, protected_artifacts, protected_runs, artifact_cutoff,
            current_run_id, delete=False, *, run_cutoff=None, report=None):
    """Recheck exact IDs before DELETE; retain partial results in report on error.

    The API returns None for a missing GET and False for an already-missing DELETE.
    """
    if run_cutoff is None:
        run_cutoff = artifact_cutoff - dt.timedelta(days=RUN_DAYS - ARTIFACT_DAYS)
    protected_artifacts, protected_runs = set(protected_artifacts), set(protected_runs)
    audit = report if report is not None else {}
    audit.update({
        "schema": "yime-actions-cleanup-report-v1", "delete_enabled": delete,
        "artifact_cutoff_utc": artifact_cutoff.isoformat(),
        "run_cutoff_utc": run_cutoff.isoformat(),
        "protected_artifact_ids": sorted(protected_artifacts),
        "protected_run_ids": sorted(protected_runs),
        "dynamic_selected_holds": [], "snapshot": {},
        "candidates": {"artifacts": [], "runs": []},
        "deleted": {"artifacts": [], "runs": []},
        "skipped": [], "failures": [], "completed": False,
    })
    operation = {"stage": "snapshot", "path": None}

    def request(path, method="GET"):
        operation.update(path=path, method=method)
        return api(path, method)

    def listing(path, key):
        # Read every page before mutation; duplicate IDs indicate a shifting list.
        result, seen, total = [], set(), None
        page = 1
        while True:
            data = request(f"{path}?per_page=100&page={page}")
            if not isinstance(data, dict) or not isinstance(data.get(key), list):
                raise RuntimeError(f"Cannot completely list {path}")
            count = data.get("total_count")
            if type(count) is not int or count < 0 or (total is not None and count != total):
                raise RuntimeError(f"Missing or changing total_count in {path}")
            total = count
            items = data[key]
            for item in items:
                identity = item.get("id")
                if type(identity) is not int or identity <= 0 or identity in seen:
                    raise RuntimeError(f"Invalid or duplicate ID in {path}")
                seen.add(identity)
            result.extend(items)
            if len(items) < 100:
                if len(result) != total:
                    raise RuntimeError(f"Incomplete pagination in {path}: {len(result)} of {total}")
                return result
            if len(result) > total:
                raise RuntimeError(f"Inconsistent pagination in {path}")
            page += 1

    def skipped(kind, identity, reason):
        audit["skipped"].append({"kind": kind, "id": identity, "reason": reason})

    def parent_id(artifact):
        identity = artifact.get("workflow_run", {}).get("id")
        if type(identity) is not int or identity <= 0:
            raise RuntimeError(f"Missing parent run for artifact {artifact['id']}")
        return identity

    def validate_run(run, expected_id):
        if run is None or run.get("id") != expected_id:
            raise RuntimeError(f"Cannot verify parent/run {expected_id}")
        if not isinstance(run.get("status"), str):
            raise RuntimeError(f"Missing status for run {expected_id}")
        timestamp(run["created_at"])
        timestamp(run["updated_at"])
        return run

    def artifact_reason(artifact, run):
        if artifact["id"] in protected_artifacts:
            return "protected_artifact"
        if str(run["id"]) == str(current_run_id):
            return "current_run"
        if run["status"] != "completed":
            return "parent_not_completed"
        if max(timestamp(artifact["created_at"]), timestamp(run["updated_at"])) >= artifact_cutoff:
            return "within_artifact_retention_or_recent_rerun"
        return None

    def run_reason(run):
        if run["id"] in protected_runs:
            return "protected_run"
        if str(run["id"]) == str(current_run_id):
            return "current_run"
        if run["status"] != "completed":
            return "run_not_completed"
        if max(timestamp(run["created_at"]), timestamp(run["updated_at"])) >= run_cutoff:
            return "within_run_retention_or_recent_rerun"
        return None

    def attached_reason(attached, run):
        for item in attached:
            linked_run = item.get("workflow_run", {}).get("id", run["id"])
            if linked_run != run["id"]:
                raise RuntimeError(f"Unexpected artifact parent in run {run['id']}")
            if item["id"] not in artifact_ids:
                return "attachment_missing_from_global_snapshot"
            reason = artifact_reason(item, run)
            if reason:
                return "retained_attachment:" + reason
        return None

    def artifact_record(artifact, run_id):
        size = artifact.get("size_in_bytes")
        if type(size) is not int or size < 0:
            raise RuntimeError(f"Missing size for artifact {artifact['id']}")
        return {"id": artifact["id"], "run_id": run_id,
                "name": artifact.get("name", ""), "size_in_bytes": size,
                "created_at": artifact["created_at"]}

    try:
        artifacts = listing("/actions/artifacts", "artifacts")
        artifact_ids = {a["id"] for a in artifacts}
        runs = listing("/actions/runs", "workflow_runs")
        run_by_id = {item["id"]: validate_run(item, item["id"]) for item in runs}
        audit["snapshot"] = {"artifacts": len(artifacts), "runs": len(runs)}

        def snapshot_parent(artifact):
            identity = parent_id(artifact)
            if identity not in run_by_id:
                run_by_id[identity] = validate_run(request(f"/actions/runs/{identity}"), identity)
            return run_by_id[identity]

        # Explicit manual selections are exact holds, not a prefix-only exemption.
        for artifact in artifacts:
            match = SELECTED_NAME.fullmatch(artifact.get("name", ""))
            if not match:
                continue
            run = snapshot_parent(artifact)
            purpose, product, architecture, source_sha, attempt = match.groups()
            if (run.get("event") == "workflow_dispatch"
                    and run.get("path") == SELECTED_WORKFLOWS[product]
                    and run.get("head_sha") == source_sha
                    and type(run.get("run_attempt")) is int
                    and int(attempt) <= run["run_attempt"]):
                protected_artifacts.add(artifact["id"])
                protected_runs.add(run["id"])
                audit["dynamic_selected_holds"].append({
                    "artifact_id": artifact["id"], "run_id": run["id"],
                    "purpose": purpose, "product": product,
                    "architecture": architecture, "source_sha": source_sha,
                    "attempt": int(attempt),
                })
        audit["protected_artifact_ids"] = sorted(protected_artifacts)
        audit["protected_run_ids"] = sorted(protected_runs)

        artifact_plan, run_plan, attached_snapshot = [], [], {}
        for artifact in artifacts:
            if artifact["id"] in protected_artifacts:
                skipped("artifact", artifact["id"], "protected_artifact")
                continue
            if timestamp(artifact["created_at"]) >= artifact_cutoff:
                skipped("artifact", artifact["id"], "within_artifact_retention")
                continue
            parent = snapshot_parent(artifact)
            reason = artifact_reason(artifact, parent)
            if reason:
                skipped("artifact", artifact["id"], reason)
            else:
                artifact_plan.append(artifact_record(artifact, parent["id"]))

        # Any list or parent-lookup failure in preflight stops all deletion.
        for run in runs:
            reason = run_reason(run)
            if not reason:
                attached = listing(f"/actions/runs/{run['id']}/artifacts", "artifacts")
                attached_snapshot[run["id"]] = {a["id"] for a in attached}
                reason = attached_reason(attached, run)
                for item in attached:
                    artifact_record(item, run["id"])
            if reason:
                skipped("run", run["id"], reason)
            else:
                run_plan.append(run["id"])
        audit["planned_counts"] = {"artifacts": len(artifact_plan), "runs": len(run_plan)}

        operation["stage"] = "artifacts"
        for planned in artifact_plan:
            path = f"/actions/artifacts/{planned['id']}"
            current = request(path)
            if current is None:
                skipped("artifact", planned["id"], "already_missing")
                continue
            if current.get("id") != planned["id"] or parent_id(current) != planned["run_id"]:
                raise RuntimeError(f"Artifact identity changed for {planned['id']}")
            parent = validate_run(request(f"/actions/runs/{planned['run_id']}"), planned["run_id"])
            reason = artifact_reason(current, parent)
            if reason:
                skipped("artifact", planned["id"], reason)
                continue
            record = artifact_record(current, parent["id"])
            audit["candidates"]["artifacts"].append(record)
            if delete:
                if request(path, "DELETE") is False:
                    skipped("artifact", planned["id"], "already_missing_at_delete")
                else:
                    audit["deleted"]["artifacts"].append(record)
            print(f"{'Selected for deletion' if delete else 'Selected'} artifact {planned['id']}", flush=True)

        operation["stage"] = "runs"
        deleted_artifacts = {a["id"] for a in audit["deleted"]["artifacts"]}
        for identity in run_plan:
            path = f"/actions/runs/{identity}"
            current = request(path)
            if current is None:
                skipped("run", identity, "already_missing")
                continue
            validate_run(current, identity)
            reason = run_reason(current)
            if not reason:
                attached = listing(path + "/artifacts", "artifacts")
                if not {a["id"] for a in attached}.issubset(attached_snapshot[identity]):
                    reason = "attachment_set_changed"
                else:
                    reason = attached_reason(attached, current)
            if reason:
                skipped("run", identity, reason)
                continue
            # Recheck after pagination as a re-run may have started while listing.
            latest = request(path)
            if latest is None:
                skipped("run", identity, "already_missing")
                continue
            validate_run(latest, identity)
            reason = run_reason(latest)
            if reason or latest["updated_at"] != current["updated_at"]:
                skipped("run", identity, reason or "run_updated_during_attachment_check")
                continue
            remaining = [artifact_record(a, identity) for a in attached if a["id"] not in deleted_artifacts]
            record = {"id": identity, "conclusion": latest.get("conclusion"),
                      "remaining_artifact_ids": [a["id"] for a in remaining],
                      "remaining_artifact_bytes": sum(a["size_in_bytes"] for a in remaining)}
            audit["candidates"]["runs"].append(record)
            if delete:
                if request(path, "DELETE") is False:
                    skipped("run", identity, "already_missing_at_delete")
                else:
                    audit["deleted"]["runs"].append(record)
            print(f"{'Selected for deletion' if delete else 'Selected'} run {identity}", flush=True)
        audit["completed"] = True
    except Exception as error:
        audit["failures"].append({**operation, "type": type(error).__name__, "message": str(error)})
        raise
    finally:
        audit["summary"] = {
            "candidate_artifacts": len(audit["candidates"]["artifacts"]),
            "candidate_runs": len(audit["candidates"]["runs"]),
            "candidate_artifact_bytes": sum(a["size_in_bytes"] for a in audit["candidates"]["artifacts"]),
            "deleted_artifacts": len(audit["deleted"]["artifacts"]),
            "deleted_runs": len(audit["deleted"]["runs"]),
            "deleted_artifact_bytes": sum(a["size_in_bytes"] for a in audit["deleted"]["artifacts"]),
            "deleted_run_cascade_bytes": sum(r["remaining_artifact_bytes"] for r in audit["deleted"]["runs"]),
            "skipped": len(audit["skipped"]), "failures": len(audit["failures"]),
        }
    return {"artifacts": len(audit["candidates"]["artifacts"]),
            "runs": len(audit["candidates"]["runs"])}


def main():
    parser = argparse.ArgumentParser(description="Five-day artifacts/seven-day runs with exact evidence holds")
    parser.add_argument("--delete", action="store_true", help="Execute deletions; default is read-only")
    parser.add_argument("--report", default="cleanup-report.json", help="Write a JSON audit report, including partial failures")
    args = parser.parse_args()
    report = {"schema": "yime-actions-cleanup-report-v1", "completed": False,
              "delete_enabled": args.delete, "failures": []}
    try:
        protected_artifacts, protected_runs = load_protection(
            Path(__file__).with_name("retention-protected.json"), os.environ["GITHUB_REPOSITORY"])
        base = os.environ["GITHUB_API_URL"] + "/repos/" + os.environ["GITHUB_REPOSITORY"]
        headers = {
            "Authorization": "Bearer " + os.environ["GH_TOKEN"],
            "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "Yime-CI-cleanup",
        }

        def api(path, method="GET"):
            request = urllib.request.Request(base + path, headers=headers, method=method)
            try:
                with urllib.request.urlopen(request, timeout=60) as response:
                    return True if method == "DELETE" else json.loads(response.read() or "null")
            except urllib.error.HTTPError as error:
                if error.code == 404:
                    return False if method == "DELETE" else None
                raise

        now = dt.datetime.now(dt.timezone.utc)
        report["started_at_utc"] = now.isoformat()
        report["repository"] = os.environ["GITHUB_REPOSITORY"]
        cleanup(api, protected_artifacts, protected_runs,
                now - dt.timedelta(days=ARTIFACT_DAYS), os.environ["GITHUB_RUN_ID"], args.delete,
                run_cutoff=now - dt.timedelta(days=RUN_DAYS), report=report)
    except Exception as error:
        if not report["failures"]:
            report["failures"].append({"stage": "initialization", "type": type(error).__name__, "message": str(error)})
        raise
    finally:
        report["finished_at_utc"] = dt.datetime.now(dt.timezone.utc).isoformat()
        path = Path(args.report)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        summary = (f"Delete enabled: {args.delete}; completed: {report['completed']}\n\n"
                   f"Policy: ordinary artifacts {ARTIFACT_DAYS} days; runs/logs {RUN_DAYS} days.\n\n"
                   f"Results: {json.dumps(report.get('summary', {}), sort_keys=True)}\n\n"
                   f"Audit report: {args.report}\n")
        print(summary, flush=True)
        if os.environ.get("GITHUB_STEP_SUMMARY"):
            with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as stream:
                stream.write(summary)


if __name__ == "__main__":
    main()
