"""Offline source wiring contracts; not Windows/TSF execution evidence."""
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
class DiagnosticContract(unittest.TestCase):
 def read(self, path): return (ROOT / path).read_text(encoding='utf-8')
 def test_broker_response_stays_same(self):
  s=self.read('go-backend/internal/touchbroker/broker.go')
  self.assertIn('r.Error = reason', s)
  self.assertIn('return reject("action rejected")', s)
  self.assertIn('writeRejectionDiagnostic(os.Stderr, "dispatch", e)', s)
 def test_broker_helper_never_serializes_request(self):
  s=self.read('go-backend/internal/touchbroker/rejection_diagnostic.go')
  self.assertNotIn('json.Marshal', s)
  self.assertNotIn('fmt.', s)
  self.assertIn('defer func() { _ = recover() }()', s)
  self.assertIn('reason := "unclassified"', s)
 def test_native_identity_and_focus_gates_retained(self):
  s=self.read('YimeTextServiceExperiment/TextService.cpp')
  self.assertIn('RPC_E_WRONG_THREAD', s)
  s=self.read('YimeTextServiceExperiment/tests/Formal18uHost.cpp')
  for text in ('registered profile mismatch', 'registered DLL mismatch', 'TF_IPPMF_FORPROCESS', 'require(hr,"engine input")'):
   self.assertIn(text, s)
 def test_no_retry_or_new_timeout(self):
  s=self.read('YimeTextServiceExperiment/tests/Formal18uHost.cpp')
  self.assertIn('DWORD timeout=15000',s)
  self.assertIn('host.awaitResult(hr,&initial,95000)',s)
  self.assertIn('if(GetTickCount64()>=deadline)',s)
 def test_route_no_replay(self):
  s=self.read('YimeTextServiceExperiment/DedicatedTouchRoute.cpp')
  self.assertIn('{"retryAllowed",false}',s)
  self.assertIn('editEpoch_!=epoch_',s)
  self.assertIn('pendingEpoch_==epoch_',s)
if __name__=='__main__': unittest.main()
