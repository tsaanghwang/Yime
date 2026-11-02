package activatedloop

import (
 "bufio"
 "bytes"
 "context"
 "crypto/sha256"
 "encoding/hex"
 "encoding/json"
 "errors"
 "io"
 "os"
 "path/filepath"
 "reflect"
 "strings"
 "testing"

 codemode "github.com/tsaanghwang/Yime/go-backend/internal/asciicodemode"
)

type inputBuffer struct{bytes.Buffer;closed bool}
func (b *inputBuffer)Close()error{b.closed=true;return nil}
type fakeChild struct{pid int;output io.Reader;input inputBuffer;waitErr error;waits,stops int}
func(c *fakeChild)PID()int{return c.pid}
func(c *fakeChild)Output()io.Reader{return c.output}
func(c *fakeChild)Input()io.WriteCloser{return &c.input}
func(c *fakeChild)Wait()error{c.waits++;return c.waitErr}
func(c *fakeChild)Stop(){c.stops++}
func validNative()NativeResult{
 broker:=uint32(22);owner:=uint32(11);session:=uint32(1);made:=uint64(100);disconnected:=DisconnectedHRESULT
 return NativeResult{PostCleanupRouteRevoked:true,PostCleanupRouteCode:&disconnected,Schema:"activated-loop-result-v1",Status:"passed",WritesStarted:true,CleanupVerified:true,HostPID:11,BrokerPID:&broker,WindowsSessionID:&session,BrokerCreationTime:&made,LedgerOwnerPID:&owner,LedgerOwnerCreationTime:&made,PublisherTrust:"not-established",HostResult:&HostResult{EditAttempts:1,Stage:"result",Scenario:"commit",ActualDLLLoaded:true,ActivationIdentity:"windows-activated-profile",Registered:true,Outcome:"applied",ReadbackMatches:true,OtherContextEmpty:true,HostCleanupVerified:true,SessionBinding:SessionBinding{SessionID:"test-session",Identity:SessionIdentity{LayoutSHA256:DedicatedLayoutSHA256,DictionarySHA256:DedicatedDictionarySHA256,Mode:"variable",SessionPolicy:"concept-keyboard-modes-v2+ellipsis-choice-v1"},Focus:SessionFocus{Context:"test-own-context",Epoch:1}}}}
}
func nativeBytes(t *testing.T,n NativeResult)[]byte{t.Helper();b,e:=json.Marshal(n);if e!=nil{t.Fatal(e)};return b}
func fixture(t *testing.T)Options{
 t.Helper();root:=t.TempDir();source:=filepath.Join(root,"source");dataDir:=filepath.Join(root,"data");if e:=os.Mkdir(dataDir,0700);e!=nil{t.Fatal(e)};binary:=filepath.Join(root,"bin");if e:=os.Mkdir(binary,0700);e!=nil{t.Fatal(e)}
 var dll,broker string
 for _,name:=range []string{DLLName,BrokerName}{data:=[]byte("synthetic hash-bound "+name);if e:=os.WriteFile(filepath.Join(binary,name),data,0600);e!=nil{t.Fatal(e)};h:=sha256.Sum256(data);if name==DLLName{dll=hex.EncodeToString(h[:])}else{broker=hex.EncodeToString(h[:])}}
 for name,data:=range map[string]string{
  "prototypes/touch-terminal/encoding/yime_yinyuan_layout.json":`{"yinyuan_id_to_key":{"S":"a","H":"b","Z":"c","M":"d"}}`,
  "internal_data/yime_syllable_decomposition.tsv":"pinyin_tone\tstatus\tshouyin_id\thuyin_id\tzhuyin_id\tmoyin_id\nni3\tok\tS\tH\tZ\tM\n",
 }{p:=filepath.Join(source,name);if e:=os.MkdirAll(filepath.Dir(p),0700);e!=nil{t.Fatal(e)};if e:=os.WriteFile(p,[]byte(data),0600);e!=nil{t.Fatal(e)}}
 return Options{BinaryDir:binary,Root:source,DataDir:dataDir,EvidenceDir:filepath.Join(root,"evidence"),DLLSHA256:dll,BrokerSHA256:broker,Confirmation:Confirm}
}
func TestCanonicalProbeUsesSharedAlgorithm(t *testing.T){o:=fixture(t);got,e:=CanonicalNi(o.Root);if e!=nil{t.Fatal(e)};record,e:=codemode.BuildRecord("abcd");if e!=nil{t.Fatal(e)};if got!=record.Variable{t.Fatal("canonical projection bypassed shared algorithm")}}
func TestControllerSingleOwnedLoop(t *testing.T){
 o:=fixture(t);host:=&fakeChild{pid:11,output:strings.NewReader("{\"stage\":\"connected\",\"accepted\":true}\n"+string(nativeBytes(t,validNative()))+"\n")};broker:=&fakeChild{pid:22,output:strings.NewReader("READY yimebroker-18u\n")};starts:=0
 expectedParent,e:=filepath.EvalSymlinks(filepath.Dir(o.EvidenceDir));if e!=nil{t.Fatal(e)};expectedDir:=filepath.Join(expectedParent,filepath.Base(o.EvidenceDir))
 start:=func(_ context.Context,path string,args []string,dir string,stderr io.Writer)(Child,error){starts++;if dir!=expectedDir{t.Fatal("foreign working directory")};if starts==1{if filepath.Base(path)!=HostName||args[0]!="--register-edit-once"{t.Fatal("unexpected host")};return host,nil};if starts!=2||filepath.Base(path)!=BrokerName||args[len(args)-2]!="--tip-host-pid"||args[len(args)-1]!="11"{t.Fatal("unowned broker")};return broker,nil}
 r:=Run(context.Background(),o,start)
 if r.Status!="evidence-consistent"||r.HostExitCode==nil||*r.HostExitCode!=0||r.BrokerExitCode==nil||*r.BrokerExitCode!=0||starts!=2||host.stops!=0||broker.stops!=0||host.waits!=1||broker.waits!=1{t.Fatalf("unexpected report or lifecycle: %+v",r)}
 var config map[string]any;if json.Unmarshal(host.input.Bytes(),&config)!=nil||len(config)!=7||config["hostPID"]!=float64(11)||config["brokerPID"]!=float64(22)||!host.input.closed{t.Fatal("not exactly one owned configuration")}
 var saved Report;data,e:=os.ReadFile(filepath.Join(o.EvidenceDir,"controller-result.json"));if e!=nil||json.Unmarshal(data,&saved)!=nil||!reflect.DeepEqual(saved,r){t.Fatal("final report mismatch")}
}
func TestControllerConnectFailureStillWaitsForCleanup(t *testing.T){
 o:=fixture(t);n:=validNative();n.Status="failed";n.OperationFailure=&Failure{Stage:"connect actual Broker",Kind:"hresult",Code:1};n.HostResult=nil
 host:=&fakeChild{pid:11,output:strings.NewReader("{\"stage\":\"connected\",\"accepted\":false}\n"+string(nativeBytes(t,n))+"\n"),waitErr:errors.New("exit1")};broker:=&fakeChild{pid:22,output:strings.NewReader("READY yimebroker-18u\n")}
 start:=func(_ context.Context,path string,_ []string,_ string,_ io.Writer)(Child,error){if filepath.Base(path)==HostName{return host,nil};return broker,nil}
 r:=Run(context.Background(),o,start);if r.Status!="failed"||host.waits!=1||broker.waits!=1||host.stops!=0||broker.stops!=0||r.ReadbackVerified{t.Fatal("failed transaction was replayed or killed instead of collecting cleanup")}
}
func TestControllerReadinessFailureDoesNotSendRegistrationConfig(t *testing.T){o:=fixture(t);host:=&fakeChild{pid:11,output:strings.NewReader("")};broker:=&fakeChild{pid:22,output:strings.NewReader("wrong ready\n")};starts:=0;start:=func(context.Context,string,[]string,string,io.Writer)(Child,error){starts++;if starts==1{return host,nil};return broker,nil};r:=Run(context.Background(),o,start);if r.Status!="failed"||starts!=2||host.input.Len()!=0||host.stops!=1||broker.stops!=1{t.Fatal("unready attempt not stopped without replay")}}
func TestControllerConfirmationAndHashesBeforeStart(t *testing.T){for _,change:=range []func(*Options){func(o *Options){o.Confirmation="yes"},func(o *Options){o.DLLSHA256=strings.Repeat("0",64)}}{o:=fixture(t);change(&o);r:=Run(context.Background(),o,func(context.Context,string,[]string,string,io.Writer)(Child,error){t.Fatal("unexpected launch");return nil,nil});if r.Status!="failed"{t.Fatal("invalid precondition accepted")}}}
func TestNativeEvidenceRejectsConflictsMissingAndFalseClaims(t *testing.T){raw:=nativeBytes(t,validNative());if ValidateNative(raw,11,22)!=nil{t.Fatal("valid fixture rejected")};for _,mutate:=range []func(*NativeResult){func(n *NativeResult){n.HostPID=99},func(n *NativeResult){n.CleanupVerified=false},func(n *NativeResult){n.HostResult.ReadbackMatches=false},func(n *NativeResult){n.HostResult.SendInput=true},func(n *NativeResult){n.LedgerOwnerCreationTime=nil},func(n *NativeResult){n.HostResult.SessionBinding.Focus.Epoch=0},func(n *NativeResult){n.HostResult.SessionBinding.Identity.DictionarySHA256="wrong"}}{n:=validNative();mutate(&n);if ValidateNative(nativeBytes(t,n),11,22)==nil{t.Fatal("weakened evidence accepted")}};for _,bad:=range []string{string(raw[:len(raw)-1])+`,"status":"passed"}`,strings.Replace(string(raw),`"readbackMatches":true,`,"",1),string(raw)+" trailing"}{if ValidateNative([]byte(bad),11,22)==nil{t.Fatal("ambiguous envelope accepted")}}}
func TestNoTrailingOutputAndBoundedDiagnostics(t *testing.T){if endOfOutput(context.Background(),bufio.NewReader(strings.NewReader("trailing")))==nil{t.Fatal("unterminated trailing output accepted")};var b boundedOutput;_,_=b.Write(make([]byte,65537));data,overflow:=b.snapshot();if len(data)!=65536||!overflow{t.Fatal("stderr unbounded")}}
func TestControllerTerminalFailureBeforeConnectIsNotKilled(t *testing.T){
 o:=fixture(t);n:=validNative();n.Status="blocked";n.WritesStarted=false;n.CleanupVerified=false;n.HostResult=nil;n.OperationFailure=&Failure{Stage:"precondition",Kind:"assertion",Code:1}
 host:=&fakeChild{pid:11,output:strings.NewReader(string(nativeBytes(t,n))+"\n"),waitErr:errors.New("exit3")};broker:=&fakeChild{pid:22,output:strings.NewReader("READY yimebroker-18u\n")}
 start:=func(_ context.Context,path string,_ []string,_ string,_ io.Writer)(Child,error){if filepath.Base(path)==HostName{return host,nil};return broker,nil}
 r:=Run(context.Background(),o,start);if r.Status!="failed"||host.waits!=1||broker.waits!=1||host.stops!=0||r.NativeResult==nil{t.Fatal("blocked terminal lost or normally exiting host killed")}
}

