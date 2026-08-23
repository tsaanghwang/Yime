// Command yimebroker is the E5-B standalone process experiment. It is not
// wired into PIME, TSF, installation, startup registration, or production.
package main

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

func main() {
	indexPath := flag.String("index", "", "validated YimeCore index")
	mode := flag.String("mode", "", "full, variable or shorthand")
	trustedClientID := flag.String("trusted-client-id", "", "identity bound by the launching transport adapter")
	exitBeforeRequest := flag.Int("experiment-exit-before-request", 0, "E5-B fault injection only")
	hangBeforeRequest := flag.Int("experiment-hang-before-request", 0, "E5-B fault injection only")
	flag.Parse()
	if *indexPath == "" || *mode == "" || *trustedClientID == "" {
		fail(fmt.Errorf("index, mode and trusted-client-id are required"))
	}
	index, err := yimecore.OpenFileIndex(*indexPath)
	if err != nil {
		fail(err)
	}
	defer index.Close()
	if index.Mode() != *mode {
		fail(fmt.Errorf("index mode %q does not match %q", index.Mode(), *mode))
	}
	factory := func() (engineapi.Engine, error) { return yimecore.NewFileEngine(index, 9) }
	dispatcher, err := yimebroker.NewDispatcher(factory, yimebroker.Config{})
	if err != nil {
		fail(err)
	}
	client := yimebroker.TrustedClient{ID: *trustedClientID}
	if *exitBeforeRequest == 0 && *hangBeforeRequest == 0 {
		err = yimebroker.ServeLines(context.Background(), os.Stdin, os.Stdout, dispatcher, client)
	} else {
		err = serveFaultExperiment(context.Background(), dispatcher, client, *exitBeforeRequest, *hangBeforeRequest)
	}
	if err != nil {
		fail(err)
	}
}

func serveFaultExperiment(ctx context.Context, dispatcher *yimebroker.Dispatcher, client yimebroker.TrustedClient, exitBefore, hangBefore int) error {
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 4096), yimebroker.MaxMessageBytes+1)
	writer := bufio.NewWriter(os.Stdout)
	requestNumber := 0
	for scanner.Scan() {
		if len(scanner.Bytes()) > yimebroker.MaxMessageBytes {
			return fmt.Errorf("broker request exceeds %d bytes", yimebroker.MaxMessageBytes)
		}
		requestNumber++
		if requestNumber == exitBefore {
			os.Exit(86)
		}
		if requestNumber == hangBefore {
			for {
				time.Sleep(time.Hour)
			}
		}
		if _, err := writer.Write(dispatcher.HandleJSON(ctx, client, append([]byte(nil), scanner.Bytes()...))); err != nil {
			return err
		}
		if err := writer.WriteByte('\n'); err != nil {
			return err
		}
		if err := writer.Flush(); err != nil {
			return err
		}
	}
	return scanner.Err()
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
