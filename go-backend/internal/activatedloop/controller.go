// Package activatedloop owns one development-only registered-host/Broker attempt.
// It is not an installer, recovery loop, UI transport, or acceptance assertion.
package activatedloop

import (
 "bufio"
 "context"
 "crypto/rand"
 "crypto/sha256"
 "encoding/hex"
 "encoding/json"
 "errors"
 "io"
 "os"
 "path/filepath"
 "strconv"
 "strings"
 "sync"
 "time"
)

const HostName = "YimeActivatedLoopOnce.exe"
const BrokerName = "YimeBroker18u.exe"
const DLLName = "YimeTextService18u.dll"
const Confirm = "once-activated-18u-loop"

type Options struct { BinaryDir, Root, DataDir, EvidenceDir, DLLSHA256, BrokerSHA256, Confirmation string }
type Report struct {
 Schema string `json:"schema"`
 Status string `json:"status"`
 Stage string `json:"stage"`
 HostPID int `json:"hostPID"`
 BrokerPID int `json:"brokerPID"`
 HostExited bool `json:"hostExited"`
 BrokerExited bool `json:"brokerExited"`
 HostExitCode *int `json:"hostExitCode"`
 BrokerExitCode *int `json:"brokerExitCode"`
 NativeResult json.RawMessage `json:"nativeResult"`
 CleanupVerified bool `json:"cleanupVerified"`
 ReadbackVerified bool `json:"readbackVerified"`
}
type Child interface { PID() int; Output() io.Reader; Input() io.WriteCloser; Wait() error; Stop() }
type StartFunc func(context.Context, string, []string, string, io.Writer) (Child,error)

type boundedOutput struct { mu sync.Mutex; data []byte; overflow bool }
func (b *boundedOutput) Write(p []byte)(int,error) { b.mu.Lock(); defer b.mu.Unlock(); n:=len(p); left:=65536-len(b.data); if len(p)>left { b.overflow=true; p=p[:left] }; b.data=append(b.data,p...); return n,nil }
func (b *boundedOutput) snapshot()([]byte,bool) { b.mu.Lock(); defer b.mu.Unlock(); return append([]byte(nil),b.data...),b.overflow }
func hashFile(path, expected string) error { if len(expected)!=64 || strings.ToLower(expected)!=expected { return errors.New("hash") }; if _,err:=hex.DecodeString(expected);err!=nil{return err}; f,err:=os.Open(path);if err!=nil{return err};defer f.Close(); info,e:=f.Stat();if e!=nil||!info.Mode().IsRegular()||info.Size()<=0||info.Size()>128*1024*1024{return errors.New("binary size")}; h:=sha256.New(); if _,err=io.Copy(h,io.LimitReader(f,128*1024*1024+1));err!=nil{return err};if hex.EncodeToString(h.Sum(nil))!=expected{return errors.New("hash")};return nil }
func readLine(ctx context.Context,r *bufio.Reader)([]byte,error){ type answer struct{line []byte;err error}; ch:=make(chan answer,1);go func(){ b,e:=r.ReadSlice('\n');if len(b)>16384{e=errors.New("frame bound")};if e==nil{b=b[:len(b)-1]};ch<-answer{append([]byte(nil),b...),e} }();select{case x:=<-ch:return x.line,x.err;case <-ctx.Done():return nil,ctx.Err()} }
func endOfOutput(ctx context.Context,r *bufio.Reader)error { line,err:=readLine(ctx,r);if err==io.EOF&&len(line)==0{return nil};return errors.New("extra or unterminated output") }

