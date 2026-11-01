// Dedicated development broker: named pipe only, never claimed stdio identity.
package main

import (
	"context"
	"flag"
	"fmt"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/internal/touchbroker"
	"os"
	"runtime"
	"strings"
)

func main() {
	if e := run(); e != nil {
		fmt.Fprintln(os.Stderr, e)
		os.Exit(1)
	}
}
func run() error {
	root := flag.String("root", "", "absolute dedicated source/resource root")
	data := flag.String("data-dir", "", "absolute isolated dictionary directory")
	pipe := flag.String("pipe-name", "", "unique controlled dedicated named pipe")
	pid := flag.Uint("tip-host-pid", 0, "actual controlled bootstrap TIP host process PID")
	flag.Parse()
	if runtime.GOOS != "windows" || runtime.GOARCH != "amd64" {
		return fmt.Errorf("dedicated broker requires Windows x64")
	}
	if !strings.HasPrefix(*pipe, `\\.\pipe\YimeBroker.18uTouch.v1.`) || len(*pipe) <= len(`\\.\pipe\YimeBroker.18uTouch.v1.`) || *pid == 0 || uint64(*pid) > 0xffffffff {
		return fmt.Errorf("dedicated endpoint and explicit TIP host PID required")
	}
	if e := requireNativeX64(); e != nil {
		return e
	}
	service, e := touchbroker.NewProduction(*root, *data)
	if e != nil {
		return e
	}
	return yimebroker.ServeNamedPipeHandler(context.Background(), yimebroker.NamedPipeConfig{Name: *pipe, MaxConnections: 2, MaxConnectionsPerClient: 2, RequireSameLogon: true, ExpectedClientProcessID: uint32(*pid), OnListening: func() { fmt.Println("READY yimebroker-18u") }}, service.ServeConnection)
}
