"""Offline consistency check for the one-process registration/edit result.
Never launches a process, registers a profile, or authenticates an execution.
"""
import json

FIELDS = {
    "schema", "stage", "scenario", "status", "activationIdentity",
    "windowsActivatedInstance", "sendInput", "operationPendingObserved",
    "editAttempts", "appliedReceipt", "readbackMatches", "registrationOwnerPID",
    "brokerTargetPID", "registrationLifecycleOwned", "cleanupVerified", "routeRevoked",
}
TRUE_FIELDS = {
    "windowsActivatedInstance", "operationPendingObserved", "appliedReceipt",
    "readbackMatches", "registrationLifecycleOwned", "cleanupVerified", "routeRevoked",
}


def need(condition, reason):
    if not condition:
        raise ValueError(reason)


def strict_json(text):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            need(key not in result, "duplicate-field")
            result[key] = value
        return result
    return json.loads(text, object_pairs_hook=unique,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError("nonfinite-json")))


def validate(stdout, exit_code, expected_pid):
    need(type(stdout) is str and len(stdout.encode("utf-8")) <= 131072, "output-bound")
    need(type(exit_code) is int and exit_code == 0, "process-failed")
    need(type(expected_pid) is int and 0 < expected_pid <= 0xffffffff, "expected-process")
    lines = stdout.splitlines()
    need(len(lines) == 2, "two-records-required")
    connected, result = map(strict_json, lines)
    need(type(connected) is dict and set(connected) == {"stage", "accepted"}
         and connected["stage"] == "connected" and connected["accepted"] is True, "connect-unproven")
    need(type(result) is dict and set(result) == FIELDS, "result-fields")
    for key, value in {
        "schema": "18u-same-process-registered-edit-v1", "stage": "result",
        "scenario": "commit", "status": "pass", "activationIdentity": "windows-activated-profile",
    }.items():
        need(result[key] == value, "result-identity")
    need(all(result[key] is True for key in TRUE_FIELDS) and result["sendInput"] is False, "result-proof")
    need(type(result["editAttempts"]) is int and result["editAttempts"] == 1, "single-edit-required")
    for key in ("registrationOwnerPID", "brokerTargetPID"):
        need(type(result[key]) is int and result[key] == expected_pid, "same-process-required")
    return {"status": "evidence-consistent", "scope": "same-process-registration-single-edit",
            "nativeExecutionVerified": False, "sourceAuthenticityVerified": False}
