package activatedloop

import (
 "bytes"
 "encoding/json"
 "errors"
 "io"
 "reflect"
)

type Failure struct { Stage string `json:"stage"`; Kind string `json:"kind"`; Code uint32 `json:"code"` }
const DedicatedLayoutSHA256 = "995f1a74f129249febbd09ca11a8266f6e0c94bac8c05c57754859fc3be3349c"
const DedicatedDictionarySHA256 = "43a74f4e47c7100f222a744f487762f1c31222c5f80b9a34fd24cbebc7e96353"
type SessionIdentity struct { LayoutSHA256 string `json:"layoutSHA256"`; DictionarySHA256 string `json:"dictionarySHA256"`; Mode string `json:"mode"`; SessionPolicy string `json:"sessionPolicy"` }
type SessionFocus struct { Context string `json:"context"`; Epoch uint64 `json:"epoch"` }
type SessionBinding struct { SessionID string `json:"sessionId"`; Identity SessionIdentity `json:"identity"`; Focus SessionFocus `json:"focus"` }
// TF_E_DISCONNECTED: MAKE_HRESULT(SEVERITY_ERROR, FACILITY_ITF, 0x0504).
// https://raw.githubusercontent.com/microsoft/win32metadata/main/generation/WinSDK/RecompiledIdlHeaders/um/msctf.h
const DisconnectedHRESULT uint32 = 0x80040504
type HostResult struct {
 EditAttempts uint32 `json:"editAttempts"`
 Stage string `json:"stage"`; Scenario string `json:"scenario"`; ActualDLLLoaded bool `json:"actualDLLLoaded"`
 ActivationIdentity string `json:"activationIdentity"`; Registered bool `json:"registered"`; SendInput bool `json:"sendInput"`
 Outcome string `json:"outcome"`; Rejected bool `json:"rejected"`; DuplicateRejected bool `json:"duplicateRejected"`
 ReadbackMatches bool `json:"readbackMatches"`; ReadbackEmpty bool `json:"readbackEmpty"`; OtherContextEmpty bool `json:"otherContextEmpty"`
 UnknownAfterPendingEditCovered bool `json:"unknownAfterPendingEditCovered"`; OperationPendingObserved bool `json:"operationPendingObserved"`
 PostWriteDisconnectObserved bool `json:"postWriteDisconnectObserved"`; ReplayRejected bool `json:"replayRejected"`; HostCleanupVerified bool `json:"hostCleanupVerified"`; SessionBinding SessionBinding `json:"sessionBinding"`
}
type NativeResult struct {
 PostCleanupRouteRevoked bool `json:"postCleanupRouteRevoked"`; PostCleanupRouteCode *uint32 `json:"postCleanupRouteCode"`
 Schema string `json:"schema"`; Status string `json:"status"`; WritesStarted bool `json:"writesStarted"`; CleanupVerified bool `json:"cleanupVerified"`
 OperationFailure *Failure `json:"operationFailure"`; CleanupFailure *Failure `json:"cleanupFailure"`; HostResult *HostResult `json:"hostResult"`
 HostPID uint32 `json:"hostPID"`; BrokerPID *uint32 `json:"brokerPID"`; WindowsSessionID *uint32 `json:"windowsSessionID"`
 BrokerCreationTime *uint64 `json:"brokerCreationTime"`; LedgerOwnerPID *uint32 `json:"ledgerOwnerPID"`; LedgerOwnerCreationTime *uint64 `json:"ledgerOwnerCreationTime"`
 PublisherTrust string `json:"publisherTrust"`
}
// Walk all nested objects so encoding/json's last-key-wins behavior cannot hide
// conflicting evidence. No arrays, raw payload, or extensible envelope is used.
func checkJSON(d *json.Decoder,depth int)error {
 if depth>8{return errors.New("JSON depth")};tok,err:=d.Token();if err!=nil{return err}
 if delimiter,ok:=tok.(json.Delim);ok {
  if delimiter!='{'{return errors.New("unexpected JSON container")};seen:=map[string]bool{}
  for d.More(){key,e:=d.Token();name,ok:=key.(string);if e!=nil||!ok||seen[name]{return errors.New("duplicate JSON field")};seen[name]=true;if e=checkJSON(d,depth+1);e!=nil{return e}}
  end,e:=d.Token();if e!=nil||end!=json.Delim('}'){return errors.New("JSON object end")}
 }
 return nil
}
func decodeExact(raw []byte,target any,nullable map[string]bool)error {
 if len(raw)==0||len(raw)>16384{return errors.New("evidence bound")}
 d:=json.NewDecoder(bytes.NewReader(raw));if err:=checkJSON(d,0);err!=nil{return err};if _,err:=d.Token();err!=io.EOF{return errors.New("trailing JSON")}
 var values map[string]json.RawMessage;if json.Unmarshal(raw,&values)!=nil{return errors.New("JSON object required")}
 t:=reflect.TypeOf(target).Elem();if len(values)!=t.NumField(){return errors.New("evidence fields")}
 for i:=0;i<t.NumField();i++{name:=t.Field(i).Tag.Get("json");v,ok:=values[name];if !ok||bytes.Equal(bytes.TrimSpace(v),[]byte("null"))&&!nullable[name]{return errors.New("missing/null evidence")}}
 d=json.NewDecoder(bytes.NewReader(raw));d.DisallowUnknownFields();if err:=d.Decode(target);err!=nil{return errors.New("evidence type")};return nil
}
func DecodeNative(raw []byte)(NativeResult,error){
 var n NativeResult
 nullable:=map[string]bool{"postCleanupRouteCode":true,"operationFailure":true,"cleanupFailure":true,"hostResult":true,"brokerPID":true,"windowsSessionID":true,"brokerCreationTime":true,"ledgerOwnerPID":true,"ledgerOwnerCreationTime":true}
 if err:=decodeExact(raw,&n,nullable);err!=nil{return n,err}
 var fields map[string]json.RawMessage;_ = json.Unmarshal(raw,&fields)
 if n.HostResult!=nil {
  if err:=decodeExact(fields["hostResult"],n.HostResult,nil);err!=nil{return n,err}
  var hostFields map[string]json.RawMessage;_ = json.Unmarshal(fields["hostResult"],&hostFields)
  if err:=decodeExact(hostFields["sessionBinding"],&n.HostResult.SessionBinding,nil);err!=nil{return n,err}
  var bindingFields map[string]json.RawMessage;_ = json.Unmarshal(hostFields["sessionBinding"],&bindingFields)
  if err:=decodeExact(bindingFields["identity"],&n.HostResult.SessionBinding.Identity,nil);err!=nil{return n,err}
  if err:=decodeExact(bindingFields["focus"],&n.HostResult.SessionBinding.Focus,nil);err!=nil{return n,err}
 }
 for name,failure:=range map[string]*Failure{"operationFailure":n.OperationFailure,"cleanupFailure":n.CleanupFailure}{if failure!=nil{if err:=decodeExact(fields[name],failure,nil);err!=nil{return n,err}}}
 if n.Schema!="activated-loop-result-v1"||n.PublisherTrust!="not-established"{return n,errors.New("native identity")}
 return n,nil
}
func ValidateNative(raw []byte,hostPID,brokerPID int)error {
 n,err:=DecodeNative(raw);if err!=nil{return err}
 if !n.PostCleanupRouteRevoked||n.PostCleanupRouteCode==nil||*n.PostCleanupRouteCode!=DisconnectedHRESULT{return errors.New("old provider route not revoked after cleanup")}
 if n.Status!="passed"||!n.WritesStarted||!n.CleanupVerified||n.OperationFailure!=nil||n.CleanupFailure!=nil||n.HostResult==nil||n.HostPID!=uint32(hostPID)||n.BrokerPID==nil||*n.BrokerPID!=uint32(brokerPID)||n.LedgerOwnerPID==nil||*n.LedgerOwnerPID!=uint32(hostPID)||n.WindowsSessionID==nil||n.BrokerCreationTime==nil||*n.BrokerCreationTime==0||n.LedgerOwnerCreationTime==nil||*n.LedgerOwnerCreationTime==0{return errors.New("native operation/ownership/cleanup")}
 h:=n.HostResult
 binding:=h.SessionBinding
 if len(binding.SessionID)==0||len(binding.SessionID)>256||len(binding.Focus.Context)==0||len(binding.Focus.Context)>256||binding.Focus.Epoch==0||binding.Identity.LayoutSHA256!=DedicatedLayoutSHA256||binding.Identity.DictionarySHA256!=DedicatedDictionarySHA256||binding.Identity.Mode!="variable"||binding.Identity.SessionPolicy!="concept-keyboard-modes-v2+ellipsis-choice-v1"{return errors.New("dedicated session identity/focus")}
 if h.EditAttempts!=1{return errors.New("exactly one edit attempt required")}
 if h.Stage!="result"||h.Scenario!="commit"||!h.ActualDLLLoaded||h.ActivationIdentity!="windows-activated-profile"||!h.Registered||h.SendInput||h.Outcome!="applied"||h.Rejected||h.DuplicateRejected||!h.ReadbackMatches||h.ReadbackEmpty||!h.OtherContextEmpty||h.UnknownAfterPendingEditCovered||h.OperationPendingObserved||h.PostWriteDisconnectObserved||h.ReplayRejected||!h.HostCleanupVerified{return errors.New("actual edit/readback unproven")}
 return nil
}
func connected(raw []byte)error{var value struct{Stage string `json:"stage"`;Accepted bool `json:"accepted"`};if err:=decodeExact(raw,&value,nil);err!=nil{return err};if value.Stage!="connected"||!value.Accepted{return errors.New("native connect rejected")};return nil}
