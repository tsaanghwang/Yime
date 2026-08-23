package yimebroker

import (
	"bufio"
	"context"
	"fmt"
	"io"
)

// ServeLines binds one already-authenticated transport connection to one
// trusted client. Each request and response is one JSON line; client identity
// is never accepted from the line payload.
func ServeLines(ctx context.Context, input io.Reader, output io.Writer, dispatcher *Dispatcher, client TrustedClient) error {
	if dispatcher == nil {
		return fmt.Errorf("dispatcher is required")
	}
	scanner := bufio.NewScanner(input)
	scanner.Buffer(make([]byte, 4096), MaxMessageBytes+1)
	writer := bufio.NewWriter(output)
	for scanner.Scan() {
		if len(scanner.Bytes()) > MaxMessageBytes {
			return fmt.Errorf("broker request exceeds %d bytes", MaxMessageBytes)
		}
		response := dispatcher.HandleJSON(ctx, client, append([]byte(nil), scanner.Bytes()...))
		if _, err := writer.Write(response); err != nil {
			return err
		}
		if err := writer.WriteByte('\n'); err != nil {
			return err
		}
		if err := writer.Flush(); err != nil {
			return err
		}
	}
	if err := scanner.Err(); err != nil {
		return fmt.Errorf("read broker request: %w", err)
	}
	return nil
}
