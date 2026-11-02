package activatedloop

import (
 "context"
 "io"
 "os/exec"
 "sync"
 "time"
)

type ownedProcess struct { cmd *exec.Cmd; input io.WriteCloser; output io.ReadCloser; once sync.Once; err error }
func (p *ownedProcess) PID()int{return p.cmd.Process.Pid}
func (p *ownedProcess) Input()io.WriteCloser{return p.input}
func (p *ownedProcess) Output()io.Reader{return p.output}
func (p *ownedProcess) Wait()error{p.once.Do(func(){p.err=p.cmd.Wait()});return p.err}
func (p *ownedProcess) Stop(){_ = p.input.Close();_ = p.cmd.Process.Kill();_ = p.Wait();_ = p.output.Close()}
// StartOwned never uses a shell or breakaway flags. Both children inherit the
// required outer Windows Job. Context kills only these owned children; the outer
// Job remains the authoritative entire-tree timeout/termination proof.
func StartOwned(ctx context.Context,path string,args []string,dir string,stderr io.Writer)(Child,error){
 cmd:=exec.CommandContext(ctx,path,args...);cmd.Dir=dir;cmd.Stderr=stderr;cmd.WaitDelay=5*time.Second
 input,err:=cmd.StdinPipe();if err!=nil{return nil,err};output,err:=cmd.StdoutPipe();if err!=nil{_ = input.Close();return nil,err}
 if err=cmd.Start();err!=nil{_ = input.Close();_ = output.Close();return nil,err}
 return &ownedProcess{cmd:cmd,input:input,output:output},nil
}
