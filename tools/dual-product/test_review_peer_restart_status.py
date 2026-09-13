import hashlib
import json
import unittest
from review_peer_restart_status import inspect_status


class StatusReviewTests(unittest.TestCase):
    def fixture(self):
        h = 'a' * 64
        stats = dict(active_version='v1', active_source_id='private source marker', active_sha256=h,
                     active_sessions=0, switches=0, rollbacks=0, rejected=0, load_mode='resident')
        value = dict(schema_version='yime-index-control-v1', request_id='startup', action='observe',
                     accepted=True, observed_at='2026-09-13T12:07:09Z', manager={},
                     managers={m: dict(stats) for m in ('variable', 'full', 'shorthand')})
        original = {'payload': {'files': [{'sha256': h}]}}
        return value, original

    def review(self, value, original):
        raw = json.dumps(value).encode()
        current = {'state': {'files': [{'path': 'index-control/status.json', 'bytes': len(raw),
                                      'sha256': hashlib.sha256(raw).hexdigest()}]}}
        return inspect_status(raw, original, current)

    def test_startup_hashes_and_no_private_text_or_rebase(self):
        value, original = self.fixture()
        result = self.review(value, original)
        self.assertTrue(result['matches_reported_snapshot'])
        self.assertTrue(result['startup_observation'])
        self.assertTrue(all(r['hash_in_original_payload'] for r in result['indexes']))
        self.assertNotIn('private source marker', json.dumps(result))
        self.assertFalse(result['recovery_admitted'])
        self.assertFalse(result['baseline_replaced'])

    def test_changed_index_and_control_error_are_visible(self):
        value, original = self.fixture()
        value.update(request_id='private request', action='swap', accepted=False, error='private error path')
        value['managers']['full']['active_sha256'] = 'b' * 64
        result = self.review(value, original)
        self.assertFalse(result['startup_observation'])
        self.assertTrue(result['error_present'])
        self.assertFalse(all(r['hash_in_original_payload'] for r in result['indexes']))
        self.assertNotIn('private', json.dumps(result))

    def test_unknown_shape_and_boolean_counter_rejected(self):
        value, original = self.fixture()
        value['unknown'] = 'private'
        with self.assertRaises(ValueError): self.review(value, original)
        del value['unknown']
        value['managers']['full']['switches'] = True
        with self.assertRaises(ValueError): self.review(value, original)

    def test_duplicate_and_oversize_rejected(self):
        for raw in (b'{"action":1,"action":2}', b' ' * 65537):
            with self.assertRaises(ValueError): inspect_status(raw, {}, {})


if __name__ == '__main__': unittest.main()
