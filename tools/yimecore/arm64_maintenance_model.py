"""Offline trust-boundary model. Never used by an installer or input runtime.

Evidence values represent independently verified observations, not fields read
from the candidate package's own manifest. No observation is implemented here.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class Evidence:
    official_system_shell: bool = False
    shell_signature_and_version: bool = False
    shell_arm64_pe: bool = False
    shell_native_process: bool = False
    launcher_in_admin_protected_location: bool = False
    launcher_hash_independently_approved: bool = False
    approval_record_admin_protected: bool = False
    package_source_authenticated: bool = False
    staging_admin_only_and_not_linked: bool = False
    staged_script_and_module_verified: bool = False
    elevated_native_arm64: bool = False
    elevated_administrator: bool = False
    same_user_sid: bool = False
    registration_tool_arm64: bool = False
    owned_files_available: bool = False


def decision(evidence: Evidence) -> tuple[bool, str]:
    """Return the first unmet trust condition; permit mutation only at the end."""
    for name in Evidence.__dataclass_fields__:
        if not getattr(evidence, name):
            return False, name
    return True, "trusted_preconditions_complete"
