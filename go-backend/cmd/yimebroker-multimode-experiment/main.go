// Command yimebroker-multimode-experiment verifies the E6-C package Broker's
// shared durable learning and per-mode transactional index generations.
package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/internal/processmemory"
)

const (
	toolVersion    = "yimebroker-e6c-multimode-package-v3"
	requestTimeout = 2 * time.Second
	controlTimeout = 2 * time.Second
	startupTimeout = 30 * time.Second
)

type latencyEvidence struct {
	Mode             string `json:"mode"`
	Iterations       int    `json:"iterations"`
	P50NS            int64  `json:"p50_ns"`
	P95NS            int64  `json:"p95_ns"`
	P99NS            int64  `json:"p99_ns"`
	MaxNS            int64  `json:"max_ns"`
	FirstHalfP95NS   int64  `json:"first_half_p95_ns"`
	SecondHalfP95NS  int64  `json:"second_half_p95_ns"`
	StickyDriftLimit int64  `json:"sticky_drift_limit_ns"`
	Passed           bool   `json:"passed"`
}

type residentEvidence struct {
	AllModesResident       bool                   `json:"all_modes_resident"`
	StartupElapsedNS       int64                  `json:"startup_elapsed_ns"`
	MemoryBeforeSoak       processmemory.Snapshot `json:"memory_before_soak"`
	MemoryAfterSoak        processmemory.Snapshot `json:"memory_after_soak"`
	PrivateGrowthBytes     int64                  `json:"private_growth_bytes"`
	WorkingSetGrowthBytes  int64                  `json:"working_set_growth_bytes"`
	ModeLatency            []latencyEvidence      `json:"mode_latency"`
	RestartModesResident   bool                   `json:"restart_modes_resident"`
	NoSevereLatencyOrStick bool                   `json:"no_severe_latency_or_stickiness"`
	Passed                 bool                   `json:"passed"`
}

type modeEvidence struct {
	Mode                        string `json:"mode"`
	LearningCode                string `json:"learning_code"`
	LearnedText                 string `json:"learned_text"`
	Selections                  int    `json:"selections"`
	RecoveredFirst              string `json:"recovered_first"`
	RecoveredUserScore          int64  `json:"recovered_user_score"`
	LearningPersistencePassed   bool   `json:"learning_persistence_passed"`
	RejectedSwitchPreservedV1   bool   `json:"rejected_switch_preserved_v1"`
	OriginalCompositionStayedV1 bool   `json:"original_composition_stayed_v1"`
	NewSessionUsedV2            bool   `json:"new_session_used_v2"`
	V2SessionSurvivedRollback   bool   `json:"v2_session_survived_rollback"`
	PostRollbackSessionUsedV1   bool   `json:"post_rollback_session_used_v1"`
	FailedSwitchRollbackPassed  bool   `json:"failed_switch_rollback_passed"`
	InheritedPartialNodes       int    `json:"inherited_partial_nodes"`
	IncompleteSecondTermPassed  bool   `json:"incomplete_second_term_passed"`
	GeneratedSentenceFirst      string `json:"generated_sentence_first"`
	GeneratedSentencePassed     bool   `json:"generated_sentence_passed"`
	FirstWordCandidateCount     int    `json:"first_word_candidate_count"`
	FirstWordSequencePassed     bool   `json:"first_word_sequence_passed"`
	FirstWordReplacementPassed  bool   `json:"first_word_replacement_passed"`
	SentenceSegmentSwitchPassed bool   `json:"sentence_segment_switch_passed"`
	FocusedSentenceCommitPassed bool   `json:"focused_sentence_commit_passed"`
}

type report struct {
	ToolVersion                  string                           `json:"tool_version"`
	GeneratedAt                  string                           `json:"generated_at"`
	BrokerPath                   string                           `json:"broker_path"`
	IndexRoot                    string                           `json:"index_root"`
	UserModelSourceID            string                           `json:"user_model_source_id"`
	RecoveredGeneration          uint64                           `json:"recovered_generation"`
	SnapshotSHA256               string                           `json:"snapshot_sha256"`
	JournalSHA256                string                           `json:"journal_sha256"`
	FinalStats                   yimebroker.DurableUserModelStats `json:"final_stats"`
	Modes                        []modeEvidence                   `json:"modes"`
	SnapshotAbsentBeforeCrash    bool                             `json:"snapshot_absent_before_crash"`
	JournalPresentBeforeCrash    bool                             `json:"journal_present_before_crash"`
	CrashJournalRecoveryPassed   bool                             `json:"crash_journal_recovery_passed"`
	DefaultIdleSessionIsVariable bool                             `json:"default_idle_session_is_variable"`
	AllModesPassed               bool                             `json:"all_modes_passed"`
	CleanRestartPassed           bool                             `json:"clean_restart_passed"`
	ProductionRimePIMEChanged    bool                             `json:"production_rime_pime_changed"`
	ResidentSystemLexicon        residentEvidence                 `json:"resident_system_lexicon"`
	Passed                       bool                             `json:"passed"`
}

