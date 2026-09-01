package yimebroker

import (
	"bufio"
	"context"
	"crypto/rand"
	"encoding/json"
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
	if client.ConnectionID == "" {
		var token [16]byte
		if _, err := rand.Read(token[:]); err != nil {
			return fmt.Errorf("create transport connection ID: %w", err)
		}
		client.ConnectionID = fmt.Sprintf("connection-%x", token)
	}
	connectionSessions := make(map[string]struct{})
	defer func() {
		for sessionID := range connectionSessions {
			dispatcher.CloseSession(client, sessionID)
		}
	}()
	scanner := bufio.NewScanner(input)
	scanner.Buffer(make([]byte, 4096), MaxMessageBytes+1)
	writer := bufio.NewWriter(output)
	for scanner.Scan() {
		if len(scanner.Bytes()) > MaxMessageBytes {
			return fmt.Errorf("broker request exceeds %d bytes", MaxMessageBytes)
		}
		frame := append([]byte(nil), scanner.Bytes()...)
		request, requestErr := DecodeRequest(frame)
		response := dispatcher.HandleJSON(ctx, client, frame)
		if requestErr == nil {
			var decoded Response
			if json.Unmarshal(response, &decoded) == nil && decoded.Error == nil {
				switch request.Operation {
				case OpenSession:
					connectionSessions[decoded.SessionID] = struct{}{}
				case CloseSession:
					delete(connectionSessions, request.SessionID)
				}
			}
		}
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
