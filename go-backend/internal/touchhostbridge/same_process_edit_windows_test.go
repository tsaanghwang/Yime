//go:build windows && amd64

package touchhostbridge

import (
	"errors"
	"testing"
)

type sameProcessEditResult struct {
	Schema                     string `json:"schema"`
	Stage                      string `json:"stage"`
	Scenario                   string `json:"scenario"`
	Status                     string `json:"status"`
	ActivationIdentity         string `json:"activationIdentity"`
	WindowsActivatedInstance   bool   `json:"windowsActivatedInstance"`
	SendInput                  bool   `json:"sendInput"`
	OperationPendingObserved   bool   `json:"operationPendingObserved"`
	EditAttempts               uint32 `json:"editAttempts"`
	AppliedReceipt             bool   `json:"appliedReceipt"`
	ReadbackMatches            bool   `json:"readbackMatches"`
	RegistrationOwnerPID       uint32 `json:"registrationOwnerPID"`
	BrokerTargetPID            uint32 `json:"brokerTargetPID"`
	RegistrationLifecycleOwned bool   `json:"registrationLifecycleOwned"`
	CleanupVerified            bool   `json:"cleanupVerified"`
	RouteRevoked               bool   `json:"routeRevoked"`
}

func validateSameProcessEditResult(raw []byte, expectedPID uint32) error {
	var r sameProcessEditResult
	if err := decodeFormalEnvelope(raw, &r); err != nil {
		return err
	}
	if expectedPID == 0 || r.RegistrationOwnerPID != expectedPID || r.BrokerTargetPID != expectedPID ||
		r.Schema != "18u-same-process-registered-edit-v1" || r.Stage != "result" ||
		r.Scenario != "commit" || r.Status != "pass" || r.ActivationIdentity != "windows-activated-profile" ||
		!r.WindowsActivatedInstance || r.SendInput || !r.OperationPendingObserved ||
		r.EditAttempts != 1 || !r.AppliedReceipt || !r.ReadbackMatches ||
		!r.RegistrationLifecycleOwned || !r.CleanupVerified || !r.RouteRevoked {
		return errors.New("same-process registration, single edit or revocation not proven")
	}
	return nil
}

func TestFormalSameProcessEvidence(t *testing.T) {
	r := sameProcessEditResult{
		Schema: "18u-same-process-registered-edit-v1", Stage: "result", Scenario: "commit",
		Status: "pass", ActivationIdentity: "windows-activated-profile", WindowsActivatedInstance: true,
		OperationPendingObserved: true, EditAttempts: 1, AppliedReceipt: true, ReadbackMatches: true,
		RegistrationOwnerPID: 37, BrokerTargetPID: 37, RegistrationLifecycleOwned: true,
		CleanupVerified: true, RouteRevoked: true,
	}
	if validateSameProcessEditResult(mustJSON(r), 37) != nil {
		t.Fatal("complete evidence rejected")
	}
	for _, mutate := range []func(*sameProcessEditResult){
		func(v *sameProcessEditResult) { v.BrokerTargetPID++ },
		func(v *sameProcessEditResult) { v.RegistrationOwnerPID++ },
		func(v *sameProcessEditResult) { v.EditAttempts = 2 },
		func(v *sameProcessEditResult) { v.WindowsActivatedInstance = false },
		func(v *sameProcessEditResult) { v.AppliedReceipt = false },
		func(v *sameProcessEditResult) { v.ReadbackMatches = false },
		func(v *sameProcessEditResult) { v.CleanupVerified = false },
		func(v *sameProcessEditResult) { v.RouteRevoked = false },
	} {
		bad := r
		mutate(&bad)
		if validateSameProcessEditResult(mustJSON(bad), 37) == nil {
			t.Fatal("incomplete or foreign-process evidence accepted")
		}
	}
}
