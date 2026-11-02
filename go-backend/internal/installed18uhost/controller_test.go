package installed18uhost

import("bytes";"context";"crypto/sha256";"encoding/hex";"encoding/json";"errors";"io";"os";"path/filepath";"strings";"testing"
 codemode "github.com/tsaanghwang/Yime/go-backend/internal/asciicodemode")
func put(t *testing.T,path string,raw []byte){t.Helper();if e:=os.MkdirAll(filepath.Dir(path),0700);e!=nil{t.Fatal(e)};if e:=os.WriteFile(path,raw,0600);e!=nil{t.Fatal(e)}}
func fixture(t *testing.T)Options{
 t.Helper();parent:=t.TempDir();root:=filepath.Join(parent,"installed");
 files:=[]string{HostPath,BrokerPath,DLLPath,ControllerPath,"profile-icon.ico","x64/Yime18uProductRegistration.exe","source/prototypes/touch-terminal/desktop/resources.lock.json","source/tools/yimecore/18u-touch-product.json","source/prototypes/touch-terminal/data/physical-layout.json","source/prototypes/touch-terminal/encoding/yime_yinyuan_layout.json","source/internal_data/yime_syllable_decomposition.tsv","data/ascii_keyboard_manifest.json","data/yime_variable.dict.yaml","data/yime_full.dict.yaml","data/yime_shorthand.dict.yaml"}
 m:=Manifest{Schema:"installed-18u-product-v1",Product:"yimecore-18u",SourceCommit:strings.Repeat("a",40),Identity:Identity{CLSID:"{6DFACE1F-562E-4773-A9D6-D5753A314711}",Profile:"{1BD904AC-3194-4419-B70A-5574100F18B3}"},Architecture:"native-x64",Language:"CN",Mode:"variable"}
 for _,name:=range files{
  raw:=[]byte("synthetic offline payload")
  if strings.HasSuffix(name,"yime_yinyuan_layout.json"){raw=[]byte(`{"yinyuan_id_to_key":{"a":"a","b":"b","c":"c","d":"d"}}`)}
  if strings.HasSuffix(name,"yime_syllable_decomposition.tsv"){raw=[]byte("pinyin_tone\tstatus\tshouyin_id\thuyin_id\tzhuyin_id\tmoyin_id\nni3\tok\ta\tb\tc\td\n")}
  put(t,filepath.Join(root,filepath.FromSlash(name)),raw);sum:=sha256.Sum256(raw);m.Files=append(m.Files,File{Path:name,Bytes:int64(len(raw)),SHA256:hex.EncodeToString(sum[:])})
 }
 raw,e:=json.Marshal(m);if e!=nil{t.Fatal(e)};put(t,filepath.Join(root,Descriptor),raw);sum:=sha256.Sum256(raw)
 // Match Run's canonical installation path, including Windows TEMP aliases.
 root,e=filepath.EvalSymlinks(root);if e!=nil{t.Fatalf("canonical fixture root: %v",e)}
 parent=filepath.Dir(root)
 return Options{Root:root,ManifestSHA256:hex.EncodeToString(sum[:]),EvidenceDir:filepath.Join(parent,"evidence"),Confirmation:Confirm}
}
func validResult()formalResult{return formalResult{Stage:"result",Scenario:"commit",ActualDLLLoaded:true,ActivationIdentity:"windows-activated-profile",Registered:true,Outcome:"applied",ReadbackMatches:true,OtherContextEmpty:true}}
type memoryInput struct{bytes.Buffer;closed bool}
func(m *memoryInput)Close()error{m.closed=true;return nil}
type fakeChild struct{pid int;input memoryInput;output io.Reader;waitErr error;waited,stopped bool}
func(f *fakeChild)PID()int{return f.pid};func(f *fakeChild)Input()io.WriteCloser{return &f.input};func(f *fakeChild)Output()io.Reader{return f.output};func(f *fakeChild)Wait()error{f.waited=true;return f.waitErr};func(f *fakeChild)Stop(){f.stopped=true}
func children(t *testing.T)(*fakeChild,*fakeChild){raw,e:=json.Marshal(validResult());if e!=nil{t.Fatal(e)};return &fakeChild{pid:111,output:strings.NewReader("{\"stage\":\"connected\",\"accepted\":true}\n"+string(raw)+"\n")},&fakeChild{pid:222,output:strings.NewReader("READY yimebroker-18u\n")}}
func TestInstalledCheckSingleExistingProtocol(t *testing.T){
 o:=fixture(t);host,broker:=children(t);count:=0
 start:=func(ctx context.Context,path string,args []string,dir string,stderr io.Writer)(Child,error){count++;if count==1{if path!=filepath.Join(o.Root,filepath.FromSlash(HostPath))||len(args)!=0{t.Fatalf("not existing host: want path=%q args=[], got path=%q args=%q",filepath.Join(o.Root,filepath.FromSlash(HostPath)),path,args)};return host,nil};if count!=2||path!=filepath.Join(o.Root,filepath.FromSlash(BrokerPath))||len(args)!=8||args[6]!="--tip-host-pid"||args[7]!="111"||args[1]!=filepath.Join(o.Root,"source")||args[3]!=filepath.Join(o.Root,"data")||!strings.HasPrefix(args[5],`\\.\pipe\YimeBroker.18uTouch.v1.installed-check-`){t.Fatal("broker owner/identity")};return broker,nil}
 r:=Run(context.Background(),o,start);if r.Status!="evidence-consistent"||count!=2||!host.waited||!broker.waited||host.stopped||broker.stopped||r.RegistrationMutationRequested||r.InstalledProfilePresenceVerified{t.Fatalf("wrong result %+v",r)}
 dec:=json.NewDecoder(&host.input.Buffer);var config map[string]any;if dec.Decode(&config)!=nil||len(config)!=6||config["scenario"]!="commit"||config["brokerPID"]!=float64(222){t.Fatal("wrong config")};record,e:=codemode.BuildRecord("abcd");if e!=nil||config["code"]!=record.Variable{t.Fatal("canonical algorithm changed")};var next map[string]bool;if dec.Decode(&next)!=nil||len(next)!=1||!next["proceed"]{t.Fatal("continuation")};var extra any;if dec.Decode(&extra)!=io.EOF||!host.input.closed{t.Fatal("replay/extra config")}
 raw,e:=os.ReadFile(filepath.Join(o.EvidenceDir,"installed-host-result.json"));if e!=nil{t.Fatal(e)};var saved Report;if json.Unmarshal(raw,&saved)!=nil||saved.Status!=r.Status{t.Fatal("report")}
}
func TestManifestAndConfirmationFailBeforeProcess(t *testing.T){
 for _,kind:=range []string{"confirmation","hash","binary","scope","extra-key","missing-false","path-traversal","duplicate-path"}{t.Run(kind,func(t *testing.T){o:=fixture(t);path:=filepath.Join(o.Root,Descriptor)
 switch kind{case "confirmation":o.Confirmation="";case "hash":o.ManifestSHA256=strings.Repeat("0",64);case "binary":put(t,filepath.Join(o.Root,filepath.FromSlash(DLLPath)),[]byte("changed"));default:raw,_:=os.ReadFile(path);var v map[string]any;_ = json.Unmarshal(raw,&v);switch kind{case "scope":v["product"]="yimecore";case "extra-key":v["command"]="anything";case "missing-false":delete(v,"autostart");case "path-traversal":v["files"].([]any)[0].(map[string]any)["path"]="../other.exe";case "duplicate-path":rows:=v["files"].([]any);rows=append(rows,rows[0]);v["files"]=rows};raw,_=json.Marshal(v);put(t,path,raw);sum:=sha256.Sum256(raw);o.ManifestSHA256=hex.EncodeToString(sum[:])}
 count:=0;r:=Run(context.Background(),o,func(context.Context,string,[]string,string,io.Writer)(Child,error){count++;return nil,errors.New("must not start")});if count!=0||r.Status=="evidence-consistent"{t.Fatal("unsafe start")}
 })}
}
func TestRegisteredEvidenceRejectsMissingAndFalseClaims(t *testing.T){raw,_:=json.Marshal(validResult());if ValidateCommit(raw)!=nil{t.Fatal("fixture")};for _,bad:=range []string{strings.Replace(string(raw),`"registered":true`,`"registered":false`,1),strings.Replace(string(raw),`"sendInput":false,`,"",1),strings.Replace(string(raw),`"readbackMatches":true`,`"readbackMatches":true,"readbackMatches":true`,1),strings.Replace(string(raw),`"registered":true`,`"registered":null`,1),strings.Replace(string(raw),`"activationIdentity":"windows-activated-profile"`,`"activationIdentity":"owned-host-activation-client"`,1),string(raw)+"{}"}{if ValidateCommit([]byte(bad))==nil{t.Fatal("false/missing/duplicate accepted")}}}
func TestFailureDoesNotRetryOrUninstall(t *testing.T){
 for _,kind:=range []string{"ready","refused","extra-output","exit"}{t.Run(kind,func(t *testing.T){o:=fixture(t);host,broker:=children(t);switch kind{case "ready":broker.output=strings.NewReader("not-ready\n");case "refused":host.output=strings.NewReader("{\"stage\":\"connected\",\"accepted\":false}\n");case "extra-output":raw,_:=json.Marshal(validResult());host.output=strings.NewReader("{\"stage\":\"connected\",\"accepted\":true}\n"+string(raw)+"\nextra\n");case "exit":host.waitErr=errors.New("exit failure")};count:=0;r:=Run(context.Background(),o,func(_ context.Context,path string,args []string,_ string,_ io.Writer)(Child,error){count++;if count==1{return host,nil};if count==2{return broker,nil};t.Fatal("retry");return nil,errors.New("retry")});if count!=2||r.Status=="evidence-consistent"||r.ReadbackEvidenceConsistent{t.Fatal("failure accepted")};if !broker.stopped{t.Fatal("owned broker not stopped")};if kind=="ready"&&host.input.Len()!=0{t.Fatal("host configured before ready")}})}
}
func TestEvidenceOutsideInstallationAndFresh(t *testing.T){o:=fixture(t);for _,path:=range []string{filepath.Join(o.Root,"evidence"),o.Root,filepath.Dir(o.Root)}{o.EvidenceDir=path;r:=Run(context.Background(),o,func(context.Context,string,[]string,string,io.Writer)(Child,error){t.Fatal("unsafe evidence start");return nil,nil});if r.Status=="evidence-consistent"{t.Fatal("bad path")}}}
func TestCanonicalNiUsesOnlyAdmittedProjection(t *testing.T){o:=fixture(t);root:=filepath.Join(o.Root,"source");got,e:=CanonicalNi(root);record,wantErr:=codemode.BuildRecord("abcd");if e!=nil||wantErr!=nil||got!=record.Variable{t.Fatal("algorithm mismatch")};put(t,filepath.Join(root,"internal_data/yime_syllable_decomposition.tsv"),[]byte("pinyin_tone\tstatus\tshouyin_id\thuyin_id\tzhuyin_id\tmoyin_id\nni3\trejected\ta\tb\tc\td\n"));if _,e=CanonicalNi(root);e==nil{t.Fatal("unadmitted accepted")}}
