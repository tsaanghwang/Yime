"""Expand the DP2 acceptance specification, without accepting execution evidence.

This tool reads a plan only. No installation, registry, runtime or user-state API.
Its output is a work list, never a maintenance authorization or acceptance receipt.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

PRODUCTS = {"yimecore", "rime-pime"}
OPERATIONS = {"install", "upgrade", "failed-upgrade-rollback", "backup-restore",
              "reboot-logon", "registered-live-host", "uninstall", "reinstall"}
PROTECTED = {"peer_registration", "peer_payloads", "peer_process_identity",
             "peer_settings_learning", "peer_run_uninstall", "default_input_method"}
BINDINGS = {"target_machine_id", "initiating_sid", "architecture", "target_package_sha256",
            "target_source_identity", "peer_package_sha256_or_absent", "pre_state_sha256",
            "post_state_sha256", "native_evidence_sha256"}
REQUIRED = {
    "install": {"native-install-transaction", "registration-x64-x86", "standard-user-runtime-ready", "self-contained-package"},
    "upgrade": {"fresh-backup", "staging-before-disruption", "registration-x64-x86", "target-user-tip-value-kinds", "standard-user-runtime-ready"},
    "failed-upgrade-rollback": {"fresh-backup", "injected-failure", "original-registration-and-value-kinds", "original-payload-and-config", "original-running-state", "original-user-data"},
    "backup-restore": {"native-independent-archive", "archive-hashes", "actual-restore", "settings-learning-reopen", "standard-user-runtime-ready"},
    "reboot-logon": {"boot-after-maintenance", "system-run-value", "shell-logon-event", "live-pid-image-boot-owner", "standard-user-runtime-ready"},
    "registered-live-host": {"current-profile-activation", "x64-three-modes", "x86-wow64-three-modes", "physical-host-input", "shift-candidate-selection", "composition-cancellation"},
    "uninstall": {"directed-target-stop", "target-registration-absent", "target-run-uninstall-absent", "exact-owned-file-removal", "user-data-retained", "independent-recovery-retained"},
    "reinstall": {"prior-uninstall-evidence", "retained-user-data-binding", "native-install-transaction", "registration-x64-x86", "settings-learning-reopen", "standard-user-runtime-ready"},
}


def exact_list(value, expected, label):
    if not isinstance(value, list) or any(not isinstance(x, str) for x in value):
        raise ValueError(f"{label}: string list required")
    if len(value) != len(set(value)) or set(value) != expected:
        raise ValueError(f"{label}: missing, duplicate or unsupported requirement")


def expand(plan):
    fields = {"schema_version", "products", "lanes", "operations", "binding_fields",
              "protected_dimensions", "evidence_by_operation", "coverage_rule",
              "execution_authorized", "installed_acceptance_passed", "three_choice_entry_admitted"}
    if not isinstance(plan, dict) or set(plan) != fields:
        raise ValueError("Exact plan fields required")
    if plan["schema_version"] != "yime-dual-product-acceptance-plan-v2":
        raise ValueError("Unsupported plan schema")
    for flag in ("execution_authorized", "installed_acceptance_passed", "three_choice_entry_admitted"):
        if plan[flag] is not False:
            raise ValueError(f"A plan cannot grant {flag}")
    exact_list(plan["products"], PRODUCTS, "products")
    exact_list(plan["operations"], OPERATIONS, "operations")
    exact_list(plan["binding_fields"], BINDINGS, "bindings")
    exact_list(plan["protected_dimensions"], PROTECTED, "protection")
    if not isinstance(plan["evidence_by_operation"], dict) or set(plan["evidence_by_operation"]) != OPERATIONS:
        raise ValueError("Every operation needs evidence requirements")
    for operation in OPERATIONS:
        exact_list(plan["evidence_by_operation"][operation], REQUIRED[operation], operation)
    if plan["coverage_rule"] != "A row requires its own native evidence bound to its target, peer state and exact package; no inheritance from another row.":
        raise ValueError("Cross-row evidence reuse is not acceptance")
    if not isinstance(plan["lanes"], list):
        raise ValueError("Lanes must be a list")
    seen = set()
    for lane in plan["lanes"]:
        if not isinstance(lane, dict) or set(lane) != {"target", "peer_installed", "installation_order"}:
            raise ValueError("Invalid lane")
        if not isinstance(lane["target"], str) or lane["target"] not in PRODUCTS or type(lane["peer_installed"]) is not bool:
            raise ValueError("Invalid lane identity")
        order = lane["installation_order"]
        expected_products = PRODUCTS if lane["peer_installed"] else {lane["target"]}
        exact_list(order, expected_products, "installation_order")
        key = (lane["target"], lane["peer_installed"], tuple(order))
        if key in seen:
            raise ValueError("Duplicate lane")
        seen.add(key)
    expected_lanes = {(p, False, (p,)) for p in PRODUCTS}
    expected_lanes |= {(p, True, order) for p in PRODUCTS
                       for order in (("yimecore", "rime-pime"), ("rime-pime", "yimecore"))}
    if seen != expected_lanes:
        raise ValueError("Both products need maintenance coverage under both installation orders")
    rows = []
    for target, peer_installed, order in sorted(seen):
        peer = next(iter(PRODUCTS - {target}))
        peer_set = {peer} if peer_installed else set()
        for operation in sorted(OPERATIONS):
            # First install establishes the order; the first product cannot be
            # initially installed with the later product already present.
            if operation == "install" and peer_installed and order[0] == target:
                continue
            before = peer_set | (set() if operation in {"install", "reinstall"} else {target})
            after = peer_set | (set() if operation == "uninstall" else {target})
            rows.append({
                "id": f"{target}.{'-then-'.join(order)}.{operation}",
                "target": target, "peer": peer, "operation": operation,
                "installation_order": list(order),
                "before_products": sorted(before), "after_products": sorted(after),
                "required_evidence": sorted(REQUIRED[operation]),
                "protected_dimensions": sorted(PROTECTED),
                "binding_fields": sorted(BINDINGS),
                "peer_requirement": "unchanged" if peer_installed else "remains-absent",
                "status": "pending-native-evidence",
            })
    return {"schema_version": "yime-dual-product-acceptance-worklist-v2",
            "plan_valid": True, "rows": rows, "execution_authorized": False,
            "installed_acceptance_passed": False, "three_choice_entry_admitted": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", type=Path, default=Path(__file__).with_name("acceptance-matrix.json"))
    args = parser.parse_args()
    raw = args.plan.read_bytes()
    result = expand(json.loads(raw.decode("utf-8-sig")))
    result["plan_sha256"] = hashlib.sha256(raw).hexdigest()
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
