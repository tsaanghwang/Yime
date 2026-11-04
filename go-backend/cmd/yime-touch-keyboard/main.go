// Command yime-touch-keyboard is an opt-in, uninstalled desktop keyboard lab.
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"github.com/tsaanghwang/Yime/go-backend/internal/installed18uhost"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
	"io"
	"os"
	"path/filepath"
	"strings"
)

var ownTSFDemoPackage string // Set only by the isolated demo builder.

type options struct {
	OwnTSFDemoSmoke                     bool
	OwnTSFDemo                          bool
	InstalledTSF                        bool
	InstalledSmoke                      bool
	InstallRoot, ManifestSHA            string
	BrokerPID                           uint
	Root, Profile, Zones, Shot, KeyView string
	DataDir, DataReport                 string
	InputTrace                          string
	Theme                               string
	KeySound                            string
	TouchUI                             bool
	PenRecontactMS                      int
	ScreenMM, ObservedMM                float64
	SaveRulerObservedMM                 string
	Gutters, Smoke, CheckData           bool
	Preview                             bool
	Host, HostSmoke                     bool
	EnglishOnly, CheckPackage           bool
	GeometryExplicit                    bool
}

func main() {
	var o options
	flag.StringVar(&o.Root, "root", "", "source root (source builds); portable builds use the executable directory")
	flag.StringVar(&o.KeyView, "key-view", "english", "english/original keycaps; in --preview this sets the English-input view preference")
	flag.StringVar(&o.Profile, "profile", "", "optional geometry profile JSON")
	flag.StringVar(&o.Zones, "numeric-zones", "both", "both/left/right/none")
	flag.BoolVar(&o.Gutters, "remove-gutters", false, "remove reviewed central and side gutters without scaling keys")
	flag.Float64Var(&o.ScreenMM, "screen-width-mm", defaultScreenWidthMM, "monitor physical width in mm (27-inch 16:9 estimate; ruler calibration required)")
	flag.Float64Var(&o.ObservedMM, "ruler-observed-mm", 100, "actual measured length of the previous 100mm reference")
	flag.StringVar(&o.SaveRulerObservedMM, "save-ruler-observed-mm", "", "installed 18u only: save a physical measurement of the uncalibrated 100mm reference for this display, then exit without opening the keyboard")
	flag.StringVar(&o.Shot, "screenshot", "", "render this keyboard to PNG and exit")
	flag.BoolVar(&o.Smoke, "self-test", false, "run isolated Win32 target-window input/focus checks and exit")
	flag.BoolVar(&o.CheckData, "check-data", false, "validate isolated Chinese dictionaries and in-process sessions, without a window or OS input")
	flag.BoolVar(&o.OwnTSFDemoSmoke, "own-tsf-demo-self-test", false, "isolated CI only: actual own-demo package UI path")
	flag.BoolVar(&o.OwnTSFDemo, "own-tsf-demo", false, "isolated native x64 own-host TSF demo; never writes to other applications")
	flag.BoolVar(&o.InstalledTSF, "installed-tsf", false, "complete installed 18u TIP frontend; no SendInput fallback")
	flag.BoolVar(&o.InstalledSmoke, "installed-smoke", false, "fixed installed frontend verification; requires the separate registered test host controller")
	flag.StringVar(&o.InstallRoot, "install-root", "", "installed 18u product root")
	flag.StringVar(&o.ManifestSHA, "manifest-sha256", "", "independent installed manifest hash")
	flag.UintVar(&o.BrokerPID, "broker-pid", 0, "runtime-owned installed broker PID")
	flag.BoolVar(&o.Preview, "preview", false, "Chinese desktop preview; output stays in this window, never sends OS input")
	flag.BoolVar(&o.Host, "host-input", false, "Chinese host-input lab; explicitly bind target before sending confirmed text")
	flag.BoolVar(&o.HostSmoke, "host-self-test", false, "with --host-input, test only disposable own EDIT windows and exit")
	flag.BoolVar(&o.EnglishOnly, "english-only", false, "use the legacy English route instead of the portable Chinese default")
	flag.BoolVar(&o.CheckPackage, "check-package", false, "verify complete portable resources and Chinese sessions without a window or OS input")
	flag.StringVar(&o.DataDir, "data-dir", "", "explicit experimental dictionary directory for --check-data, --preview or --host-input")
	flag.StringVar(&o.DataReport, "data-report", "", "optional JSON result file for --check-data")
	flag.StringVar(&o.InputTrace, "input-trace", "", "preview-only input diagnostics to a new JSONL file; no document text")
	flag.StringVar(&o.Theme, "theme", "original", "original/dark drawing palette; no layout or input behavior changes")
	flag.StringVar(&o.KeySound, "key-sound", "off", "off/click; optional local accepted-key feedback")
	flag.BoolVar(&o.TouchUI, "touch-ui", false, "opt-in compact touchscreen view with settings and large editing controls")
	flag.IntVar(&o.PenRecontactMS, "pen-recontact-ms", 0, "preview trial: suppress rapid same-pen same-key recontact; 0 disables, maximum250ms")
	flag.Parse()
	o.GeometryExplicit = hasGeometryOptions(flag.CommandLine)
	if e := execute(o); e != nil {
		if o.SaveRulerObservedMM != "" || o.InstalledSmoke || o.OwnTSFDemoSmoke || o.Smoke || o.HostSmoke || o.Shot != "" || o.CheckData || o.CheckPackage {
			fmt.Fprintln(os.Stderr, e)
		} else {
			showError(e)
		}
		os.Exit(1)
	}
}

