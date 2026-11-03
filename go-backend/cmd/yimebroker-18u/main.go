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
	desktop := flag.Bool("installed-desktop", false, "complete installed frontend/TIP service")
	installRoot := flag.String("install-root", "", "verified installed product root")
	anchor := flag.String("manifest-sha256", "", "independent installed manifest hash")
	flag.Parse()
	if runtime.GOOS != "windows" || (runtime.GOARCH != "amd64" && runtime.GOARCH != "arm64") {
		return fmt.Errorf("dedicated broker requires native Windows x64 or ARM64")
	}
	if e := requireNativeX64(); e != nil {
		return e
	}
	if *desktop {
		if *root != "" || *data != "" || *pipe != "" || *pid != 0 {
			return fmt.Errorf("installed desktop cannot use controlled-host options")
		}
		return touchbroker.ServeDesktop(context.Background(), *installRoot, *anchor, func() { fmt.Println("READY yimebroker-18u-desktop") })
	}
	if *installRoot != "" || *anchor != "" {
		return fmt.Errorf("installation options require installed-desktop")
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
