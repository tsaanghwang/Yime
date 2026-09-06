package yimebroker

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"sync/atomic"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

// These rows and key strings are synthetic contract fixtures, not linguistic
// records or authorization to generate any connected-speech pronunciation.
func bundleGenerationFixture(t *testing.T, version, label string, enabled bool) BundleGenerationSpec {
	t.Helper()
	root := t.TempDir()
	spec := BundleGenerationSpec{Version: version, Modes: make(map[string]BundleModeSpec)}
	for _, mode := range supportedIndexModes {
		makeIndex := func(name, rows string) IndexSpec {
			source := filepath.Join(root, mode+"-"+name+".dict.yaml")
			if err := os.WriteFile(source, []byte("---\nname: synthetic\n...\n"+rows), 0o600); err != nil {
				t.Fatal(err)
			}
			index := filepath.Join(root, mode+"-"+name+".yidx")
			built, err := yimecore.BuildIndexFile(mode, source, index)
			if err != nil {
				t.Fatal(err)
			}
			return IndexSpec{Version: version, Mode: mode, Path: index, ExpectedSHA256: built.IndexSHA256}
		}
		modeSpec := BundleModeSpec{Core: makeIndex("core", "core-"+label+"\tc1\t100\ncanonical\tx1\t80\n")}
		if enabled {
			modeSpec.Modules = []BundleModuleSpec{{ID: "third-tone-stage5c", Index: makeIndex("alias", "alias-"+label+"\ts1\t1\n")}}
		}
		spec.Modes[mode] = modeSpec
	}
	return spec
}

func bundleGenerationVersion(spec BundleGenerationSpec, version string) BundleGenerationSpec {
	spec = cloneBundleGenerationSpec(spec)
	spec.Version = version
	for mode, modeSpec := range spec.Modes {
		modeSpec.Core.Version = version
		for i := range modeSpec.Modules {
			modeSpec.Modules[i].Index.Version = version
		}
		spec.Modes[mode] = modeSpec
	}
	return spec
}

func closeBundleFixtureEngine(t *testing.T, engine engineapi.Engine) {
	t.Helper()
	if err := engine.(interface{ Close() error }).Close(); err != nil {
		t.Fatal(err)
	}
}

func assertBundleFixtureText(t *testing.T, engine engineapi.Engine, code, want string) {
	t.Helper()
	engine.Reset()
	result, err := engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: code})
	if err != nil {
		t.Fatal(err)
	}
	for _, candidate := range result.State.Candidates {
		if candidate.Text == want {
			return
		}
	}
	t.Fatalf("synthetic expected candidate absent for %q", code)
}