type modeProbe struct {
	mode           string
	code           string
	path           string
	hash           string
	text           string
	sentencePrefix string
	sentenceSecond string
}

func main() {
	brokerPath := flag.String("broker", "", "packaged E6-C YimeBroker executable")
	indexRoot := flag.String("index-root", "", "packaged full, variable and shorthand index directory")
	snapshot := flag.String("snapshot", "", "trial user-model snapshot")
	journal := flag.String("journal", "", "trial user-model journal")
	manifest := flag.String("manifest", "", "trial multi-index control manifest")
	status := flag.String("status", "", "trial multi-index control status")
	output := flag.String("output", "", "evidence JSON")
	sourceID := flag.String("source-id", "yimecore-e6c-three-mode-trial-v1", "stable trial user-model namespace")
	flag.Parse()
	if *brokerPath == "" || *indexRoot == "" || *snapshot == "" || *journal == "" || *manifest == "" || *status == "" || *output == "" || *sourceID == "" {
		fail(errors.New("broker, index-root, snapshot, journal, manifest, status, output and source-id are required"))
	}
	probes := []modeProbe{
		{mode: "full", code: "bjjj", sentencePrefix: "nlllhsso", sentenceSecond: "psdj1m,."},
		{mode: "variable", code: "bj", sentencePrefix: "nlhso", sentenceSecond: "psdj1m,."},
		{mode: "shorthand", code: "bl", sentencePrefix: "nlhso", sentenceSecond: "psdj1m."},
	}
	for index := range probes {
		probes[index].path = filepath.Join(*indexRoot, probes[index].mode+".yidx")
		hash, err := yimebroker.IndexFileSHA256(probes[index].path)
		if err != nil {
			fail(err)
		}
		probes[index].hash = hash
	}
	startupAt := time.Now()
	process, err := startBroker(*brokerPath, *indexRoot, *snapshot, *journal, *manifest, *status, *sourceID)
	if err != nil {
		fail(err)
	}
	startupStatus, err := waitStatusWithin(*status, "startup", startupTimeout)
	if err != nil {
		process.terminate()
		fail(err)
	}
	resident := residentEvidence{StartupElapsedNS: time.Since(startupAt).Nanoseconds()}
	resident.AllModesResident = allManagersUseLoadMode(startupStatus, "resident")
	resident.MemoryBeforeSoak, err = processmemory.PID(process.command.Process.Pid)
	if err != nil {
		process.terminate()
		fail(err)
	}
	resident.ModeLatency, err = process.measureSoak(probes, 250)
	if err != nil {
		process.terminate()
		fail(err)
	}
	resident.MemoryAfterSoak, err = processmemory.PID(process.command.Process.Pid)
	if err != nil {
		process.terminate()
		fail(err)
	}
	resident.PrivateGrowthBytes = int64(resident.MemoryAfterSoak.PrivateBytes) - int64(resident.MemoryBeforeSoak.PrivateBytes)
	resident.WorkingSetGrowthBytes = int64(resident.MemoryAfterSoak.WorkingSetBytes) - int64(resident.MemoryBeforeSoak.WorkingSetBytes)
	resident.NoSevereLatencyOrStick = true
	for _, latency := range resident.ModeLatency {
		resident.NoSevereLatencyOrStick = resident.NoSevereLatencyOrStick && latency.Passed
	}
	evidence := make([]modeEvidence, 0, len(probes))
	const selections = 3
	for probeIndex := range probes {
		probe := &probes[probeIndex]
		inheritedNodes, inheritedPassed, generatedFirst, generatedPassed, sentenceErr := process.verifyContinuousSentence(*probe)
		if sentenceErr != nil {
			process.terminate()
			fail(sentenceErr)
		}
		firstWordCount, firstWordPassed, segmentSwitchPassed, replacementPassed, focusedCommitPassed, dynamicErr :=
			process.verifyDynamicSentence(*probe)
		if dynamicErr != nil {
			process.terminate()
			fail(dynamicErr)
		}
		session, _, err := process.open(probe.mode)
		if err != nil {
			process.terminate()
			fail(err)
		}
		state, _, err := process.applyCode(session, probe.code, true)
		if err != nil || len(state.Candidates) < 2 {
			process.terminate()
			fail(fmt.Errorf("%s learning probe has fewer than two candidates: %w", probe.mode, err))
		}
		probe.text = state.Candidates[1].Text
		for selection := 0; selection < selections; selection++ {
			state, _, err = process.applyCode(session, probe.code, true)
			if err != nil {
				process.terminate()
				fail(err)
			}
			candidate := findCandidate(state.Candidates, probe.text)
			if candidate == nil {
				process.terminate()
				fail(fmt.Errorf("%s learning target %q disappeared", probe.mode, probe.text))
			}
			mutationID := fmt.Sprintf("e6c-package-%s-selection-%d", probe.mode, selection)
			selected, err := process.selectCandidate(session, candidate.ID, mutationID)
			if err != nil || selected.Result == nil || selected.Result.Commit != probe.text {
				process.terminate()
				fail(fmt.Errorf("%s durable selection failed: %w", probe.mode, err))
			}
		}
		_ = process.closeSession(session)
		evidence = append(evidence, modeEvidence{
			Mode: probe.mode, LearningCode: probe.code, LearnedText: probe.text, Selections: selections,
			InheritedPartialNodes: inheritedNodes, IncompleteSecondTermPassed: inheritedPassed,
			GeneratedSentenceFirst: generatedFirst, GeneratedSentencePassed: generatedPassed,
			FirstWordCandidateCount: firstWordCount, FirstWordSequencePassed: firstWordPassed,
			SentenceSegmentSwitchPassed: segmentSwitchPassed, FirstWordReplacementPassed: replacementPassed,
			FocusedSentenceCommitPassed: focusedCommitPassed,
		})
	}

	for index, probe := range probes {
		pinned, opened, err := process.open(probe.mode)
		if err != nil {
			process.terminate()
			fail(err)
		}
		_, partial, err := process.applyCode(pinned, probe.code[:1], false)
		if err != nil {
			process.terminate()
			fail(err)
		}
		badID := "reject-" + probe.mode
		bad := runControl(*manifest, *status, yimebroker.IndexControlRequest{
			SchemaVersion: yimebroker.IndexControlSchema, RequestID: badID, Action: "swap",
			Index: &yimebroker.IndexSpec{Version: "bad", Mode: probe.mode, Path: probe.path, ExpectedSHA256: strings.Repeat("0", 64)},
		})
		_, continued, err := process.applyCode(pinned, probe.code[1:], false)
		if err != nil {
			process.terminate()
			fail(err)
		}
		evidence[index].RejectedSwitchPreservedV1 = !bad.Accepted && bad.Manager.ActiveVersion == "v1" && bad.Managers[probe.mode].ActiveVersion == "v1"
		evidence[index].OriginalCompositionStayedV1 = opened.EngineVersion == "v1" && partial.EngineVersion == "v1" && continued.EngineVersion == "v1" && continued.Result != nil && continued.Result.State.RawInput == probe.code

		swapID := "swap-" + probe.mode
		swapped := runControl(*manifest, *status, yimebroker.IndexControlRequest{
			SchemaVersion: yimebroker.IndexControlSchema, RequestID: swapID, Action: "swap",
			Index: &yimebroker.IndexSpec{Version: "v2", Mode: probe.mode, Path: probe.path, ExpectedSHA256: probe.hash},
		})
		v2, v2Opened, err := process.open(probe.mode)
		if err != nil {
			process.terminate()
			fail(err)
		}
		evidence[index].NewSessionUsedV2 = swapped.Accepted && swapped.Manager.ActiveVersion == "v2" && v2Opened.EngineVersion == "v2"
		rollbackID := "rollback-" + probe.mode
		rolledBack := runControl(*manifest, *status, yimebroker.IndexControlRequest{
			SchemaVersion: yimebroker.IndexControlSchema, RequestID: rollbackID, Action: "rollback", Mode: probe.mode,
		})
		v2Reset, err := process.reset(v2)
		if err != nil {
			process.terminate()
			fail(err)
		}
		post, postOpened, err := process.open(probe.mode)
		if err != nil {
			process.terminate()
			fail(err)
		}
		evidence[index].V2SessionSurvivedRollback = v2Reset.EngineVersion == "v2"
		evidence[index].PostRollbackSessionUsedV1 = rolledBack.Accepted && rolledBack.Manager.ActiveVersion == "v1" && postOpened.EngineVersion == "v1"
		evidence[index].FailedSwitchRollbackPassed = evidence[index].RejectedSwitchPreservedV1 && evidence[index].OriginalCompositionStayedV1 && evidence[index].NewSessionUsedV2 && evidence[index].V2SessionSurvivedRollback && evidence[index].PostRollbackSessionUsedV1
		_ = process.closeSession(pinned)
		_ = process.closeSession(v2)
		_ = process.closeSession(post)
	}
	snapshotAbsentBeforeCrash := !fileExists(*snapshot)
	journalPresentBeforeCrash := fileSize(*journal) > 0
	process.terminate()

	restarted, err := startBroker(*brokerPath, *indexRoot, *snapshot, *journal, *manifest, *status, *sourceID)
	if err != nil {
		fail(err)
	}
	restartStatus, err := waitStatusWithin(*status, "startup", startupTimeout)
	if err != nil {
		restarted.terminate()
		fail(err)
	}
	resident.RestartModesResident = allManagersUseLoadMode(restartStatus, "resident")
	resident.Passed = resident.AllModesResident && resident.RestartModesResident && resident.NoSevereLatencyOrStick
	for index, probe := range probes {
		session, _, err := restarted.open(probe.mode)
		if err != nil {
			restarted.terminate()
			fail(err)
		}
		state, _, err := restarted.applyCode(session, probe.code, true)
		if err != nil || len(state.Candidates) == 0 {
			restarted.terminate()
			fail(fmt.Errorf("%s recovery query failed: %w", probe.mode, err))
		}
		evidence[index].RecoveredFirst = state.Candidates[0].Text
		evidence[index].RecoveredUserScore = state.Candidates[0].Score.User
		evidence[index].LearningPersistencePassed = state.Candidates[0].Text == probe.text && state.Candidates[0].Score.User > 0
		_ = restarted.closeSession(session)
	}
	defaultSession, _, err := restarted.open("")
	if err != nil {
		restarted.terminate()
		fail(err)
	}
	defaultState, _, err := restarted.applyCode(defaultSession, probes[1].code, true)
	defaultVariable := err == nil && len(defaultState.Candidates) > 0 && defaultState.Candidates[0].Text == probes[1].text
	_ = restarted.closeSession(defaultSession)
	cleanRestart := restarted.close()

	store, err := yimebroker.OpenDurableUserModel(yimebroker.DurableUserModelConfig{
		SnapshotPath: *snapshot, JournalPath: *journal, SourceID: *sourceID, CheckpointEvery: 1000,
	})
	if err != nil {
		fail(err)
	}
	finalStats := store.Stats()
	generation := store.Model().Generation()
	if err := store.Close(); err != nil {
		fail(err)
	}
	allModes := true
	for _, item := range evidence {
		allModes = allModes && item.LearningPersistencePassed && item.FailedSwitchRollbackPassed &&
			item.IncompleteSecondTermPassed && item.GeneratedSentencePassed &&
			item.FirstWordSequencePassed && item.SentenceSegmentSwitchPassed &&
			item.FirstWordReplacementPassed &&
			item.FocusedSentenceCommitPassed
	}
	crashJournalRecovery := snapshotAbsentBeforeCrash && journalPresentBeforeCrash
	for _, item := range evidence {
		crashJournalRecovery = crashJournalRecovery && item.LearningPersistencePassed
	}
	result := report{
		ToolVersion: toolVersion, GeneratedAt: time.Now().UTC().Format(time.RFC3339Nano),
		BrokerPath: filepath.Clean(*brokerPath), IndexRoot: filepath.Clean(*indexRoot), UserModelSourceID: *sourceID,
		RecoveredGeneration: generation, SnapshotSHA256: hashFile(*snapshot), JournalSHA256: hashFile(*journal),
		FinalStats: finalStats, Modes: evidence, SnapshotAbsentBeforeCrash: snapshotAbsentBeforeCrash,
		JournalPresentBeforeCrash: journalPresentBeforeCrash, CrashJournalRecoveryPassed: crashJournalRecovery,
		DefaultIdleSessionIsVariable: defaultVariable,
		AllModesPassed:               allModes, CleanRestartPassed: cleanRestart, ProductionRimePIMEChanged: false,
		ResidentSystemLexicon: resident,
	}
	const dynamicSentenceCommitsPerMode = 1
	result.Passed = result.AllModesPassed && result.CrashJournalRecoveryPassed && result.DefaultIdleSessionIsVariable && result.CleanRestartPassed && result.ResidentSystemLexicon.Passed && result.RecoveredGeneration == uint64(len(probes)*(selections+dynamicSentenceCommitsPerMode)) && !result.ProductionRimePIMEChanged
	writeJSON(*output, result)
	fmt.Printf("YimeBroker E6-C package: passed=%t generation=%d modes=%d\n", result.Passed, generation, len(evidence))
	if !result.Passed {
		os.Exit(1)
	}
}

