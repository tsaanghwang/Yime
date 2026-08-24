package yimebroker

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const IndexControlSchema = "yime-index-control-v1"

type IndexControlRequest struct {
	SchemaVersion string     `json:"schema_version"`
	RequestID     string     `json:"request_id"`
	Action        string     `json:"action"`
	Mode          string     `json:"mode,omitempty"`
	Index         *IndexSpec `json:"index,omitempty"`
}

type IndexControlStatus struct {
	SchemaVersion  string                       `json:"schema_version"`
	ObservedAt     string                       `json:"observed_at"`
	RequestID      string                       `json:"request_id"`
	Action         string                       `json:"action"`
	Mode           string                       `json:"mode,omitempty"`
	Accepted       bool                         `json:"accepted"`
	Error          string                       `json:"error,omitempty"`
	Manager        IndexManagerStats            `json:"manager"`
	Managers       map[string]IndexManagerStats `json:"managers,omitempty"`
	ManifestSHA256 string                       `json:"manifest_sha256,omitempty"`
}

func WatchIndexControl(ctx context.Context, manifestPath, statusPath string, manager *IndexManager, interval time.Duration) error {
	if manager == nil || strings.TrimSpace(manifestPath) == "" || strings.TrimSpace(statusPath) == "" {
		return errors.New("manifest, status and index manager are required")
	}
	if interval < 10*time.Millisecond {
		return errors.New("index control interval must be at least 10ms")
	}
	if err := writeIndexControlStatus(statusPath, IndexControlStatus{
		SchemaVersion: IndexControlSchema, ObservedAt: time.Now().UTC().Format(time.RFC3339Nano),
		RequestID: "startup", Action: "observe", Accepted: true, Manager: manager.Stats(),
	}); err != nil {
		return err
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	lastDigest := ""
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
			data, err := os.ReadFile(manifestPath)
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			if err != nil {
				return err
			}
			digestBytes := sha256.Sum256(data)
			digest := hex.EncodeToString(digestBytes[:])
			if digest == lastDigest {
				continue
			}
			lastDigest = digest
			request, decodeErr := decodeIndexControl(data)
			status := IndexControlStatus{
				SchemaVersion: IndexControlSchema, ObservedAt: time.Now().UTC().Format(time.RFC3339Nano),
				RequestID: request.RequestID, Action: request.Action, ManifestSHA256: digest,
			}
			if decodeErr != nil {
				status.Error = decodeErr.Error()
			} else {
				switch request.Action {
				case "swap":
					if request.Index == nil {
						decodeErr = errors.New("swap requires index")
					} else {
						decodeErr = manager.Swap(*request.Index)
					}
				case "rollback":
					if request.Index != nil {
						decodeErr = errors.New("rollback must not include index")
					} else {
						decodeErr = manager.Rollback()
					}
				default:
					decodeErr = fmt.Errorf("unsupported index control action %q", request.Action)
				}
				if decodeErr != nil {
					status.Error = decodeErr.Error()
				}
			}
			status.Accepted = decodeErr == nil
			status.Manager = manager.Stats()
			if err := writeIndexControlStatus(statusPath, status); err != nil {
				return err
			}
		}
	}
}

// WatchModeIndexControl applies the existing transactional generation switch
// independently to full, variable and shorthand indices. Swap takes its mode
// from index.mode; rollback requires an explicit top-level mode because it has
// no index payload. Status always includes all three active generations.
func WatchModeIndexControl(ctx context.Context, manifestPath, statusPath string, managers *ModeIndexManager, interval time.Duration) error {
	if managers == nil || strings.TrimSpace(manifestPath) == "" || strings.TrimSpace(statusPath) == "" {
		return errors.New("manifest, status and mode index manager are required")
	}
	if interval < 10*time.Millisecond {
		return errors.New("index control interval must be at least 10ms")
	}
	if err := writeIndexControlStatus(statusPath, IndexControlStatus{
		SchemaVersion: IndexControlSchema, ObservedAt: time.Now().UTC().Format(time.RFC3339Nano),
		RequestID: "startup", Action: "observe", Accepted: true, Managers: managers.Stats(),
	}); err != nil {
		return err
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	lastDigest := ""
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
			data, err := os.ReadFile(manifestPath)
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			if err != nil {
				return err
			}
			digestBytes := sha256.Sum256(data)
			digest := hex.EncodeToString(digestBytes[:])
			if digest == lastDigest {
				continue
			}
			lastDigest = digest
			request, decodeErr := decodeIndexControl(data)
			mode := request.Mode
			status := IndexControlStatus{
				SchemaVersion: IndexControlSchema, ObservedAt: time.Now().UTC().Format(time.RFC3339Nano),
				RequestID: request.RequestID, Action: request.Action, Mode: mode, ManifestSHA256: digest,
			}
			if decodeErr == nil {
				switch request.Action {
				case "swap":
					if request.Index == nil {
						decodeErr = errors.New("swap requires index")
					} else if mode != "" && mode != request.Index.Mode {
						decodeErr = errors.New("control mode does not match index mode")
					} else {
						mode = request.Index.Mode
						decodeErr = managers.Swap(*request.Index)
					}
				case "rollback":
					if request.Index != nil || mode == "" {
						decodeErr = errors.New("mode rollback requires mode and no index")
					} else {
						decodeErr = managers.Rollback(mode)
					}
				default:
					decodeErr = fmt.Errorf("unsupported index control action %q", request.Action)
				}
			}
			status.Mode = mode
			status.Accepted = decodeErr == nil
			if decodeErr != nil {
				status.Error = decodeErr.Error()
			}
			if mode != "" {
				status.Manager, _ = managers.ModeStats(mode)
			}
			status.Managers = managers.Stats()
			if err := writeIndexControlStatus(statusPath, status); err != nil {
				return err
			}
		}
	}
}

func decodeIndexControl(data []byte) (IndexControlRequest, error) {
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var request IndexControlRequest
	if err := decoder.Decode(&request); err != nil {
		return request, err
	}
	if err := ensureJSONEOF(decoder); err != nil {
		return request, err
	}
	if request.SchemaVersion != IndexControlSchema || strings.TrimSpace(request.RequestID) == "" {
		return request, errors.New("invalid index control schema or request ID")
	}
	return request, nil
}

func writeIndexControlStatus(path string, status IndexControlStatus) error {
	data, err := json.MarshalIndent(status, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	directory := filepath.Dir(path)
	if err := os.MkdirAll(directory, 0o755); err != nil {
		return err
	}
	temporary, err := os.CreateTemp(directory, ".yime-index-status-*.tmp")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if _, err := temporary.Write(data); err != nil {
		_ = temporary.Close()
		return err
	}
	if err := temporary.Sync(); err != nil {
		_ = temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	if err := os.Rename(temporaryPath, path); err == nil {
		return nil
	}
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return os.Rename(temporaryPath, path)
}
