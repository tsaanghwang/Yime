"""Offline mismatch tests. No directory is created and the probe is not run."""

from copy import deepcopy
import unittest

from directory_identity_contract import validate_directory_contract


EXPECTED = r"C:\vm\probe-directory-contract"
FINAL = r"\\?\C:\vm\probe-directory-contract"
RECORDED = {"event": "output-directory", "volume": "1122334455667788",
            "file_id": "0123456789abcdeffedcba9876543210", "final_path": FINAL,
            "sha256": "", "attributes": 0x10, "reparse_tag": 0}
OBSERVED = {key: value for key, value in RECORDED.items() if key not in ("event", "sha256")}
CREATION = {"event": "directory-create", "create_information": 2}


class DirectoryIdentityContractTests(unittest.TestCase):
    def check_rejected(self, *, recorded=None, observed=None, creation=None, expected=EXPECTED):
        with self.assertRaises(ValueError):
            validate_directory_contract(
                deepcopy(RECORDED if recorded is None else recorded),
                deepcopy(OBSERVED if observed is None else observed), expected,
                deepcopy(CREATION if creation is None else creation),
            )

    def test_matching_independent_handle(self):
        validate_directory_contract(deepcopy(RECORDED), deepcopy(OBSERVED), EXPECTED, deepcopy(CREATION))

    def test_wrong_create_disposition(self):
        self.check_rejected(creation={"event": "directory-create", "create_information": 1})

    def test_missing_create_disposition(self):
        self.check_rejected(creation={"event": "directory-create"})

    def test_volume_mismatch(self):
        observed = dict(OBSERVED, volume="1122334455667789")
        self.check_rejected(observed=observed)

    def test_low_half_file_id_mismatch(self):
        observed = dict(OBSERVED, file_id="1123456789abcdeffedcba9876543210")
        self.check_rejected(observed=observed)

    def test_high_half_file_id_mismatch(self):
        observed = dict(OBSERVED, file_id="0123456789abcdeffedcba9876543211")
        self.check_rejected(observed=observed)

    def test_short_file_id(self):
        self.check_rejected(observed=dict(OBSERVED, file_id="0123456789abcdef"))

    def test_zero_file_id(self):
        self.check_rejected(observed=dict(OBSERVED, file_id="0" * 32))

    def test_zero_volume(self):
        self.check_rejected(observed=dict(OBSERVED, volume="0" * 16))

    def test_nonhex_identity(self):
        self.check_rejected(observed=dict(OBSERVED, file_id="z" * 32))

    def test_not_a_directory(self):
        self.check_rejected(observed=dict(OBSERVED, attributes=0x20))

    def test_reparse_attribute(self):
        self.check_rejected(observed=dict(OBSERVED, attributes=0x410))

    def test_unexpected_reparse_tag(self):
        self.check_rejected(observed=dict(OBSERVED, reparse_tag=0xA0000003))

    def test_independent_final_path_mismatch(self):
        self.check_rejected(observed=dict(OBSERVED, final_path=r"\\?\C:\vm\other"))

    def test_both_handles_wrong_path(self):
        wrong = r"\\?\C:\vm\other"
        self.check_rejected(recorded=dict(RECORDED, final_path=wrong),
                            observed=dict(OBSERVED, final_path=wrong))

    def test_nonlocal_final_path(self):
        self.check_rejected(observed=dict(OBSERVED, final_path=r"\\?\UNC\host\share\probe"))

    def test_traversal_component(self):
        self.check_rejected(observed=dict(OBSERVED, final_path=r"\\?\C:\vm\other\..\probe-directory-contract"))

    def test_trailing_dot_component(self):
        self.check_rejected(observed=dict(OBSERVED, final_path=r"\\?\C:\vm.\probe-directory-contract"))

    def test_directory_hash_unexpected(self):
        self.check_rejected(recorded=dict(RECORDED, sha256="ab" * 32))


if __name__ == "__main__":
    unittest.main()
