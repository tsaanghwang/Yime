package installed18uhost

import("bytes";"crypto/sha256";"encoding/hex";"encoding/json";"errors";"io";"os";"path/filepath";"regexp";"strings")
const HostPath=NativeDirectory+"/YimeTouchRegisteredFormalHostTests.exe"
const BrokerPath="bin/YimeBroker18u.exe"
const DLLPath=NativeDirectory+"/YimeTextService18u.dll"
const ControllerPath="bin/Yime18uInstalledRuntime.exe"
const Descriptor="installed-18u-product.json"
var hex64=regexp.MustCompile(`^[0-9a-f]{64}$`)
var hex40=regexp.MustCompile(`^[0-9a-f]{40}$`)
type File struct{Path string `json:"path"`;Bytes int64 `json:"bytes"`;SHA256 string `json:"sha256"`}
type Identity struct{CLSID string `json:"clsid"`;Profile string `json:"profile"`}
type Manifest struct{Schema string `json:"schema"`;Product string `json:"product"`;SourceCommit string `json:"sourceCommit"`;Identity Identity `json:"identity"`;Architecture string `json:"architecture"`;Language string `json:"language"`;Mode string `json:"mode"`;Autostart bool `json:"autostart"`;Files []File `json:"files"`}
// Reject duplicate keys even in nested records; no unknown/null fields can be
// silently accepted by typed decoding. Missing fields are checked below.
func strictJSON(raw []byte,value any)error{
 d:=json.NewDecoder(bytes.NewReader(raw));var walk func(int)error
 walk=func(depth int)error{if depth>8{return errors.New("json depth")};t,e:=d.Token();if e!=nil{return e};if t==nil{return errors.New("null")};switch t{case json.Delim('{'):seen:=map[string]bool{};for d.More(){k,e:=d.Token();s,ok:=k.(string);if e!=nil||!ok||seen[s]{return errors.New("duplicate key")};seen[s]=true;if e=walk(depth+1);e!=nil{return e}};_,e=d.Token();return e;case json.Delim('['):for d.More(){if e=walk(depth+1);e!=nil{return e}};_,e=d.Token();return e};return nil}
 if e:=walk(0);e!=nil{return e};if _,e:=d.Token();e!=io.EOF{return errors.New("trailing json")};d=json.NewDecoder(bytes.NewReader(raw));d.DisallowUnknownFields();return d.Decode(value)
}
func hashFile(path string)(string,int64,error){
 if err:=regularPath(path);err!=nil{return "",0,err};f,e:=os.Open(path);if e!=nil{return "",0,e};defer f.Close();h:=sha256.New();n,e:=io.Copy(h,io.LimitReader(f,1<<32));if e!=nil||n==1<<32{return "",0,errors.New("file size")};return hex.EncodeToString(h.Sum(nil)),n,nil
}
func regularPath(path string)error{
 for p:=path;;p=filepath.Dir(p){s,e:=os.Lstat(p);if e!=nil{return e};if s.Mode()&os.ModeSymlink!=0||reparse(p){return errors.New("reparse path")};if filepath.Dir(p)==p{break}}
 s,e:=os.Stat(path);if e!=nil{return e};if !s.Mode().IsRegular(){return errors.New("regular file required")};return nil
}
func VerifyInstallation(root,anchor string)(Manifest,error){
 var m Manifest
 if !filepath.IsAbs(root)||!hex64.MatchString(anchor){return m,errors.New("absolute root and independent manifest hash required")}
 path:=filepath.Join(root,Descriptor);h,n,e:=hashFile(path);if e!=nil||h!=anchor||n>1<<20{return m,errors.New("manifest hash/size")};raw,e:=os.ReadFile(path);if e!=nil{return m,e};if e=strictJSON(raw,&m);e!=nil{return m,e}
 // False-valued autostart must be present, not a zero-value from missing data.
 var fields map[string]json.RawMessage;_ = json.Unmarshal(raw,&fields)
 if len(fields)!=9||m.Schema!="installed-18u-product-v1"||m.Product!="yimecore-18u"||!hex40.MatchString(m.SourceCommit)||m.Identity.CLSID!="{6DFACE1F-562E-4773-A9D6-D5753A314711}"||m.Identity.Profile!="{1BD904AC-3194-4419-B70A-5574100F18B3}"||NativeDirectory==""||m.Architecture!=NativeArchitecture||m.Language!="CN"||m.Mode!="variable"||m.Autostart||fields["autostart"]==nil{return m,errors.New("dedicated manifest identity")}
 required:=map[string]bool{HostPath:false,BrokerPath:false,DLLPath:false,ControllerPath:false,"profile-icon.ico":false,NativeDirectory+"/Yime18uProductRegistration.exe":false,"source/prototypes/touch-terminal/desktop/resources.lock.json":false,"source/tools/yimecore/"+ProductDescriptor:false,"source/prototypes/touch-terminal/data/physical-layout.json":false,"source/prototypes/touch-terminal/encoding/yime_yinyuan_layout.json":false,"source/internal_data/yime_syllable_decomposition.tsv":false,"data/ascii_keyboard_manifest.json":false,"data/yime_variable.dict.yaml":false,"data/yime_full.dict.yaml":false,"data/yime_shorthand.dict.yaml":false}
 seen:=map[string]bool{}
 for _,f:=range m.Files{key:=strings.ToLower(f.Path);if f.Path==""||strings.ContainsAny(f.Path,`\:`)||strings.HasPrefix(f.Path,"/")||filepath.ToSlash(filepath.Clean(f.Path))!=f.Path||strings.HasPrefix(f.Path,"../")||f.Path==".."||key==Descriptor||seen[key]||!hex64.MatchString(f.SHA256)||f.Bytes<=0{return m,errors.New("payload record")};seen[key]=true;h,n,e:=hashFile(filepath.Join(root,filepath.FromSlash(f.Path)));if e!=nil||n!=f.Bytes||h!=f.SHA256{return m,errors.New("payload mismatch")};if _,ok:=required[f.Path];ok{required[f.Path]=true}}
 for _,found:=range required{if !found{return m,errors.New("required payload missing")}}
 return m,nil
}
