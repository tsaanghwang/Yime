//go:build windows && amd64

package main
import("syscall";"unsafe")
func nativeJobGate()bool{
 k:=syscall.NewLazyDLL("kernel32.dll")
 current,_,_:=k.NewProc("GetCurrentProcess").Call()
 var process,native uint16
 ok,_,_:=k.NewProc("IsWow64Process2").Call(current,uintptr(unsafe.Pointer(&process)),uintptr(unsafe.Pointer(&native)))
 if ok==0||process!=0||native!=0x8664{return false}
 var assigned int32
 ok,_,_ = k.NewProc("IsProcessInJob").Call(current,0,uintptr(unsafe.Pointer(&assigned)))
 return ok!=0&&assigned!=0
}