type brokerSession struct {
	id       string
	sequence uint64
}

type brokerProcess struct {
	command *exec.Cmd
	input   io.WriteCloser
	output  *bufio.Reader
	waited  bool
}

func startBroker(binary, indexRoot, snapshot, journal, manifest, status, sourceID string) (*brokerProcess, error) {
	command := exec.Command(binary, "-index-root", indexRoot, "-default-mode", "variable", "-trusted-client-id", "e6c-package-supervisor",
		"-user-model-snapshot", snapshot, "-user-model-journal", journal, "-user-model-source-id", sourceID,
		"-user-model-checkpoint-every", "1000", "-index-version", "v1", "-index-control-manifest", manifest, "-index-control-status", status)
	input, err := command.StdinPipe()
	if err != nil {
		return nil, err
	}
	output, err := command.StdoutPipe()
	if err != nil {
		return nil, err
	}
	command.Stderr = os.Stderr
	if err := command.Start(); err != nil {
		return nil, err
	}
	return &brokerProcess{command: command, input: input, output: bufio.NewReader(output)}, nil
}

func (p *brokerProcess) open(mode string) (*brokerSession, yimebroker.Response, error) {
	response, err := p.send(yimebroker.Request{Version: 1, Sequence: 1, Operation: yimebroker.OpenSession, Mode: mode})
	return &brokerSession{id: response.SessionID, sequence: 1}, response, err
}