func hasGeometryOptions(flags *flag.FlagSet) bool {
	explicit := false
	flags.Visit(func(f *flag.Flag) {
		if f.Name == "profile" || f.Name == "numeric-zones" || f.Name == "remove-gutters" {
			explicit = true
		}
	})
	return explicit
}

func execute(o options) error {
	if o.SaveRulerObservedMM != "" && (!o.InstalledTSF || o.InstalledSmoke || o.BrokerPID != 0) {
		return fmt.Errorf("saving calibration requires installed TSF mode without a Broker or smoke session")
	}
	if o.SaveRulerObservedMM != "" && o.ScreenMM != defaultScreenWidthMM {
		return fmt.Errorf("saving installed calibration requires the ordinary Runtime baseline --screen-width-mm %.2f; nondefault baseline was not saved", defaultScreenWidthMM)
	}
	if o.InstalledTSF {
		if o.OwnTSFDemo || o.OwnTSFDemoSmoke || o.Host || o.Preview || o.EnglishOnly || o.Smoke || o.HostSmoke || o.CheckData || o.CheckPackage || o.InputTrace != "" || o.Shot != "" || o.DataReport != "" || o.DataDir != "" || o.Root != "" || o.Profile != "" || (o.BrokerPID == 0 && o.SaveRulerObservedMM == "") || uint64(o.BrokerPID) > 0xffffffff {
			return fmt.Errorf("installed TSF mode requires its runtime and cannot combine with lab execution modes")
		}
		if _, e := installed18uhost.VerifyDesktopInstallation(o.InstallRoot, o.ManifestSHA); e != nil {
			return e
		}
		exe, e := os.Executable()
		if e != nil {
			return e
		}
		if !strings.EqualFold(filepath.Clean(exe), filepath.Join(o.InstallRoot, filepath.FromSlash(installed18uhost.FrontendPath))) {
			return fmt.Errorf("frontend must run from the verified installed payload")
		}
		o.Root = filepath.Join(o.InstallRoot, "source")
		o.Profile = filepath.Join(o.Root, "prototypes/touch-terminal/desktop/profiles/main-only.json")
		o.TouchUI = true
		return run(o)
	}
	if o.InstalledSmoke || o.InstallRoot != "" || o.ManifestSHA != "" || o.BrokerPID != 0 {
		return fmt.Errorf("installed options require --installed-tsf")
	}
	if o.OwnTSFDemoSmoke && !o.OwnTSFDemo {
		return fmt.Errorf("demo self-test requires --own-tsf-demo")
	}
	if ownTSFDemoPackage != "" && !o.OwnTSFDemo && !o.CheckPackage && !o.CheckData {
		return fmt.Errorf("this isolated demo requires explicit --own-tsf-demo; no legacy host fallback")
	}
	if o.OwnTSFDemo {
		if o.Host || o.Preview || o.EnglishOnly || o.Smoke || o.HostSmoke || o.CheckData || o.CheckPackage || o.InputTrace != "" || o.Shot != "" || o.PenRecontactMS != 0 || o.DataReport != "" {
			return fmt.Errorf("own TSF demo cannot combine with other execution modes")
		}
		o.TouchUI = true
		o.KeyView = "original"
	}
	if o.PenRecontactMS < 0 || o.PenRecontactMS > 250 || o.PenRecontactMS != 0 && (!o.Preview || !o.TouchUI || o.Host || o.EnglishOnly || o.CheckData || o.CheckPackage || o.Smoke || o.HostSmoke || o.Shot != "") {
		return fmt.Errorf("--pen-recontact-ms requires interactive --preview --touch-ui; use0..250")
	}
	if o.KeySound != "" && o.KeySound != "off" && o.KeySound != "click" {
		return fmt.Errorf("unknown key-sound %q; use off or click", o.KeySound)
	}
	if o.Theme != "" && o.Theme != "original" && o.Theme != "dark" {
		return fmt.Errorf("unknown theme %q; use original or dark", o.Theme)
	}
	if o.InputTrace != "" && (!o.Preview || o.Host || o.HostSmoke || o.EnglishOnly || o.CheckData || o.CheckPackage || o.Smoke || o.Shot != "") {
		return fmt.Errorf("--input-trace requires interactive --preview only")
	}
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	if err := preparePortable(&o, filepath.Dir(exe), portableResourcesSHA256); err != nil {
		return err
	}
	if o.TouchUI && (o.EnglishOnly || o.Smoke || o.HostSmoke || (!o.Preview && !o.Host && !o.CheckData && !o.OwnTSFDemo)) {
		return fmt.Errorf("--touch-ui requires Chinese preview/host/data-check mode; classic self-tests and --english-only use the original view")
	}
	if o.EnglishOnly && (o.Host || o.Preview || o.CheckData || o.HostSmoke) {
		return fmt.Errorf("--english-only cannot combine with Chinese session options")
	}
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
	if !o.Preview && !o.Host && !o.OwnTSFDemo && (o.DataDir != "" || o.DataReport != "") {
		return fmt.Errorf("data options require --check-data, --preview or --host-input")
	}
	if o.OwnTSFDemo {
		if _, err := demoHostPath(o.Root, portableResourcesSHA256); err != nil {
			return err
		}
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
	b, e = tk.Arrange(b, p)
	if e == nil && o.TouchUI {
		return touchScreenBoard(b)
	}
	return b, e
}
