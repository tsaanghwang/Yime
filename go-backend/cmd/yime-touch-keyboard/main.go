// Command yime-touch-keyboard is an opt-in, uninstalled desktop keyboard lab.
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
	"io"
	"os"
	"path/filepath"
)

type options struct {
	Root, Profile, Zones, Shot, KeyView string
	DataDir, DataReport                 string
	ScreenMM, ObservedMM                float64
	Gutters, Smoke, CheckData           bool
	Preview                             bool
	Host, HostSmoke                     bool
}

func main() {
	var o options
	flag.StringVar(&o.Root, "root", "..", "checkout root")
	flag.StringVar(&o.KeyView, "key-view", "english", "english/original keycaps; in --preview this sets the English-input view preference")
	flag.StringVar(&o.Profile, "profile", "", "optional geometry profile JSON")
	flag.StringVar(&o.Zones, "numeric-zones", "both", "both/left/right/none")
	flag.BoolVar(&o.Gutters, "remove-gutters", false, "remove reviewed central and side gutters without scaling keys")
	flag.Float64Var(&o.ScreenMM, "screen-width-mm", 597.73, "monitor physical width in mm (27-inch 16:9 estimate; ruler calibration required)")
	flag.Float64Var(&o.ObservedMM, "ruler-observed-mm", 100, "actual measured length of the previous 100mm reference")
	flag.StringVar(&o.Shot, "screenshot", "", "render this keyboard to PNG and exit")
	flag.BoolVar(&o.Smoke, "self-test", false, "run isolated Win32 target-window input/focus checks and exit")
	flag.BoolVar(&o.CheckData, "check-data", false, "validate isolated Chinese dictionaries and in-process sessions, without a window or OS input")
	flag.BoolVar(&o.Preview, "preview", false, "Chinese desktop preview; output stays in this window, never sends OS input")
	flag.BoolVar(&o.Host, "host-input", false, "Chinese host-input lab; explicitly bind target before sending confirmed text")
	flag.BoolVar(&o.HostSmoke, "host-self-test", false, "with --host-input, test only disposable own EDIT windows and exit")
	flag.StringVar(&o.DataDir, "data-dir", "", "explicit experimental dictionary directory for --check-data, --preview or --host-input")
	flag.StringVar(&o.DataReport, "data-report", "", "optional JSON result file for --check-data")
	flag.Parse()
	if e := execute(o); e != nil {
		if o.Smoke || o.HostSmoke || o.Shot != "" || o.CheckData {
			fmt.Fprintln(os.Stderr, e)
		} else {
			showError(e)
		}
		os.Exit(1)
	}
}

func execute(o options) error {
	if o.HostSmoke && !o.Host {
		return fmt.Errorf("--host-self-test requires --host-input")
	}
	if o.Host && (o.Preview || o.CheckData || o.Smoke || o.Shot != "" || o.DataReport != "" || o.DataDir == "") {
		return fmt.Errorf("--host-input requires explicit --data-dir; incompatible with preview/check-data/self-test/screenshot/data-report")
	}
	if o.Preview && (o.CheckData || o.Smoke || o.DataReport != "" || o.DataDir == "") {
		return fmt.Errorf("--preview requires explicit --data-dir and cannot combine with --check-data, --self-test or --data-report")
	}
	if o.CheckData {
		return checkData(o)
	}
	if !o.Preview && !o.Host && (o.DataDir != "" || o.DataReport != "") {
		return fmt.Errorf("data options require --check-data, --preview or --host-input")
	}
	return run(o)
}
func load(o options) (tk.Board, error) {
	p := tk.Profile{NumericZones: o.Zones, RemoveGutters: o.Gutters}
	if o.Profile != "" {
		raw, e := os.ReadFile(o.Profile)
		if e != nil {
			return tk.Board{}, e
		}
		decoder := json.NewDecoder(bytes.NewReader(raw))
		decoder.DisallowUnknownFields()
		if e = decoder.Decode(&p); e != nil {
			return tk.Board{}, e
		}
		if e = decoder.Decode(new(any)); e != io.EOF {
			return tk.Board{}, fmt.Errorf("profile must contain one JSON object")
		}
	}
	root, e := filepath.Abs(o.Root)
	if e != nil {
		return tk.Board{}, e
	}
	b, e := tk.Load(filepath.Join(root, "prototypes", "touch-terminal", "data", "physical-layout.json"))
	if e != nil {
		return b, e
	}
	return tk.Arrange(b, p)
}
