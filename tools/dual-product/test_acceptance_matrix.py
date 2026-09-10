import copy
import importlib.util
import json
from pathlib import Path
import unittest

HERE = Path(__file__).parent
SPEC = importlib.util.spec_from_file_location("acceptance_matrix", HERE / "acceptance_matrix.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class MatrixTests(unittest.TestCase):
    def setUp(self):
        self.plan = json.loads((HERE / "acceptance-matrix.json").read_text(encoding="utf-8"))

    def test_all_lanes_and_preserved_peer(self):
        result = MODULE.expand(self.plan)
        self.assertEqual(len(result["rows"]), 46)
        self.assertEqual(len({row['id'] for row in result['rows']}), 46)
        for row in result["rows"]:
            self.assertEqual(row["peer"] in row["before_products"], row["peer"] in row["after_products"])
            if row["operation"] == "failed-upgrade-rollback":
                self.assertEqual(row["before_products"], row["after_products"])
            if row["operation"] == "uninstall":
                self.assertNotIn(row["target"], row["after_products"])
        self.assertIs(result["three_choice_entry_admitted"], False)

    def test_each_product_maintained_under_each_order(self):
        rows = MODULE.expand(self.plan)['rows']
        for order in (['yimecore', 'rime-pime'], ['rime-pime', 'yimecore']):
            for target in order:
                with self.subTest(order=order, target=target):
                    actual = {r['operation'] for r in rows
                              if r['installation_order'] == order and r['target'] == target}
                    expected = MODULE.OPERATIONS - ({'install'} if target == order[0] else set())
                    self.assertEqual(actual, expected)

    def test_reinstall_retains_order_and_requires_prior_removal(self):
        rows = [r for r in MODULE.expand(self.plan)['rows'] if r['operation'] == 'reinstall']
        self.assertEqual(len(rows), 6)
        for row in rows:
            self.assertNotIn(row['target'], row['before_products'])
            self.assertIn(row['target'], row['after_products'])
            self.assertIn('prior-uninstall-evidence', row['required_evidence'])
            self.assertIn('retained-user-data-binding', row['required_evidence'])
            self.assertIn('settings-learning-reopen', row['required_evidence'])

    def test_invalid_order_rejected(self):
        for order in (None, 'yimecore', [], ['yimecore', 'yimecore'], ['other', 'yimecore']):
            changed = copy.deepcopy(self.plan)
            changed['lanes'][-1]['installation_order'] = order
            with self.subTest(order=order), self.assertRaises(ValueError):
                MODULE.expand(changed)

    def test_no_first_product_maintenance_lane_can_be_omitted(self):
        for index, lane in enumerate(self.plan['lanes']):
            if lane['peer_installed'] and lane['installation_order'][0] == lane['target']:
                changed = copy.deepcopy(self.plan)
                changed['lanes'].pop(index)
                with self.assertRaises(ValueError): MODULE.expand(changed)

    def test_old_plan_schema_is_not_silently_promoted(self):
        self.plan['schema_version'] = 'yime-dual-product-acceptance-plan-v1'
        with self.assertRaises(ValueError): MODULE.expand(self.plan)

    def test_missing_reverse_order_rejected(self):
        self.plan["lanes"].pop()
        with self.assertRaises(ValueError): MODULE.expand(self.plan)

    def test_duplicate_lane_does_not_count_as_coverage(self):
        self.plan["lanes"][-1] = copy.deepcopy(self.plan["lanes"][0])
        with self.assertRaises(ValueError): MODULE.expand(self.plan)

    def test_every_evidence_requirement_is_enforced(self):
        for op, requirements in self.plan["evidence_by_operation"].items():
            for requirement in requirements:
                with self.subTest(op=op, requirement=requirement):
                    changed = copy.deepcopy(self.plan)
                    changed["evidence_by_operation"][op].remove(requirement)
                    with self.assertRaises(ValueError): MODULE.expand(changed)

    def test_peer_and_default_protections_cannot_be_dropped(self):
        for dimension in self.plan["protected_dimensions"]:
            changed = copy.deepcopy(self.plan)
            changed["protected_dimensions"].remove(dimension)
            with self.assertRaises(ValueError): MODULE.expand(changed)

    def test_plan_cannot_claim_execution_or_pass(self):
        for flag in ("execution_authorized", "installed_acceptance_passed", "three_choice_entry_admitted"):
            for value in (True, 0, "false", None):
                changed = copy.deepcopy(self.plan)
                changed[flag] = value
                with self.assertRaises(ValueError): MODULE.expand(changed)

    def test_peer_presence_requires_boolean(self):
        self.plan["lanes"][0]["peer_installed"] = 0
        with self.assertRaises(ValueError): MODULE.expand(self.plan)

    def test_no_unbound_machine_or_package(self):
        for field in self.plan["binding_fields"]:
            changed = copy.deepcopy(self.plan)
            changed["binding_fields"].remove(field)
            with self.assertRaises(ValueError): MODULE.expand(changed)


if __name__ == "__main__":
    unittest.main()
