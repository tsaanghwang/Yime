"""Validate an explicit package request and record uploaded artifact identity.

Selected names are recognized only for these trusted manual workflows by cleanup.
They still expire on GitHub; this receipt does not prove an external archive exists.
"""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import subprocess


def select_request(event, purpose, architecture, reason, source_sha, checkout_sha):
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha) or checkout_sha != source_sha:
        raise ValueError("Actual checkout must match the recorded event source SHA")
    # Non-dispatch events never select packages, even if arbitrary environment
    # variables or a PR payload happen to contain similarly named fields.
    if event != "workflow_dispatch":
        purpose, architecture, reason = "checks-only", "both", ""
    if purpose not in ("checks-only", "delivery", "reproduction"):
        raise ValueError("Unknown package purpose")
    if architecture not in ("x64", "arm64", "both"):
        raise ValueError("Unknown package architecture")
    reason = reason.strip()
    if purpose != "checks-only" and not reason:
        raise ValueError("A selected delivery or reproduction package needs a reason")
    if len(reason) > 1000:
        raise ValueError("Package reason must be at most 1000 characters")
    selected = purpose != "checks-only"
    return {
        "schema": "yime-selected-package-request-v1",
        "source_sha": source_sha,
        "purpose": purpose,
        "reason": reason,
        "architecture": architecture,
        "upload_x64": selected and architecture in ("x64", "both"),
        "upload_arm64": selected and architecture in ("arm64", "both"),
    }


def uploaded_receipt(request, architecture, artifact_id, artifact_digest,
                     artifact_url, run_id, attempt):
    if architecture not in ("x64", "arm64") or not request.get("upload_" + architecture):
        raise ValueError("The uploaded architecture was not explicitly requested")
    if not str(artifact_id).isdigit() or int(artifact_id) <= 0:
        raise ValueError("Missing uploaded artifact ID")
    digest = artifact_digest.removeprefix("sha256:")
    if not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise ValueError("Missing uploaded artifact SHA-256")
    if not str(run_id).isdigit() or int(run_id) <= 0 or not str(attempt).isdigit() or int(attempt) <= 0:
        raise ValueError("Invalid workflow run identity")
    return {
        **request,
        "schema": "yime-selected-package-upload-v1",
        "architecture": architecture,
        "artifact_id": int(artifact_id),
        "sha256": digest,
        "artifact_url": artifact_url,
        "run_id": int(run_id),
        "run_attempt": int(attempt),
        "recorded_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "external_archive_verified": False,
        "note": "The selected workflow naming contract exempts this upload from routine cleanup, not GitHub expiry. Archive the original ZIP before platform expiry.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("request", "receipt"))
    parser.add_argument("--request", default=".generated/ci-package-request.json")
    parser.add_argument("--architecture", choices=("x64", "arm64"))
    parser.add_argument("--output-dir", default=".generated/selected-package-receipts")
    args = parser.parse_args()
    request_path = Path(args.request)
    if args.mode == "request":
        actual_sha = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
        request = select_request(
            os.environ["GITHUB_EVENT_NAME"], os.environ.get("PACKAGE_PURPOSE") or "checks-only",
            os.environ.get("PACKAGE_ARCHITECTURE") or "both", os.environ.get("PACKAGE_REASON", ""),
            os.environ["GITHUB_SHA"], actual_sha)
        request_path.parent.mkdir(parents=True, exist_ok=True)
        request_path.write_text(json.dumps(request, indent=2) + "\n", encoding="utf-8")
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
            for arch in ("x64", "arm64"):
                output.write(f"upload_{arch}={str(request['upload_' + arch]).lower()}\n")
        return
    request = json.loads(request_path.read_text(encoding="utf-8"))
    receipt = uploaded_receipt(request, args.architecture, os.environ.get("ARTIFACT_ID", ""),
                               os.environ.get("ARTIFACT_DIGEST", ""), os.environ.get("ARTIFACT_URL", ""),
                               os.environ["GITHUB_RUN_ID"], os.environ["GITHUB_RUN_ATTEMPT"])
    directory = Path(args.output_dir)
    directory.mkdir(parents=True, exist_ok=True)
    serialized = json.dumps(receipt, indent=2)
    (directory / (args.architecture + ".json")).write_text(serialized + "\n", encoding="utf-8")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as summary:
            summary.write("\nSelected package upload identity (not an archival receipt):\n\n```json\n" + serialized + "\n```\n")


if __name__ == "__main__":
    main()