// Run's StartFunc is an offline test seam. Production always supplies StartOwned.
// The entrypoint must verify native Windows AMD64 and membership in the outer
// kill-on-close Job before calling Run. No native process is started by tests.
func Run(parent context.Context,o Options,start StartFunc)(report Report){
 report=Report{Schema:"activated-loop-controller-v1",Status:"failed",Stage:"preconditions"}
 if o.Confirmation!=Confirm || start==nil { return }
 for _,p:=range []string{o.BinaryDir,o.Root,o.DataDir,o.EvidenceDir}{if !filepath.IsAbs(p){return}}
 // Resolve existing parent aliases before creating the new evidence directory.
 parentDir,e:=filepath.EvalSymlinks(filepath.Dir(o.EvidenceDir));if e!=nil{return};o.EvidenceDir=filepath.Join(parentDir,filepath.Base(o.EvidenceDir))
 for _,protected:=range []string{o.BinaryDir,o.Root,o.DataDir}{resolved,e:=filepath.EvalSymlinks(protected);if e!=nil{return};rel,e:=filepath.Rel(resolved,o.EvidenceDir);if e!=nil||rel=="."||rel!=".."&&!strings.HasPrefix(rel,".."+string(os.PathSeparator)){return}}
 if hashFile(filepath.Join(o.BinaryDir,DLLName),o.DLLSHA256)!=nil || hashFile(filepath.Join(o.BinaryDir,BrokerName),o.BrokerSHA256)!=nil{return}
 code,err:=CanonicalNi(o.Root);if err!=nil || len(code)==0 || len(code)>16{return}
 if err=os.Mkdir(o.EvidenceDir,0700);err!=nil{return}
 var hostErr,brokerErr,hostOut,brokerOut boundedOutput
 defer func(){
  h,ho:=hostErr.snapshot();b,bo:=brokerErr.snapshot();out,oo:=hostOut.snapshot();bout,boo:=brokerOut.snapshot()
  if os.WriteFile(filepath.Join(o.EvidenceDir,"host-stdout.jsonl"),out,0600)!=nil||os.WriteFile(filepath.Join(o.EvidenceDir,"broker-stdout.txt"),bout,0600)!=nil{report.Status="failed";report.Stage="evidence-write"}
  if ho||bo||oo||boo {report.Status="failed";report.Stage="output-bound";report.ReadbackVerified=false;report.CleanupVerified=false}
  if os.WriteFile(filepath.Join(o.EvidenceDir,"host-stderr.jsonl"),h,0600)!=nil || os.WriteFile(filepath.Join(o.EvidenceDir,"broker-stderr.jsonl"),b,0600)!=nil {report.Status="failed";report.Stage="evidence-write"}
  data,e:=json.Marshal(report);if e==nil {if os.WriteFile(filepath.Join(o.EvidenceDir,"controller-result.json"),append(data,'\n'),0600)!=nil{report.Status="failed";report.Stage="evidence-write"}}
 }()
 ctx,cancel:=context.WithTimeout(parent,180*time.Second);defer cancel()
 report.Stage="host-start"
 host,err:=start(ctx,filepath.Join(o.BinaryDir,HostName),[]string{"--register-edit-once","--dll",filepath.Join(o.BinaryDir,DLLName),"--sha256",o.DLLSHA256,"--ledger",filepath.Join(o.EvidenceDir,"registration-ledger.dpapi")},o.EvidenceDir,&hostErr)
 if err!=nil{return};hostDone:=false;defer func(){if !hostDone{host.Stop()}}()
 report.HostPID=host.PID();if report.HostPID<=0{return}
 nonce:=make([]byte,16);if _,err=rand.Read(nonce);err!=nil{return}
 pipe:=`\\.\pipe\YimeBroker.18uTouch.v1.activated-`+hex.EncodeToString(nonce)
 report.Stage="broker-start"
 broker,err:=start(ctx,filepath.Join(o.BinaryDir,BrokerName),[]string{"--root",o.Root,"--data-dir",o.DataDir,"--pipe-name",pipe,"--tip-host-pid",strconv.Itoa(report.HostPID)},o.EvidenceDir,&brokerErr)
 if err!=nil{return};brokerDone:=false;defer func(){if !brokerDone{broker.Stop()}}()
 report.BrokerPID=broker.PID();if report.BrokerPID<=0||report.BrokerPID==report.HostPID{return}
 br:=bufio.NewReaderSize(io.TeeReader(broker.Output(),&brokerOut),16385);report.Stage="broker-ready"
 line,err:=readLine(ctx,br);if err!=nil||string(line)!="READY yimebroker-18u"{return}
 config:=struct{Schema string `json:"schema"`;HostPID int `json:"hostPID"`;BrokerPID int `json:"brokerPID"`;BrokerImage string `json:"brokerImage"`;BrokerSHA256 string `json:"brokerSHA256"`;Pipe string `json:"pipe"`;Code string `json:"code"`}{"activated-loop-config-v1",report.HostPID,report.BrokerPID,filepath.Join(o.BinaryDir,BrokerName),o.BrokerSHA256,pipe,code}
 report.Stage="host-config"
 if err=json.NewEncoder(host.Input()).Encode(config);err!=nil{return};if err=host.Input().Close();err!=nil{return}
 hr:=bufio.NewReaderSize(io.TeeReader(host.Output(),&hostOut),16385);report.Stage="host-result"
 line,err=readLine(ctx,hr);if err!=nil{return}
 sawAccepted:=false
 var connect struct{Stage string `json:"stage"`;Accepted bool `json:"accepted"`}
 if decodeExact(line,&connect,nil)==nil && connect.Stage=="connected" {
  sawAccepted=connect.Accepted
  // A refused connection can still be followed by the authoritative cleanup
  // result. Never kill a normally unwinding native transaction just for false.
  line,err=readLine(ctx,hr);if err!=nil{return}
 }
 if _,e:=DecodeNative(line);e!=nil{return};report.NativeResult=append(json.RawMessage(nil),line...)
 nativeOK:=sawAccepted&&ValidateNative(line,report.HostPID,report.BrokerPID)==nil
 report.Stage="host-exit";if endOfOutput(ctx,hr)!=nil{return};err=host.Wait();hostDone=true;report.HostExited=true
 report.HostExitCode=exitCode(err);hostOK:=err==nil
 report.Stage="broker-exit";if endOfOutput(ctx,br)!=nil{return};err=broker.Wait();brokerDone=true;report.BrokerExited=true
 report.BrokerExitCode=exitCode(err);brokerOK:=err==nil
 if !nativeOK{report.Stage="native-operation-or-cleanup";return};if !hostOK{report.Stage="host-exit";return};if !brokerOK{report.Stage="broker-exit";return}
 report.CleanupVerified=true;report.ReadbackVerified=true;report.Status="evidence-consistent";report.Stage="completed";return
}
func exitCode(err error)*int{zero:=0;if err==nil{return &zero};type coded interface{ExitCode()int};var c coded;if errors.As(err,&c){v:=c.ExitCode();return &v};return nil}