func (p *brokerProcess) applyCode(session *brokerSession, code string, reset bool) (engineapi.State, yimebroker.Response, error) {
	var response yimebroker.Response
	var err error
	if reset {
		response, err = p.reset(session)
		if err != nil {
			return engineapi.State{}, response, err
		}
	}
	for _, key := range code {
		session.sequence++
		response, err = p.send(yimebroker.Request{Version: 1, Sequence: session.sequence, SessionID: session.id,
			Operation: yimebroker.ApplyEvent, Event: engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)}})
		if err != nil {
			return engineapi.State{}, response, err
		}
	}
	if response.Result == nil {
		return engineapi.State{}, response, errors.New("apply response has no result")
	}
	return response.Result.State, response, nil
}

func (p *brokerProcess) measureSoak(probes []modeProbe, iterations int) ([]latencyEvidence, error) {
	evidence := make([]latencyEvidence, 0, len(probes))
	for _, probe := range probes {
		session, _, err := p.open(probe.mode)
		if err != nil {
			return nil, err
		}
		durations := make([]time.Duration, 0, iterations)
		for iteration := 0; iteration < iterations; iteration++ {
			started := time.Now()
			state, _, applyErr := p.applyCode(session, probe.code, true)
			durations = append(durations, time.Since(started))
			if applyErr != nil {
				_ = p.closeSession(session)
				return nil, fmt.Errorf("%s resident soak iteration %d: %w", probe.mode, iteration, applyErr)
			}
			if len(state.Candidates) == 0 {
				_ = p.closeSession(session)
				return nil, fmt.Errorf("%s resident soak iteration %d returned no candidates", probe.mode, iteration)
			}
		}
		if err := p.closeSession(session); err != nil {
			return nil, err
		}
		evidence = append(evidence, summarizeModeLatency(probe.mode, durations))
	}
	return evidence, nil
}

