// Dedicated development broker: named pipe only, never claimed stdio identity.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"runtime"
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
	return runBroker(context.Background(), brokerOptions{*root, *data, *pipe, uint64(*pid)}, runtime.GOOS, runtime.GOARCH, productionBrokerDependencies())
}
