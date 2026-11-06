//go:build windows && (amd64 || arm64)
package main

import("context";"encoding/json";"errors";"io";"os";"path/filepath";"strings";"sync";"syscall";"unsafe"
 "github.com/tsaanghwang/Yime/go-backend/internal/installed18uhost")

type installedChild struct{process *runtimeProcess;input,output,stderrReader *os.File;once sync.Once;err error;done chan struct{};stderrDone chan struct{};stopJob func()}
func(p *installedChild)PID()int{return p.process.PID()}
func(p *installedChild)Input()io.WriteCloser{return p.input}
func(p *installedChild)Output()io.Reader{return p.output}
func(p *installedChild)Wait()error{p.once.Do(func(){p.err=p.process.Wait();<-p.stderrDone;_ = p.input.Close();_ = p.output.Close();_ = p.stderrReader.Close();close(p.done)});return p.err}
func(p *installedChild)Stop(){p.stopJob();_ = p.input.Close();_ = p.process.Kill();_ = p.stderrReader.Close();_ = p.Wait();_ = p.output.Close()}
func nativeInstalledArchitecture()bool{
 var processMachine,nativeMachine uint16
 current,e:=syscall.GetCurrentProcess();if e!=nil{return false}
 proc:=kernel32Runtime.NewProc("IsWow64Process2");if proc.Find()!=nil{return false}
 ok,_,_:=proc.Call(uintptr(current),uintptr(unsafe.Pointer(&processMachine)),uintptr(unsafe.Pointer(&nativeMachine)))
 return ok!=0&&processMachine==0&&nativeMachine==installed18uhost.NativeMachine
}
func installedStart(job *runtimeHandle,jobMu *sync.Mutex,stopJob func())installed18uhost.StartFunc{return func(ctx context.Context,path string,args []string,directory string,stderr io.Writer)(installed18uhost.Child,error){
 inRead,inWrite,e:=os.Pipe();if e!=nil{return nil,e}
 outRead,outWrite,e:=os.Pipe();if e!=nil{inRead.Close();inWrite.Close();return nil,e}
 errRead,errWrite,e:=os.Pipe();if e!=nil{inRead.Close();inWrite.Close();outRead.Close();outWrite.Close();return nil,e}
 jobMu.Lock()
 process,e:=startProcessInJobStreams(path,args,inRead,outWrite,errWrite,directory,job)
 jobMu.Unlock()
 inRead.Close();outWrite.Close();errWrite.Close()
 if e!=nil{inWrite.Close();outRead.Close();errRead.Close();return nil,e}
 child:=&installedChild{process:process,stopJob:stopJob,input:inWrite,output:outRead,stderrReader:errRead,done:make(chan struct{}),stderrDone:make(chan struct{})}
 go func(){defer close(child.stderrDone);defer errRead.Close();_,_ = io.Copy(stderr,errRead)}()
 go func(){select{case <-ctx.Done():stopJob();_ = child.process.Kill();_ = errRead.Close();case <-child.done:}}()
 return child,nil
}}
func runInstalled18uCheck(root,anchor,evidence,confirm string)error{
 if !nativeInstalledArchitecture(){return errors.New("matching native x64 or ARM64 Windows required; no emulation")}
 // Ensure the verified runtime file is this process, not a separate copied tool.
 executable,e:=os.Executable();if e!=nil{return e};actual,e:=filepath.EvalSymlinks(executable);if e!=nil{return e};expected,e:=filepath.EvalSymlinks(filepath.Join(root,filepath.FromSlash(installed18uhost.ControllerPath)));if e!=nil||!strings.EqualFold(actual,expected){return errors.New("runtime must be the installed payload")}
 job,e:=createChildProcessJob();if e!=nil{return e};var closeOnce sync.Once;var jobMu sync.Mutex;stopJob:=func(){closeOnce.Do(func(){jobMu.Lock();defer jobMu.Unlock();_ = job.Close()})};defer stopJob()
 result:=installed18uhost.Run(context.Background(),installed18uhost.Options{Root:root,ManifestSHA256:anchor,EvidenceDir:evidence,Confirmation:confirm},installedStart(job,&jobMu,stopJob))
 if e=json.NewEncoder(os.Stdout).Encode(result);e!=nil{return e}
 if result.Status!="evidence-consistent"{return errors.New("installed 18u check failed or inconclusive; no retry")};return nil
}