func (p *brokerProcess) verifyContinuousSentence(probe modeProbe) (int, bool, string, bool, error) {
	session, _, err := p.open(probe.mode)
	if err != nil {
		return 0, false, "", false, err
	}
	defer p.closeSession(session)
	if _, _, err := p.applyCode(session, probe.sentencePrefix, true); err != nil {
		return 0, false, "", false, err
	}
	inheritedNodes := 0
	for index, key := range probe.sentenceSecond {
		session.sequence++
		response, applyErr := p.send(yimebroker.Request{
			Version: 1, Sequence: session.sequence, SessionID: session.id, Operation: yimebroker.ApplyEvent,
			Event: engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)},
		})
		if applyErr != nil {
			return inheritedNodes, false, "", false, fmt.Errorf("%s continuous sentence key %d: %w", probe.mode, index, applyErr)
		}
		if response.Result == nil {
			return inheritedNodes, false, "", false, fmt.Errorf("%s continuous sentence key %d returned no state", probe.mode, index)
		}
		candidates := response.Result.State.Candidates
		if len(candidates) == 0 {
			return inheritedNodes, false, "", false, fmt.Errorf("%s continuous sentence lost candidates at second-term key %d", probe.mode, index)
		}
		if index < len(probe.sentenceSecond)-1 {
			inherited := false
			for _, candidate := range candidates {
				if strings.HasPrefix(candidate.Text, "你好") {
					inherited = true
					break
				}
			}
			if !inherited {
				return inheritedNodes, false, "", false, fmt.Errorf("%s second-term node %d did not inherit the completed prefix", probe.mode, index)
			}
			inheritedNodes++
			continue
		}
		first := candidates[0]
		generatedPassed := first.Text == "你好排序" && first.Exact && len(first.Segments) == 2
		return inheritedNodes, inheritedNodes == len(probe.sentenceSecond)-1, first.Text, generatedPassed, nil
	}
	return inheritedNodes, false, "", false, errors.New("continuous sentence probe has an empty second code")
}

