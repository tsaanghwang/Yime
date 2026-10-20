package keyboardlab

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"time"
)

// Serve runs the original loopback-only web adapter over the shared runtime.
func Serve(root, dataDir string, port int) error {
	if port < 0 || port > 65535 {
		return errors.New("port must be between 0 and 65535")
	}
	runtime, err := OpenRuntime(root, dataDir)
	if err != nil {
		return err
	}
	defer runtime.Close()
	root, _ = filepath.Abs(root)
	staticRoot := filepath.Join(root, "prototypes", "touch-terminal")
	listener, err := net.Listen("tcp4", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		return err
	}
	defer listener.Close()
	app := &lab{staticRoot: staticRoot, layoutID: runtime.LayoutID, origin: "http://" + listener.Addr().String(), token: randomID(), service: runtime.Sessions, builds: runtime.Builds}
	app.repositoryRoot = root
	server := &http.Server{Handler: app, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 30 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 16 << 10}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()
	shutdownDone := make(chan struct{})
	go func() {
		defer close(shutdownDone)
		<-ctx.Done()
		// Wait for in-flight sessions before unmapping their shared indexes.
		_ = server.Shutdown(context.Background())
	}()
	log.Printf("Yime keyboard lab: %s (real YimeCore, page-only commits, no installed input method)", app.origin)
	err = server.Serve(listener)
	cancel()
	<-shutdownDone
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}