func TestBundleGenerationManagerAtomicLeaseEnableDisable(t *testing.T) {
	isolateBundleGenerationTemp(t)
	off := bundleGenerationFixture(t, "off-1", "old", false)
	on := bundleGenerationFixture(t, "on-2", "new", true)
	manager, err := OpenBundleGenerationManager(off, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer manager.Close()
	oldSourceIDs := manager.Stats().ActiveSourceIDs
	oldEngines, newEngines := make(map[string]engineapi.Engine), make(map[string]engineapi.Engine)
	oldGeneration := manager.active
	for _, mode := range supportedIndexModes {
		oldEngines[mode], err = manager.NewEngine(mode)
		if err != nil {
			t.Fatal(err)
		}
		defer closeBundleFixtureEngine(t, oldEngines[mode])
	}
	if err := manager.Swap(on); err != nil {
		t.Fatal(err)
	}
	onGeneration := manager.active
	for _, mode := range supportedIndexModes {
		newEngines[mode], err = manager.NewEngine(mode)
		if err != nil {
			t.Fatal(err)
		}
		defer closeBundleFixtureEngine(t, newEngines[mode])
		assertBundleFixtureText(t, oldEngines[mode], "c1", "core-old")
		assertBundleFixtureText(t, newEngines[mode], "c1", "core-new")
		assertBundleFixtureText(t, newEngines[mode], "s1", "alias-new")
		if oldEngines[mode].(interface{ IndexVersion() string }).IndexVersion() != "off-1" ||
			newEngines[mode].(interface{ IndexVersion() string }).IndexVersion() != "on-2" {
			t.Fatal("session generation changed")
		}
	}
	if stats := manager.Stats(); stats.ActiveSessions != 6 || stats.RetiredGenerations != 1 || stats.Switches != 1 {
		t.Fatalf("unexpected lease counts: %+v", stats)
	}
	if err := manager.Swap(bundleGenerationVersion(off, "off-3")); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(oldSourceIDs, manager.Stats().ActiveSourceIDs) {
		t.Fatal("disabled bundle did not restore the canonical source identities")
	}
	for _, mode := range supportedIndexModes {
		engine, err := manager.NewEngine(mode)
		if err != nil {
			t.Fatal(err)
		}
		result, err := engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: "s1"})
		if err != nil || len(result.State.Candidates) != 0 {
			t.Fatal("module source survived disable in an untrained core-only fixture")
		}
		closeBundleFixtureEngine(t, engine)
		assertBundleFixtureText(t, newEngines[mode], "s1", "alias-new")
	}
	closeBundleFixtureEngine(t, oldEngines["full"])
	if oldGeneration.closed || manager.Stats().ActiveSessions != 5 {
		t.Fatal("closing one lease closed sibling sessions")
	}
	for _, mode := range []string{"variable", "shorthand"} {
		closeBundleFixtureEngine(t, oldEngines[mode])
	}
	if !oldGeneration.closed {
		t.Fatal("unleased retired generation was not closed")
	}
	if _, err := os.Stat(oldGeneration.root); !os.IsNotExist(err) {
		t.Fatal("retired private staging directory was not removed")
	}
	if err := manager.Close(); err != nil {
		t.Fatal(err)
	}
	if _, err := manager.NewEngine("full"); err == nil {
		t.Fatal("closed manager accepted a new lease")
	}
	for _, mode := range supportedIndexModes {
		assertBundleFixtureText(t, newEngines[mode], "s1", "alias-new")
		closeBundleFixtureEngine(t, newEngines[mode])
	}
	if !onGeneration.closed || manager.Stats().ActiveSessions != 0 || manager.Stats().RetiredGenerations != 0 {
		t.Fatal("manager close did not defer and then release all outstanding leases")
	}
	if _, err := newEngines["full"].Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: "s1"}); err == nil {
		t.Fatal("closed engine accessed a released generation")
	}
}