func (p *brokerProcess) verifyDynamicSentence(probe modeProbe) (int, bool, bool, bool, bool, error) {
	session, _, err := p.open(probe.mode)
	if err != nil {
		return 0, false, false, false, false, err
	}
	defer p.closeSession(session)
	state, _, err := p.applyCode(session, probe.sentencePrefix+probe.sentenceSecond, true)
	if err != nil {
		return 0, false, false, false, false, err
	}
	var sentence *engineapi.Candidate
	for index := range state.Candidates {
		candidate := &state.Candidates[index]
		if candidate.Exact && len(candidate.Segments) >= 2 && candidate.Segments[0].Start == 0 {
			sentence = candidate
			break
		}
	}
	if sentence == nil {
		return 0, false, false, false, false, fmt.Errorf("%s dynamic sentence candidate is missing", probe.mode)
	}
	original := *sentence
	first := original.Segments[0]
	session.sequence++
	focused, err := p.send(yimebroker.Request{
		Version: 1, Sequence: session.sequence, SessionID: session.id, Operation: yimebroker.ApplyEvent,
		Event: engineapi.Event{Operation: engineapi.FocusSegment, CandidateID: original.ID,
			SegmentStart: first.Start, SegmentEnd: first.End},
	})
	if err != nil || focused.Result == nil {
		return 0, false, false, false, false, fmt.Errorf("%s focus first sentence word: %w", probe.mode, err)
	}
	choices := focused.Result.State.Candidates
	sequencePassed := len(choices) > 0 && len(choices) <= 9 && focused.Result.State.ActiveSegment != nil
	for _, choice := range choices {
		sequencePassed = sequencePassed && choice.Code == first.Code && len(choice.Segments) == 0
	}
	if !sequencePassed {
		return len(choices), false, false, false, false, nil
	}
	second := original.Segments[1]
	session.sequence++
	secondFocused, err := p.send(yimebroker.Request{
		Version: 1, Sequence: session.sequence, SessionID: session.id, Operation: yimebroker.ApplyEvent,
		Event: engineapi.Event{Operation: engineapi.FocusSegment, CandidateID: original.ID,
			SegmentStart: second.Start, SegmentEnd: second.End},
	})
	segmentSwitchPassed := err == nil && secondFocused.Result != nil &&
		secondFocused.Result.State.ActiveSegment != nil &&
		secondFocused.Result.State.ActiveSegment.Start == second.Start &&
		len(secondFocused.Result.State.Candidates) > 0
	if segmentSwitchPassed {
		for _, choice := range secondFocused.Result.State.Candidates {
			segmentSwitchPassed = segmentSwitchPassed && choice.Code == second.Code
		}
	}
	if !segmentSwitchPassed {
		return len(choices), true, false, false, false, err
	}
	session.sequence++
	refocusedFirst, err := p.send(yimebroker.Request{
		Version: 1, Sequence: session.sequence, SessionID: session.id, Operation: yimebroker.ApplyEvent,
		Event: engineapi.Event{Operation: engineapi.FocusSegment, CandidateID: original.ID,
			SegmentStart: first.Start, SegmentEnd: first.End},
	})
	if err != nil || refocusedFirst.Result == nil || refocusedFirst.Result.State.ActiveSegment == nil {
		return len(choices), true, true, false, false, fmt.Errorf("%s return focus to first word: %w", probe.mode, err)
	}
	replacement := choices[0]
	for _, choice := range choices[1:] {
		if choice.Text != first.Text {
			replacement = choice
			break
		}
	}
	replaced, err := p.selectCandidate(session, replacement.ID,
		fmt.Sprintf("e6c-dynamic-%s-first-word", probe.mode))
	if err != nil || replaced.Result == nil {
		return len(choices), true, true, false, false, fmt.Errorf("%s replace first sentence word: %w", probe.mode, err)
	}
	var corrected *engineapi.Candidate
	for index := range replaced.Result.State.Candidates {
		candidate := &replaced.Result.State.Candidates[index]
		if len(candidate.Segments) != len(original.Segments) || candidate.Segments[0].Text != replacement.Text {
			continue
		}
		preserved := true
		for segmentIndex := 1; segmentIndex < len(original.Segments); segmentIndex++ {
			preserved = preserved && candidate.Segments[segmentIndex].Text == original.Segments[segmentIndex].Text
		}
		if preserved {
			corrected = candidate
			break
		}
	}
	replacementPassed := replaced.Result.Commit == "" && corrected != nil
	if !replacementPassed {
		return len(choices), true, true, false, false, nil
	}
	correctedFirst := corrected.Segments[0]
	session.sequence++
	refocused, err := p.send(yimebroker.Request{
		Version: 1, Sequence: session.sequence, SessionID: session.id, Operation: yimebroker.ApplyEvent,
		Event: engineapi.Event{Operation: engineapi.FocusSegment, CandidateID: corrected.ID,
			SegmentStart: correctedFirst.Start, SegmentEnd: correctedFirst.End},
	})
	if err != nil || refocused.Result == nil || refocused.Result.State.ActiveSegment == nil {
		return len(choices), true, true, true, false, fmt.Errorf("%s refocus corrected sentence: %w", probe.mode, err)
	}
	committed, err := p.selectCandidate(session, corrected.ID,
		fmt.Sprintf("e6c-dynamic-%s-sentence-row", probe.mode))
	commitPassed := err == nil && committed.Result != nil && committed.Result.Commit == corrected.Text &&
		committed.Result.State.RawInput == ""
	return len(choices), true, true, true, commitPassed, err
}