func TestExactEditAttemptAndRevokedRouteEvidence(t *testing.T){
 for _,change:=range []func(*NativeResult){
  func(n *NativeResult){n.HostResult.EditAttempts=0},
  func(n *NativeResult){n.HostResult.EditAttempts=2},
  func(n *NativeResult){n.PostCleanupRouteRevoked=false},
  func(n *NativeResult){n.PostCleanupRouteCode=nil},
  func(n *NativeResult){v:=uint32(0);n.PostCleanupRouteCode=&v},
  func(n *NativeResult){v:=uint32(0x80004005);n.PostCleanupRouteCode=&v},
 }{n:=validNative();change(&n);if ValidateNative(nativeBytes(t,n),11,22)==nil{t.Fatal("insufficient exact edit/revocation evidence accepted")}}
 raw:=string(nativeBytes(t,validNative()))
 for _,bad:=range []string{
  strings.Replace(raw,`"editAttempts":1,`,"",1),
  strings.Replace(raw,`"editAttempts":1`,`"editAttempts":null`,1),
  strings.Replace(raw,`"editAttempts":1`,`"editAttempts":true`,1),
  strings.Replace(raw,`"editAttempts":1`,`"editAttempts":-1`,1),
  strings.Replace(raw,`"editAttempts":1`,`"editAttempts":4294967297`,1),
  strings.Replace(raw,`"postCleanupRouteRevoked":true,`,"",1),
  strings.Replace(raw,`"postCleanupRouteRevoked":true`,`"postCleanupRouteRevoked":1`,1),
  strings.Replace(raw,`"postCleanupRouteCode":2147747076,`,"",1),
  strings.Replace(raw,`"postCleanupRouteCode":2147747076`,`"postCleanupRouteCode":"2147747076"`,1),
  strings.Replace(raw,`"postCleanupRouteCode":2147747076`,`"postCleanupRouteCode":6442714372`,1),
 }{if bad==raw{t.Fatal("negative fixture did not alter field")};if ValidateNative([]byte(bad),11,22)==nil{t.Fatal("missing/wrongly typed refinement evidence accepted")}}
 // An unqueried route is valid failure evidence, never successful evidence.
 n:=validNative();n.Status="failed";n.PostCleanupRouteRevoked=false;n.PostCleanupRouteCode=nil
 if _,err:=DecodeNative(nativeBytes(t,n));err!=nil{t.Fatal("unqueried failure evidence rejected")}
 if ValidateNative(nativeBytes(t,n),11,22)==nil{t.Fatal("failure evidence accepted as success")}
}