func TestBundleGenerationManagerRejectsIncompleteAndMixedSpecifications(t *testing.T) {
	isolateBundleGenerationTemp(t)
	initial := bundleGenerationFixture(t, "initial", "base", true)
	manager, err := OpenBundleGenerationManager(initial, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer manager.Close()
	sourceIDs := manager.Stats().ActiveSourceIDs
	tests := map[string]func(*BundleGenerationSpec){
		"missing-mode":   func(s *BundleGenerationSpec) { delete(s.Modes, "shorthand") },
		"unknown-mode":   func(s *BundleGenerationSpec) { s.Modes["bogus"] = s.Modes["full"]; delete(s.Modes, "shorthand") },
		"extra-mode":     func(s *BundleGenerationSpec) { s.Modes["bogus"] = s.Modes["full"] },
		"module-partial": func(s *BundleGenerationSpec) { m := s.Modes["shorthand"]; m.Modules = nil; s.Modes["shorthand"] = m },
		"unknown-module": func(s *BundleGenerationSpec) { s.Modes["full"].Modules[0].ID = "research-only" },
		"duplicate-module": func(s *BundleGenerationSpec) {
			m := s.Modes["full"]
			m.Modules = append(m.Modules, m.Modules[0])
			s.Modes["full"] = m
		},
		"mixed-version":       func(s *BundleGenerationSpec) { s.Modes["full"].Modules[0].Index.Version = "other" },
		"wrong-core-version":  func(s *BundleGenerationSpec) { m := s.Modes["full"]; m.Core.Version = "other"; s.Modes["full"] = m },
		"wrong-declared-mode": func(s *BundleGenerationSpec) { s.Modes["full"].Modules[0].Index.Mode = "variable" },
		"wrong-file-mode": func(s *BundleGenerationSpec) {
			m := s.Modes["shorthand"]
			m.Core.Path = s.Modes["full"].Core.Path
			m.Core.ExpectedSHA256 = s.Modes["full"].Core.ExpectedSHA256
			s.Modes["shorthand"] = m
		},
		"bad-hash": func(s *BundleGenerationSpec) {
			s.Modes["shorthand"].Modules[0].Index.ExpectedSHA256 = strings.Repeat("0", 64)
		},
		"non-hex-hash": func(s *BundleGenerationSpec) {
			s.Modes["full"].Modules[0].Index.ExpectedSHA256 = strings.Repeat("x", 64)
		},
		"relative-path": func(s *BundleGenerationSpec) { s.Modes["full"].Modules[0].Index.Path = "alias.yidx" },
		"missing-file": func(s *BundleGenerationSpec) {
			s.Modes["shorthand"].Modules[0].Index.Path = filepath.Join(t.TempDir(), "absent.yidx")
		},
	}
	for name, mutate := range tests {
		t.Run(name, func(t *testing.T) {
			spec := bundleGenerationVersion(initial, name)
			mutate(&spec)
			if err := manager.Swap(spec); err == nil {
				t.Fatal("invalid complete generation accepted")
			}
			if stats := manager.Stats(); stats.ActiveVersion != "initial" || !reflect.DeepEqual(stats.ActiveSourceIDs, sourceIDs) || stats.Switches != 0 {
				t.Fatal("failed staging partially published a mode or module")
			}
		})
	}
	if err := manager.Swap(initial); err == nil {
		t.Fatal("duplicate published version accepted")
	}
	changed := bundleGenerationFixture(t, "initial", "conflict", false)
	if err := manager.Swap(changed); err == nil {
		t.Fatal("duplicate version with different content accepted")
	}
	if err := manager.Swap(bundleGenerationVersion(initial, "second")); err != nil {
		t.Fatal(err)
	}
	if err := manager.Swap(initial); err == nil {
		t.Fatal("retired version was republished with ambiguous identity")
	}
}

type bundleFixtureClosable struct {
	engineapi.Engine
	closed *atomic.Int32
}

func (e *bundleFixtureClosable) Close() error { e.closed.Add(1); return nil }

func TestBundleGenerationManagerBuilderValidationAndSpecIsolation(t *testing.T) {
	isolateBundleGenerationTemp(t)
	initial := bundleGenerationFixture(t, "first", "base", true)
	var closed atomic.Int32
	var rejectBuild, rejectValidation atomic.Bool
	builder := func(mode string, bundle *yimecore.BundleIndex) (engineapi.Engine, error) {
		if rejectBuild.Load() && mode == "shorthand" {
			return nil, errors.New("synthetic builder failure")
		}
		engine, err := yimecore.NewBundleEngine(bundle, 9)
		return &bundleFixtureClosable{Engine: engine, closed: &closed}, err
	}
	validator := func(engine engineapi.Engine) error {
		if rejectValidation.Load() {
			return errors.New("synthetic validation failure")
		}
		return nil
	}
	manager, err := OpenBundleGenerationManager(initial, builder, validator)
	if err != nil {
		t.Fatal(err)
	}
	defer manager.Close()
	if closed.Load() != 3 {
		t.Fatal("successful staging did not close its validation engines")
	}
	rejectBuild.Store(true)
	if err := manager.Swap(bundleGenerationVersion(initial, "build-rejected")); err == nil || closed.Load() != 5 {
		t.Fatal("late builder failure did not preserve the active generation or close prior probes")
	}
	rejectBuild.Store(false)
	rejectValidation.Store(true)
	if err := manager.Swap(bundleGenerationVersion(initial, "validation-rejected")); err == nil || closed.Load() != 6 {
		t.Fatal("validator failure did not close its probe")
	}
	if manager.Stats().ActiveVersion != "first" || manager.Stats().Switches != 0 {
		t.Fatal("failed validator or builder published staging")
	}
	rejectValidation.Store(false)
	engine, err := manager.NewEngine("full")
	if err != nil {
		t.Fatal(err)
	}
	defer closeBundleFixtureEngine(t, engine)
	initial.Modes["full"].Modules[0].ID = "mutated"
	delete(initial.Modes, "variable")
	assertBundleFixtureText(t, engine, "s1", "alias-base")
	if _, err := manager.NewEngine("bogus"); err == nil {
		t.Fatal("unknown session mode accepted")
	}
	// Mutable caller maps and slices must also be isolated across staging's
	// builder callbacks, not merely dropped after publication.
	mutable := bundleGenerationFixture(t, "mutation", "copied", true)
	called := false
	copyManager, err := OpenBundleGenerationManager(mutable, func(mode string, bundle *yimecore.BundleIndex) (engineapi.Engine, error) {
		if !called {
			called = true
			mutable.Modes["shorthand"].Modules[0].ID = "mutated"
			delete(mutable.Modes, "variable")
		}
		return yimecore.NewBundleEngine(bundle, 9)
	}, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer copyManager.Close()
	if len(copyManager.Stats().ActiveSourceIDs) != 3 {
		t.Fatal("caller mutation changed the staged generation")
	}
}

func TestBundleGenerationManagerConcurrentPublicationIsWholeAndImmutable(t *testing.T) {
	isolateBundleGenerationTemp(t)
	initial := bundleGenerationFixture(t, "old", "old", false)
	next := bundleGenerationFixture(t, "next", "next", true)
	var block atomic.Bool
	staged, release := make(chan struct{}), make(chan struct{})
	manager, err := OpenBundleGenerationManager(initial, func(mode string, bundle *yimecore.BundleIndex) (engineapi.Engine, error) {
		if block.Load() && mode == "shorthand" {
			close(staged)
			<-release
		}
		return yimecore.NewBundleEngine(bundle, 9)
	}, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer manager.Close()
	block.Store(true)
	done := make(chan error, 1)
	go func() { done <- manager.Swap(next) }()
	<-staged
	if stats := manager.Stats(); stats.ActiveVersion != "old" || len(stats.ActiveSourceIDs) != 3 {
		t.Fatal("partially staged generation became visible")
	}
	// New leases opened while the final mode is staged must all pin old.
	block.Store(false)
	leases := make([]engineapi.Engine, 0, 3)
	for _, mode := range supportedIndexModes {
		engine, err := manager.NewEngine(mode)
		if err != nil {
			t.Fatal(err)
		}
		leases = append(leases, engine)
		defer closeBundleFixtureEngine(t, engine)
	}
	close(release)
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	errorsFound := make(chan error, 3)
	for i, engine := range leases {
		wg.Add(1)
		go func(mode string, engine engineapi.Engine) {
			defer wg.Done()
			for n := 0; n < 25; n++ {
				engine.Reset()
				result, err := engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: "c1"})
				if err != nil || len(result.State.Candidates) == 0 || result.State.Candidates[0].Text != "core-old" {
					errorsFound <- fmt.Errorf("old %s lease changed across publication", mode)
					return
				}
			}
		}(supportedIndexModes[i], engine)
	}
	wg.Wait()
	close(errorsFound)
	for err := range errorsFound {
		t.Error(err)
	}
	if stats := manager.Stats(); stats.ActiveVersion != "next" || len(stats.ActiveSourceIDs) != 3 || stats.ActiveSessions != 3 {
		t.Fatal("complete publication did not retain prior leases")
	}
	// Corrupting the caller's original file after publication cannot change
	// either the resident copy or subsequent sessions on that generation.
	if err := os.WriteFile(next.Modes["full"].Core.Path, []byte("corrupt external original"), 0o600); err != nil {
		t.Fatal(err)
	}
	engine, err := manager.NewEngine("full")
	if err != nil {
		t.Fatal(err)
	}
	defer closeBundleFixtureEngine(t, engine)
	assertBundleFixtureText(t, engine, "c1", "core-next")
}

func isolateBundleGenerationTemp(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	t.Setenv("TEMP", root)
	t.Setenv("TMP", root)
	return root
}

func TestBundleGenerationManagerModuleIdentityAndFailureResourceCleanup(t *testing.T) {
	stagingRoot := isolateBundleGenerationTemp(t)
	on := bundleGenerationFixture(t, "on", "same-core", true)
	manager, err := OpenBundleGenerationManager(on, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer manager.Close()
	enabledIDs := manager.Stats().ActiveSourceIDs
	off := bundleGenerationVersion(on, "off")
	for mode, modeSpec := range off.Modes {
		modeSpec.Modules = nil
		off.Modes[mode] = modeSpec
	}
	if err := manager.Swap(off); err != nil {
		t.Fatal(err)
	}
	for _, mode := range supportedIndexModes {
		if manager.Stats().ActiveSourceIDs[mode] == enabledIDs[mode] {
			t.Fatal("module removal with an unchanged core did not change bundle identity")
		}
	}
	if err := manager.Swap(bundleGenerationVersion(on, "reenabled")); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(manager.Stats().ActiveSourceIDs, enabledIDs) {
		t.Fatal("re-enabling identical content did not restore stable source identities")
	}
	countStages := func() int {
		t.Helper()
		matches, err := filepath.Glob(filepath.Join(stagingRoot, "yime-bundle-generation-*"))
		if err != nil {
			t.Fatal(err)
		}
		return len(matches)
	}
	if countStages() != 1 {
		t.Fatal("unleased retired staging directories leaked")
	}
	bad := bundleGenerationVersion(on, "rejected")
	bad.Modes["shorthand"].Modules[0].Index.ExpectedSHA256 = strings.Repeat("0", 64)
	if err := manager.Swap(bad); err == nil || countStages() != 1 {
		t.Fatal("failed late-mode staging leaked its temporary generation")
	}
	if err := manager.Close(); err != nil || countStages() != 0 {
		t.Fatal("unleased manager close leaked its staging directory")
	}
	// A builder failure during NewEngine must release the pinned lease, even
	// though the already-published generation remains available for recovery.
	var fail atomic.Bool
	failedManager, err := OpenBundleGenerationManager(on, func(_ string, bundle *yimecore.BundleIndex) (engineapi.Engine, error) {
		if fail.Load() {
			return nil, errors.New("synthetic new-session failure")
		}
		return yimecore.NewBundleEngine(bundle, 9)
	}, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer failedManager.Close()
	fail.Store(true)
	if _, err := failedManager.NewEngine("full"); err == nil || failedManager.Stats().ActiveSessions != 0 {
		t.Fatal("new-session builder failure leaked a lease")
	}
	if manager, err := OpenBundleGenerationManager(on, func(string, *yimecore.BundleIndex) (engineapi.Engine, error) {
		return nil, nil
	}, nil); err == nil || manager != nil || countStages() != 1 {
		t.Fatal("nil staging engine was accepted or leaked its staged files")
	}
}

func TestBundleGenerationManagerCloseDuringStagingAndConcurrentVersionConflict(t *testing.T) {
	for _, action := range []string{"close", "duplicate"} {
		t.Run(action, func(t *testing.T) {
			root := isolateBundleGenerationTemp(t)
			initial := bundleGenerationFixture(t, "old", "old", false)
			next := bundleGenerationFixture(t, "next", "next", true)
			var block atomic.Bool
			staged := make(chan struct{}, 2)
			release := make(chan struct{})
			manager, err := OpenBundleGenerationManager(initial, func(mode string, bundle *yimecore.BundleIndex) (engineapi.Engine, error) {
				if block.Load() && mode == "shorthand" {
					staged <- struct{}{}
					<-release
				}
				return yimecore.NewBundleEngine(bundle, 9)
			}, nil)
			if err != nil {
				t.Fatal(err)
			}
			defer manager.Close()
			block.Store(true)
			done := make(chan error, 2)
			go func() { done <- manager.Swap(next) }()
			<-staged
			if action == "close" {
				if err := manager.Close(); err != nil {
					t.Fatal(err)
				}
				close(release)
				if err := <-done; err == nil || manager.Stats().Switches != 0 {
					t.Fatal("staging published after manager close")
				}
				matches, err := filepath.Glob(filepath.Join(root, "yime-bundle-generation-*"))
				if err != nil || len(matches) != 0 {
					t.Fatal("aborted publication after close leaked resources")
				}
			} else {
				go func() { done <- manager.Swap(next) }()
				<-staged
				close(release)
				first, second := <-done, <-done
				if (first == nil) == (second == nil) || manager.Stats().Switches != 1 || manager.Stats().Rejected != 1 {
					t.Fatal("concurrent identical versions were not serialized to a single publication")
				}
				matches, err := filepath.Glob(filepath.Join(root, "yime-bundle-generation-*"))
				if err != nil || len(matches) != 1 {
					t.Fatal("losing concurrent publication leaked resources")
				}
			}
		})
	}
}