func summarizeModeLatency(mode string, durations []time.Duration) latencyEvidence {
	ordered := append([]time.Duration(nil), durations...)
	sort.Slice(ordered, func(i, j int) bool { return ordered[i] < ordered[j] })
	middle := len(durations) / 2
	first := append([]time.Duration(nil), durations[:middle]...)
	second := append([]time.Duration(nil), durations[middle:]...)
	sort.Slice(first, func(i, j int) bool { return first[i] < first[j] })
	sort.Slice(second, func(i, j int) bool { return second[i] < second[j] })
	firstP95 := durationPercentile(first, 95)
	secondP95 := durationPercentile(second, 95)
	driftLimit := firstP95*4 + 2*time.Millisecond
	result := latencyEvidence{
		Mode: mode, Iterations: len(durations), P50NS: durationPercentile(ordered, 50).Nanoseconds(),
		P95NS: durationPercentile(ordered, 95).Nanoseconds(), P99NS: durationPercentile(ordered, 99).Nanoseconds(),
		MaxNS: ordered[len(ordered)-1].Nanoseconds(), FirstHalfP95NS: firstP95.Nanoseconds(),
		SecondHalfP95NS: secondP95.Nanoseconds(), StickyDriftLimit: driftLimit.Nanoseconds(),
	}
	result.Passed = result.P99NS < (250*time.Millisecond).Nanoseconds() &&
		result.MaxNS < time.Second.Nanoseconds() && secondP95 <= driftLimit
	return result
}

func durationPercentile(values []time.Duration, percent int) time.Duration {
	if len(values) == 0 {
		return 0
	}
	position := (len(values)*percent + 99) / 100
	if position < 1 {
		position = 1
	}
	if position > len(values) {
		position = len(values)
	}
	return values[position-1]
}

