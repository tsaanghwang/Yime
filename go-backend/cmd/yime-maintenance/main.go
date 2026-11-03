// yime-maintenance is the native, package-bound entry for developer maintenance.
// A release must bind this binary to exactly one plan at build time. It never
// treats hashes supplied by the package being opened as publisher authentication.
package main

import (
	"bytes"
	"crypto/sha256"
	"debug/pe"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

var expectedPlanSHA string // Set with -ldflags only after the plan is finalized.

type fileRecord struct {
	Bytes  int64  `json:"bytes"`
	SHA256 string `json:"sha256"`
}
type shellRecord struct {
	Path   string `json:"path"`
	SHA256 string `json:"sha256"`
}
type maintenancePlan struct {
	Schema       string                `json:"schema"`
	Product      string                `json:"product"`
	Target       string                `json:"target"`
	SourceCommit string                `json:"sourceCommit"`
	Shell        shellRecord           `json:"shell"`
	Files        map[string]fileRecord `json:"files"`
}

var hashPattern = regexp.MustCompile(`^[0-9a-f]{64}$`)
var commitPattern = regexp.MustCompile(`^[0-9a-f]{40}$`)
var devicePattern = regexp.MustCompile(`^(COM|LPT)[1-9¹²³]$`)

const shellMember = "maintenance/powershell/pwsh.exe"

func validMember(name string) bool {
	if name == "" || strings.ContainsAny(name, "\\:\x00\r\n<>\"|?*") || strings.HasPrefix(name, "/") {
		return false
	}
	for _, p := range strings.Split(name, "/") {
		if p == "" || p == "." || p == ".." || strings.TrimSpace(p) != p || strings.HasSuffix(p, ".") {
			return false
		}
		base := strings.ToUpper(strings.SplitN(p, ".", 2)[0])
		if base == "CON" || base == "PRN" || base == "AUX" || base == "NUL" || devicePattern.MatchString(base) {
			return false
		}
	}
	return true
}

func parsePlan(raw []byte, expected string) (maintenancePlan, error) {
	var plan maintenancePlan
	if !hashPattern.MatchString(expected) || len(raw) > 4*1024*1024 {
		return plan, errors.New("unbound or oversized maintenance plan")
	}
	sum := sha256.Sum256(raw)
	if hex.EncodeToString(sum[:]) != expected {
		return plan, errors.New("maintenance plan differs from compiled identity")
	}
	d := json.NewDecoder(bytes.NewReader(raw))
	d.DisallowUnknownFields()
	if err := d.Decode(&plan); err != nil {
		return plan, err
	}
	if err := d.Decode(new(any)); err != io.EOF {
		return plan, errors.New("trailing maintenance plan data")
	}
	if plan.Schema != "yime-native-maintenance-v1" || plan.Target != "windows-arm64" || !commitPattern.MatchString(plan.SourceCommit) {
		return plan, errors.New("unsupported maintenance identity")
	}
	if plan.Product != "yimecore-18u" && plan.Product != "rime-pime" {
		return plan, errors.New("unsupported maintenance product")
	}
	if !hashPattern.MatchString(plan.Shell.SHA256) || plan.Shell.Path != shellMember {
		return plan, errors.New("unbound native shell")
	}
	if len(plan.Files) < 5 || len(plan.Files) > 4096 {
		return plan, errors.New("incomplete or oversized maintenance inventory")
	}
	seen := make(map[string]bool)
	for name, row := range plan.Files {
		if !validMember(name) || strings.EqualFold(name, "maintenance-plan.json") || strings.EqualFold(name, "YimeMaintenance.exe") || row.Bytes < 0 || !hashPattern.MatchString(row.SHA256) || seen[strings.ToLower(name)] {
			return plan, errors.New("invalid maintenance member")
		}
		seen[strings.ToLower(name)] = true
	}
	for _, name := range []string{"Setup.ps1", "Product.psm1", "product-package.json", "maintenance/preflight.ps1", shellMember} {
		if _, ok := plan.Files[name]; !ok {
			return plan, fmt.Errorf("missing bound entry: %s", name)
		}
	}
	if plan.Files[shellMember].SHA256 != plan.Shell.SHA256 {
		return plan, errors.New("shell identity differs from bound inventory")
	}
	return plan, nil
}

func verifyNativeShell(f *os.File) error {
	p, err := pe.NewFile(f)
	if err != nil {
		return fmt.Errorf("native shell PE: %w", err)
	}
	defer p.Close()
	if p.Machine != pe.IMAGE_FILE_MACHINE_ARM64 || p.Characteristics&pe.IMAGE_FILE_EXECUTABLE_IMAGE == 0 || p.Characteristics&pe.IMAGE_FILE_DLL != 0 {
		return errors.New("bundled shell must be native ARM64 executable")
	}
	if _, ok := p.OptionalHeader.(*pe.OptionalHeader64); !ok {
		return errors.New("bundled shell must have PE32+ headers")
	}
	return nil
}

func verifyStream(f *os.File, row fileRecord) error {
	st, err := f.Stat()
	if err != nil {
		return err
	}
	if !st.Mode().IsRegular() || st.Size() != row.Bytes {
		return errors.New("maintenance file type or size mismatch")
	}
	if _, err = f.Seek(0, io.SeekStart); err != nil {
		return err
	}
	h := sha256.New()
	if _, err = io.Copy(h, f); err != nil {
		return err
	}
	if hex.EncodeToString(h.Sum(nil)) != row.SHA256 {
		return errors.New("maintenance file hash mismatch")
	}
	_, err = f.Seek(0, io.SeekStart)
	return err
}

func main() {
	action := flag.String("action", "Check", "Check, Install, or Uninstall")
	planPath := flag.String("plan", "", "package plan bound into this executable")
	initiator := flag.String("initiating-sid", "", "same-account elevation binding")
	elevated := flag.Bool("elevated", false, "internal same-account elevated invocation")
	parentPID := flag.Uint("parent-pid", 0, "internal ordinary installation caller")
	parentStarted := flag.Uint64("parent-started", 0, "internal caller creation time")
	flag.Parse()
	if flag.NArg() != 0 || (*action != "Check" && *action != "Install" && *action != "Uninstall") {
		fmt.Fprintln(os.Stderr, "invalid maintenance operation")
		os.Exit(2)
	}
	if *planPath == "" {
		exe, err := os.Executable()
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
		*planPath = filepath.Join(filepath.Dir(exe), "maintenance-plan.json")
	}
	if err := maintain(*action, *planPath, *initiator, *elevated, *parentPID, *parentStarted); err != nil {
		fmt.Fprintln(os.Stderr, "maintenance stopped:", err)
		os.Exit(1)
	}
}
