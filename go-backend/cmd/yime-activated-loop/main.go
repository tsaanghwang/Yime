package main

import (
 "context"
 "encoding/json"
 "flag"
 "fmt"
 "os"
 "path/filepath"
 "github.com/tsaanghwang/Yime/go-backend/internal/activatedloop"
)
func main(){
 var o activatedloop.Options
 flag.StringVar(&o.Root,"root","","fixed source/resource root")
 flag.StringVar(&o.DataDir,"data-dir","","fixed dedicated resource directory")
 flag.StringVar(&o.EvidenceDir,"evidence-dir","","fresh external evidence directory")
 flag.StringVar(&o.DLLSHA256,"dll-sha256","","pinned dedicated DLL SHA256")
 flag.StringVar(&o.BrokerSHA256,"broker-sha256","","pinned dedicated Broker SHA256")
 flag.StringVar(&o.Confirmation,"confirm","","explicit once-only authorization token")
 flag.Parse()
 if flag.NArg()!=0 || !nativeJobGate() { fmt.Fprintln(os.Stderr,"native AMD64 controller in an enclosing Windows Job required");os.Exit(3) }
 executable,err:=os.Executable();if err!=nil{os.Exit(3)};o.BinaryDir=filepath.Dir(executable)
 report:=activatedloop.Run(context.Background(),o,activatedloop.StartOwned)
 if json.NewEncoder(os.Stdout).Encode(report)!=nil{os.Exit(1)}
 if report.Status!="evidence-consistent"{os.Exit(1)}
}