func (p *brokerProcess) selectCandidate(session *brokerSession, candidateID, mutationID string) (yimebroker.Response, error) {
	session.sequence++
	return p.send(yimebroker.Request{Version: 1, Sequence: session.sequence, SessionID: session.id,
		Operation: yimebroker.Select, CandidateID: candidateID, MutationID: mutationID})
}

func (p *brokerProcess) reset(session *brokerSession) (yimebroker.Response, error) {
	session.sequence++
	return p.send(yimebroker.Request{Version: 1, Sequence: session.sequence, SessionID: session.id, Operation: yimebroker.ResetSession})
}

func (p *brokerProcess) closeSession(session *brokerSession) error {
	session.sequence++
	_, err := p.send(yimebroker.Request{Version: 1, Sequence: session.sequence, SessionID: session.id, Operation: yimebroker.CloseSession})
	return err
}

func (p *brokerProcess) send(request yimebroker.Request) (yimebroker.Response, error) {
	data, err := yimebroker.EncodeRequest(request)
	if err != nil {
		return yimebroker.Response{}, err
	}
	if _, err := p.input.Write(append(data, '\n')); err != nil {
		return yimebroker.Response{}, err
	}
	type readResult struct {
		data []byte
		err  error
	}
	done := make(chan readResult, 1)
	go func() { data, err := p.output.ReadBytes('\n'); done <- readResult{data: data, err: err} }()
	select {
	case result := <-done:
		if result.err != nil {
			return yimebroker.Response{}, result.err
		}
		var response yimebroker.Response
		if err := json.Unmarshal(result.data, &response); err != nil {
			return response, err
		}
		if response.Error != nil {
			return response, fmt.Errorf("%s: %s", response.Error.Code, response.Error.Message)
		}
		return response, nil
	case <-time.After(requestTimeout):
		return yimebroker.Response{}, errors.New("Broker response timeout")
	}
}

func (p *brokerProcess) close() bool {
	_ = p.input.Close()
	err := p.command.Wait()
	p.waited = true
	return err == nil
}

func (p *brokerProcess) terminate() {
	_ = p.input.Close()
	if p.command.Process != nil {
		_ = p.command.Process.Kill()
	}
	if !p.waited {
		_ = p.command.Wait()
		p.waited = true
	}
}

func runControl(manifest, status string, request yimebroker.IndexControlRequest) yimebroker.IndexControlStatus {
	data, err := json.MarshalIndent(request, "", "  ")
	if err != nil {
		fail(err)
	}
	temporary := manifest + ".tmp"
	if err := os.WriteFile(temporary, append(data, '\n'), 0o644); err != nil {
		fail(err)
	}
	if err := os.Rename(temporary, manifest); err != nil {
		_ = os.Remove(manifest)
		if err := os.Rename(temporary, manifest); err != nil {
			fail(err)
		}
	}
	value, err := waitStatus(status, request.RequestID)
	if err != nil {
		fail(err)
	}
	return value
}

func waitStatus(path, requestID string) (yimebroker.IndexControlStatus, error) {
	return waitStatusWithin(path, requestID, controlTimeout)
}

func waitStatusWithin(path, requestID string, timeout time.Duration) (yimebroker.IndexControlStatus, error) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		data, err := os.ReadFile(path)
		if err == nil {
			var status yimebroker.IndexControlStatus
			if json.Unmarshal(data, &status) == nil && status.RequestID == requestID {
				return status, nil
			}
		}
		time.Sleep(10 * time.Millisecond)
	}
	return yimebroker.IndexControlStatus{}, fmt.Errorf("control status %q timed out", requestID)
}

func allManagersUseLoadMode(status yimebroker.IndexControlStatus, loadMode string) bool {
	if len(status.Managers) != 3 {
		return false
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		if status.Managers[mode].LoadMode != loadMode {
			return false
		}
	}
	return true
}

func findCandidate(candidates []engineapi.Candidate, text string) *engineapi.Candidate {
	for index := range candidates {
		if candidates[index].Text == text {
			return &candidates[index]
		}
	}
	return nil
}

func hashFile(path string) string {
	hash, err := yimebroker.IndexFileSHA256(path)
	if err != nil {
		return ""
	}
	return hash
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func fileSize(path string) int64 {
	info, err := os.Stat(path)
	if err != nil {
		return 0
	}
	return info.Size()
}

func writeJSON(path string, value any) {
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		fail(err)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		fail(err)
	}
	if err := os.WriteFile(path, append(data, '\n'), 0o644); err != nil {
		fail(err)
	}
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
