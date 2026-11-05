// Package installed18uhost adapts the existing registered formal-host protocol.
// It never registers, enables, removes, or recovers an installed product.
package installed18uhost

import("bufio";"context";"crypto/rand";"encoding/hex";"encoding/json";"errors";"io";"os";"path/filepath";"strconv";"strings";"sync";"time")
const Confirm="once-installed-18u-host"
type Options struct{Root, ManifestSHA256, EvidenceDir, Confirmation string}
type Report struct{
 Schema string `json:"schema"`
 Status string `json:"status"`
 Stage string `json:"stage"`
 SourceCommit string `json:"sourceCommit"`
 ManifestSHA256 string `json:"manifestSHA256"`
 HostPID int `json:"hostPID"`
 BrokerPID int `json:"brokerPID"`
 HostExitSucceeded bool `json:"hostExitSucceeded"`
 BrokerExitSucceeded bool `json:"brokerExitSucceeded"`
 ReadbackEvidenceConsistent bool `json:"readbackEvidenceConsistent"`
 RegistrationMutationRequested bool `json:"registrationMutationRequested"`
 InstalledProfilePresenceVerified bool `json:"installedProfilePresenceVerified"`
 NativeResult json.RawMessage `json:"nativeResult"`
}
type Child interface{PID()int;Input()io.WriteCloser;Output()io.Reader;Wait()error;Stop()}
type StartFunc func(context.Context,string,[]string,string,io.Writer)(Child,error)
type boundedOutput struct{mu sync.Mutex;raw []byte;overflow bool}
func(b *boundedOutput)Write(p []byte)(int,error){b.mu.Lock();defer b.mu.Unlock();n:=len(p);left:=65536-len(b.raw);if len(p)>left{p=p[:left];b.overflow=true};b.raw=append(b.raw,p...);return n,nil}
func(b *boundedOutput)snapshot()([]byte,bool){b.mu.Lock();defer b.mu.Unlock();return append([]byte(nil),b.raw...),b.overflow}
func readLine(ctx context.Context,r *bufio.Reader)([]byte,error){type result struct{raw []byte;err error};ch:=make(chan result,1);go func(){raw,e:=r.ReadSlice('\n');if len(raw)>16384{e=errors.New("frame limit")};if e==nil{raw=raw[:len(raw)-1]};ch<-result{append([]byte(nil),raw...),e}}();select{case r:=<-ch:return r.raw,r.err;case <-ctx.Done():return nil,ctx.Err()}}
func eof(ctx context.Context,r *bufio.Reader)bool{raw,e:=readLine(ctx,r);return e==io.EOF&&len(raw)==0}
// Run is deliberately one attempt. Production provides the existing runtime's
// Job-bound process factory; unit tests provide non-executing children.
func Run(parent context.Context,o Options,start StartFunc)(report Report){
 report=Report{Schema:"installed-18u-host-check-v1",Status:"failed-or-inconclusive",Stage:"preconditions",ManifestSHA256:o.ManifestSHA256}
 if o.Confirmation!=Confirm||start==nil||!filepath.IsAbs(o.EvidenceDir){return}
 m,e:=VerifyInstallation(o.Root,o.ManifestSHA256);if e!=nil{return};report.SourceCommit=m.SourceCommit
 root,e:=filepath.EvalSymlinks(o.Root);if e!=nil{return};parentDir,e:=filepath.EvalSymlinks(filepath.Dir(o.EvidenceDir));if e!=nil{return};o.EvidenceDir=filepath.Join(parentDir,filepath.Base(o.EvidenceDir))
 rel,e:=filepath.Rel(root,o.EvidenceDir);if e!=nil||rel=="."||rel!=".."&&!strings.HasPrefix(rel,".."+string(os.PathSeparator)){return}
 code,e:=CanonicalNi(filepath.Join(root,"source"));if e!=nil||len(code)==0||len(code)>16{return}
 if e=os.Mkdir(o.EvidenceDir,0700);e!=nil{return}
 var hostOut,hostErr,brokerOut,brokerErr boundedOutput
 defer func(){
  for name,value:=range map[string]*boundedOutput{"host-stdout.jsonl":&hostOut,"host-stderr.jsonl":&hostErr,"broker-stdout.txt":&brokerOut,"broker-stderr.jsonl":&brokerErr}{raw,overflow:=value.snapshot();if overflow{report.Status="failed-or-inconclusive";report.Stage="output-bound";report.ReadbackEvidenceConsistent=false};if os.WriteFile(filepath.Join(o.EvidenceDir,name),raw,0600)!=nil{report.Status="failed-or-inconclusive";report.Stage="evidence-write";report.ReadbackEvidenceConsistent=false}}
  raw,e:=json.Marshal(report);if e!=nil||os.WriteFile(filepath.Join(o.EvidenceDir,"installed-host-result.json"),append(raw,'\n'),0600)!=nil{report.Status="failed-or-inconclusive";report.Stage="evidence-write";report.ReadbackEvidenceConsistent=false}
 }()
 ctx,cancel:=context.WithTimeout(parent,180*time.Second);defer cancel()
 report.Stage="host-start"
 host,e:=start(ctx,filepath.Join(root,filepath.FromSlash(HostPath)),nil,o.EvidenceDir,&hostErr);if e!=nil{return};hostDone:=false;defer func(){if !hostDone{host.Stop()}}()
 report.HostPID=host.PID();if report.HostPID<=0{return}
 nonce:=make([]byte,16);if _,e=rand.Read(nonce);e!=nil{return};pipe:=`\\.\pipe\YimeBroker.18uTouch.v1.installed-check-`+hex.EncodeToString(nonce)
 report.Stage="broker-start"
 broker,e:=start(ctx,filepath.Join(root,filepath.FromSlash(BrokerPath)),[]string{"--root",filepath.Join(root,"source"),"--data-dir",filepath.Join(root,"data"),"--pipe-name",pipe,"--tip-host-pid",strconv.Itoa(report.HostPID)},o.EvidenceDir,&brokerErr);if e!=nil{return};brokerDone:=false;defer func(){if !brokerDone{broker.Stop()}}()
 report.BrokerPID=broker.PID();if report.BrokerPID<=0||report.BrokerPID==report.HostPID{return}
 br:=bufio.NewReaderSize(io.TeeReader(broker.Output(),&brokerOut),16385)
 report.Stage="broker-ready";line,e:=readLine(ctx,br);if e!=nil||string(line)!="READY yimebroker-18u"{return}
 config:=map[string]any{"scenario":"commit","dll":filepath.Join(root,filepath.FromSlash(DLLPath)),"pipe":pipe,"brokerPID":report.BrokerPID,"brokerImage":filepath.Join(root,filepath.FromSlash(BrokerPath)),"code":code}
 report.Stage="host-config";if e=json.NewEncoder(host.Input()).Encode(config);e!=nil{return}
 hr:=bufio.NewReaderSize(io.TeeReader(host.Output(),&hostOut),16385)
 report.Stage="host-connect";line,e=readLine(ctx,hr);if e!=nil{return};var connected struct{Stage string `json:"stage"`;Accepted bool `json:"accepted"`};if decodeFormalEnvelope(line,&connected)!=nil||connected.Stage!="connected"||!connected.Accepted{return}
 // Existing registered test protocol has exactly one explicit continuation.
 if e=json.NewEncoder(host.Input()).Encode(map[string]bool{"proceed":true});e!=nil{return};if e=host.Input().Close();e!=nil{return}
 report.Stage="host-result";line,e=readLine(ctx,hr);if e!=nil{return};if ValidateCommit(line)!=nil{return};report.NativeResult=append(json.RawMessage(nil),line...)
 report.Stage="host-exit";if !eof(ctx,hr){return};if e=host.Wait();e!=nil{hostDone=true;return};hostDone=true;report.HostExitSucceeded=true
 report.Stage="broker-exit";if !eof(ctx,br){return};if e=broker.Wait();e!=nil{brokerDone=true;return};brokerDone=true;report.BrokerExitSucceeded=true
 // Result proves the scoped edit and process termination, NOT registry absence
 // or persistence verification. Persistent installation is intentionally intact.
 if ctx.Err()!=nil{report.Stage="deadline";return};report.ReadbackEvidenceConsistent=true;report.Status="evidence-consistent";report.Stage="completed";return
}
