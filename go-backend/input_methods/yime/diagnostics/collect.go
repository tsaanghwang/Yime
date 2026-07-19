package diagnostics

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

// Context carries runtime paths for diagnostics collection.
type Context struct {
	UserDir   string
	SharedDir string
	HelpDir   string
	LogDir    string
}

// ReportOptions controls structured report generation.
type ReportOptions struct {
	IncludeEnvironmentSummary bool
	IncludeRecommendedActions bool
	IncludeRawLogExcerpt      bool
	Anonymize                 bool
	KeepDriveLetter           bool
	AnonymizeMode             string
	RawLogExcerptMode         string
	ContextWindowRadius       int
}

// DefaultIssueReadyOptions returns the built-in issue-ready preset.
func DefaultIssueReadyOptions() ReportOptions {
	return ReportOptions{
		IncludeEnvironmentSummary: true,
		IncludeRecommendedActions: true,
		IncludeRawLogExcerpt:      true,
		Anonymize:                 true,
		KeepDriveLetter:           true,
		AnonymizeMode:             "full",
		RawLogExcerptMode:         "error-window",
		ContextWindowRadius:       20,
	}
}

func BuildStatusReport(ctx Context) string {
	sections := []string{
		"== Findings ==",
	}
	sections = append(sections, diagnosticFindings(ctx)...)
	sections = append(sections, "", "== Paths ==")
	sections = append(sections,
		pathCheck("User data", ctx.UserDir),
		pathCheck("Shared data", ctx.SharedDir),
		pathCheck("Help docs", ctx.HelpDir),
		pathCheck("Log dir", ctx.LogDir),
		"",
		"== Installed runtime ==",
		installFlavorCheck(installRootFromShared(ctx.SharedDir)),
		fileCheck("server.exe", serverBinaryPath(ctx.SharedDir)),
		fileCheck("tool-hub.exe", filepath.Join(installRootFromShared(ctx.SharedDir), "tool-hub.exe")),
		fileCheck("yime-layout-designer.exe", filepath.Join(installRootFromShared(ctx.SharedDir), "yime-layout-designer.exe")),
		fileCheck("lexicon-manager.exe", filepath.Join(installRootFromShared(ctx.SharedDir), "lexicon-manager.exe")),
		fileCheck("reverse-lookup.exe", filepath.Join(installRootFromShared(ctx.SharedDir), "reverse-lookup.exe")),
		fileCheck("settings-tool.exe", filepath.Join(installRootFromShared(ctx.SharedDir), "settings-tool.exe")),
		fileCheck("diagnostics-tool.exe", filepath.Join(installRootFromShared(ctx.SharedDir), "diagnostics-tool.exe")),
		deployerCheck(ctx.SharedDir),
		"",
		"== Running processes ==",
		processSummary("PIMELauncher"),
		processSummary("server"),
		"",
		"== Settings chain ==",
	)
	sections = append(sections, settingsChainSummary(ctx.UserDir)...)
	sections = append(sections, "", "== User Rime files ==")
	sections = append(sections, rimeUserFilesSummary(ctx.UserDir)...)
	sections = append(sections, "", "== Logs ==")
	sections = append(sections, logSummary(ctx.LogDir))
	sections = append(sections, "", "== Log interpretation ==")
	sections = append(sections, logInterpretation(ctx.LogDir)...)
	return strings.Join(sections, "\n")
}

func BuildStructuredReport(ctx Context, opts ReportOptions) string {
	lines := []string{
		"# Yime Diagnostics Report",
		"",
		"Generated: " + time.Now().Format("2006-01-02 15:04:05"),
		protectText("UserDir: "+ctx.UserDir, opts),
		protectText("SharedDir: "+ctx.SharedDir, opts),
		protectText("HelpDir: "+ctx.HelpDir, opts),
		protectText("LogDir: "+ctx.LogDir, opts),
		"Anonymized: " + boolLabel(opts.Anonymize),
		"Anonymize mode: " + opts.AnonymizeMode,
		"Keep drive letter: " + boolLabel(opts.KeepDriveLetter),
		"",
	}
	if opts.IncludeEnvironmentSummary {
		lines = append(lines, markdownSection(environmentSummaryLines(ctx))...)
		lines = append(lines, "")
	}
	for _, line := range markdownSection(strings.Split(BuildStatusReport(ctx), "\n")) {
		lines = append(lines, protectText(line, opts))
	}
	if opts.IncludeRecommendedActions {
		lines = append(lines, "")
		lines = append(lines, markdownSection(recommendedActionLines(ctx.LogDir))...)
	}
	if opts.IncludeRawLogExcerpt {
		lines = append(lines, "")
		lines = append(lines, markdownSection(rawLogExcerptLines(ctx.LogDir, opts.RawLogExcerptMode, opts.ContextWindowRadius))...)
	}
	return strings.Join(lines, "\n")
}

func environmentSummaryLines(ctx Context) []string {
	return []string{
		"== Environment summary ==",
		statusLine("Generated at", "time", time.Now().Format("2006-01-02 15:04:05")),
		statusLine("Install root", "path", installRootFromShared(ctx.SharedDir)),
		statusLine("server.exe", "path", serverBinaryPath(ctx.SharedDir)),
		statusLine("PIMELauncher", processStateLabel("PIMELauncher"), "snapshot"),
		statusLine("server", processStateLabel("server"), "snapshot"),
		statusLine("UserDir", "path", ctx.UserDir),
		statusLine("SharedDir", "path", ctx.SharedDir),
		statusLine("LogDir", "path", ctx.LogDir),
	}
}

func diagnosticFindings(ctx Context) []string {
	findings := []string{}
	userExists := pathExists(ctx.UserDir)
	sharedExists := pathExists(ctx.SharedDir)
	if !sharedExists {
		findings = append(findings, "判定：当前共享运行时路径不存在，像是这套 Yime/PIME 运行时还没装好，或者现在打开的不是预期安装。")
	}
	if userExists && !fileExists(filepath.Join(ctx.UserDir, "default.custom.yaml")) {
		findings = append(findings, "判定：用户目录存在，但 default.custom.yaml 缺失。")
	}
	if len(findings) == 0 {
		findings = append(findings, "判定：未发现明显阻断项；请结合日志解释和设置链路继续排查。")
	}
	return findings
}

func settingsChainSummary(userDir string) []string {
	if !pathExists(userDir) {
		return []string{statusLine("Settings chain", "missing", "user dir unavailable")}
	}
	state := readStandaloneSnapshot(userDir)
	schema := readConfiguredSchema(userDir)
	pageSize := readConfiguredPageSize(userDir)
	return []string{
		statusLine("default.custom.yaml", filePresenceLabel(filepath.Join(userDir, "default.custom.yaml")), filepath.Join(userDir, "default.custom.yaml")),
		statusLine("Configured schema", valuePresence(schema), emptyFallback(schema, "no schema_list selection found")),
		statusLine("Configured page size", valuePresence(pageSize), emptyFallback(pageSize, "no menu/page_size key found")),
		statusLine("user.yaml", filePresenceLabel(filepath.Join(userDir, "user.yaml")), filepath.Join(userDir, "user.yaml")),
		statusLine("yime_settings_state.json", filePresenceLabel(filepath.Join(userDir, "yime_settings_state.json")), filepath.Join(userDir, "yime_settings_state.json")),
		statusLine("Standalone state parse", state.ParseStatus, state.ParseDetail),
		statusLine("reverse_lookup_display_mode", valuePresence(state.ReverseLookupMode), emptyFallback(state.ReverseLookupMode, "value missing")),
		statusLine("candidate_layout", valuePresence(state.CandidateLayout), emptyFallback(state.CandidateLayout, "value missing")),
		statusLine("Activation sync hint", "observe", "onActivate only restores standalone reverse-lookup and layout preferences; schema and page-size changes still need an explicit rebuild/deploy path."),
	}
}

func rimeUserFilesSummary(userDir string) []string {
	if !pathExists(userDir) {
		return []string{
			statusLine("default.custom.yaml", "missing", "user dir unavailable"),
			statusLine("user.yaml", "missing", "user dir unavailable"),
			statusLine("yime_settings_state.json", "missing", "user dir unavailable"),
			statusLine("yime_user_phrases.txt", "missing", "user dir unavailable"),
		}
	}
	return []string{
		fileCheck("default.custom.yaml", filepath.Join(userDir, "default.custom.yaml")),
		fileCheck("user.yaml", filepath.Join(userDir, "user.yaml")),
		fileCheck("yime_settings_state.json", filepath.Join(userDir, "yime_settings_state.json")),
		fileCheck("yime_user_phrases.txt", filepath.Join(userDir, "yime_user_phrases.txt")),
	}
}

func logSummary(logDir string) string {
	if !pathExists(logDir) {
		return statusLine("Logs", "missing", "directory missing")
	}
	entries, err := os.ReadDir(logDir)
	if err != nil || len(entries) == 0 {
		return statusLine("Logs", "empty", "directory exists but no files were found")
	}
	files := make([]os.DirEntry, 0, len(entries))
	for _, entry := range entries {
		if !entry.IsDir() {
			files = append(files, entry)
		}
	}
	if len(files) == 0 {
		return statusLine("Logs", "empty", "directory exists but no files were found")
	}
	sort.Slice(files, func(i, j int) bool {
		infoI, _ := files[i].Info()
		infoJ, _ := files[j].Info()
		if infoI == nil || infoJ == nil {
			return i > j
		}
		return infoI.ModTime().After(infoJ.ModTime())
	})
	latestPath := filepath.Join(logDir, files[0].Name())
	info, _ := files[0].Info()
	tail := readLastLine(latestPath)
	return statusLine("Logs", "ok", fmt.Sprintf("%d files | latest %s @ %s | tail %s", len(files), files[0].Name(), modTime(info), tail))
}

func logInterpretation(logDir string) []string {
	logPath := primaryLogFile(logDir)
	lines := readRecentLogLines(logPath)
	if len(lines) == 0 {
		return []string{statusLine("Primary log", "missing", "could not read recent log lines")}
	}
	requestCount := countMatches(lines, `(?i)request|onKey|filterKey`)
	commandCount := countMatches(lines, `(?i)onCommand|commandId`)
	errorCount := countMatches(lines, `(?i)error|failed|timeout|panic|错误|失败`)
	summary := []string{
		statusLine("Recent requests", "count", fmt.Sprintf("%d", requestCount)),
		statusLine("Recent commands", "count", fmt.Sprintf("%d", commandCount)),
		statusLine("Recent error-like lines", "count", fmt.Sprintf("%d", errorCount)),
	}
	if requestCount == 0 {
		summary = append(summary, statusLine("Interpretation", "warning", "the backend log does not show recent requests; the host may not be reaching this backend at all"))
	}
	if errorCount > 0 {
		summary = append(summary, statusLine("Interpretation", "warning", "recent error-like lines exist; check the last error-like line first"))
	}
	if requestCount > 0 && errorCount == 0 {
		summary = append(summary, statusLine("Interpretation", "ok", "the log shows live backend traffic without obvious recent errors"))
	}
	return summary
}

func recommendedActionLines(logDir string) []string {
	lines := logInterpretation(logDir)
	actions := []string{}
	for _, line := range lines {
		if strings.Contains(strings.ToLower(line), "warning") {
			actions = append(actions, "Recommended action: "+line)
		}
	}
	if len(actions) == 0 {
		return []string{
			"== Recommended actions ==",
			statusLine("Recommended action", "observe", "no action mapping was produced from the current log snapshot"),
		}
	}
	out := []string{"== Recommended actions =="}
	out = append(out, actions...)
	return out
}

func rawLogExcerptLines(logDir, mode string, radius int) []string {
	logPath := primaryLogFile(logDir)
	lines := readRecentLogLines(logPath)
	if len(lines) == 0 {
		return []string{
			"== Raw log excerpt ==",
			statusLine("Primary log", "missing", "could not locate a log file to excerpt"),
		}
	}
	excerpt := []string{}
	switch mode {
	case "errors", "error-window":
		for _, line := range lines {
			if strings.Contains(strings.ToLower(line), "error") || strings.Contains(line, "失败") {
				excerpt = append(excerpt, line)
			}
		}
		if len(excerpt) > 40 {
			excerpt = excerpt[len(excerpt)-40:]
		}
	default:
		if len(lines) > 40 {
			excerpt = lines[len(lines)-40:]
		} else {
			excerpt = lines
		}
	}
	if len(excerpt) == 0 {
		excerpt = []string{"no recent lines matched the current filter"}
	}
	out := []string{"== Raw log excerpt ==", statusLine("Primary log", "ok", logPath)}
	out = append(out, excerpt...)
	_ = radius
	return out
}

type standaloneSnapshot struct {
	ReverseLookupMode string
	CandidateLayout   string
	ParseStatus       string
	ParseDetail       string
}

func readStandaloneSnapshot(userDir string) standaloneSnapshot {
	snapshot := standaloneSnapshot{
		ParseStatus: "missing",
		ParseDetail: "yime_settings_state.json not found",
	}
	path := filepath.Join(userDir, "yime_settings_state.json")
	if !fileExists(path) {
		return snapshot
	}
	data, err := os.ReadFile(path)
	if err != nil {
		snapshot.ParseStatus = "invalid"
		snapshot.ParseDetail = err.Error()
		return snapshot
	}
	content := string(data)
	if strings.Contains(content, `"reverse_lookup_display_mode"`) {
		snapshot.ReverseLookupMode = extractJSONString(content, "reverse_lookup_display_mode")
	}
	if strings.Contains(content, `"candidate_layout"`) {
		snapshot.CandidateLayout = extractJSONString(content, "candidate_layout")
	}
	snapshot.ParseStatus = "ok"
	snapshot.ParseDetail = "JSON parsed"
	return snapshot
}

func readConfiguredSchema(userDir string) string {
	content, _ := os.ReadFile(filepath.Join(userDir, "user.yaml"))
	for _, line := range strings.Split(string(content), "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "previously_selected_schema:") {
			return strings.TrimSpace(strings.TrimPrefix(trimmed, "previously_selected_schema:"))
		}
	}
	content2, _ := os.ReadFile(filepath.Join(userDir, "default.custom.yaml"))
	for _, line := range strings.Split(string(content2), "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "- schema:") {
			return strings.TrimSpace(strings.TrimPrefix(trimmed, "- schema:"))
		}
	}
	return ""
}

func readConfiguredPageSize(userDir string) string {
	content, _ := os.ReadFile(filepath.Join(userDir, "default.custom.yaml"))
	for _, line := range strings.Split(string(content), "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, `"menu/page_size":`) {
			return strings.TrimSpace(strings.TrimPrefix(trimmed, `"menu/page_size":`))
		}
		if strings.HasPrefix(trimmed, "menu/page_size:") {
			return strings.TrimSpace(strings.TrimPrefix(trimmed, "menu/page_size:"))
		}
	}
	return ""
}

func installRootFromShared(sharedDir string) string {
	if sharedDir == "" {
		return ""
	}
	return filepath.Clean(filepath.Join(sharedDir, "..", "..", ".."))
}

func serverBinaryPath(sharedDir string) string {
	return filepath.Join(installRootFromShared(sharedDir), "server.exe")
}

func deployerCheck(sharedDir string) string {
	for _, candidate := range []string{
		filepath.Join(installRootFromShared(sharedDir), "rime_deployer.exe"),
		filepath.Join(filepath.Dir(sharedDir), "rime_deployer.exe"),
		`C:\dev\librime\build\bin\Release\rime_deployer.exe`,
	} {
		if fileExists(candidate) {
			return fileCheck("rime_deployer.exe", candidate)
		}
	}
	return statusLine("rime_deployer.exe", "missing", "no deployer candidate found")
}

func installFlavorCheck(installRoot string) string {
	if installRoot == "" {
		return statusLine("Install root", "missing", "could not derive install root from shared data path")
	}
	if strings.HasPrefix(strings.ToLower(installRoot), strings.ToLower(`C:\Program Files (x86)\YIME`)) {
		return statusLine("Install root", "installed", installRoot)
	}
	return statusLine("Install root", "nonstandard", installRoot)
}

func pathCheck(label, path string) string {
	if strings.TrimSpace(path) == "" {
		return statusLine(label, "missing", "path value is empty")
	}
	if !pathExists(path) {
		return statusLine(label, "missing", path)
	}
	return statusLine(label, "ok", path)
}

func fileCheck(label, path string) string {
	if strings.TrimSpace(path) == "" {
		return statusLine(label, "missing", "path value is empty")
	}
	info, err := os.Stat(path)
	if err != nil {
		return statusLine(label, "missing", path)
	}
	return statusLine(label, "ok", path+" | modified "+info.ModTime().Format("2006-01-02 15:04:05"))
}

func processSummary(name string) string {
	if processRunning(name) {
		return statusLine(name, "running", "process snapshot")
	}
	return statusLine(name, "stopped", "no running process found")
}

func processStateLabel(name string) string {
	if processRunning(name) {
		return "running"
	}
	return "stopped"
}

func primaryLogFile(logDir string) string {
	if !pathExists(logDir) {
		return ""
	}
	candidate := filepath.Join(logDir, "go_backend.log")
	if fileExists(candidate) {
		return candidate
	}
	entries, err := os.ReadDir(logDir)
	if err != nil {
		return ""
	}
	var latestPath string
	var latestTime time.Time
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(strings.ToLower(entry.Name()), ".log") {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			continue
		}
		if info.ModTime().After(latestTime) {
			latestTime = info.ModTime()
			latestPath = filepath.Join(logDir, entry.Name())
		}
	}
	return latestPath
}

func readRecentLogLines(path string) []string {
	if path == "" {
		return nil
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	lines := strings.Split(strings.ReplaceAll(string(data), "\r\n", "\n"), "\n")
	if len(lines) > 200 {
		lines = lines[len(lines)-200:]
	}
	return lines
}

func readLastLine(path string) string {
	lines := readRecentLogLines(path)
	if len(lines) == 0 {
		return "<last line unavailable>"
	}
	return lines[len(lines)-1]
}

func countMatches(lines []string, pattern string) int {
	re := regexp.MustCompile(pattern)
	count := 0
	for _, line := range lines {
		if re.MatchString(line) {
			count++
		}
	}
	return count
}

func statusLine(label, state, detail string) string {
	return label + ": " + state + " | " + detail
}

func markdownSection(lines []string) []string {
	out := []string{}
	for _, line := range lines {
		if strings.TrimSpace(line) == "" {
			out = append(out, "")
			continue
		}
		if strings.HasPrefix(line, "== ") && strings.HasSuffix(line, " ==") {
			out = append(out, "## "+strings.TrimSuffix(strings.TrimPrefix(line, "== "), " =="))
			continue
		}
		out = append(out, "- "+line)
	}
	return out
}

func protectText(line string, opts ReportOptions) string {
	if !opts.Anonymize {
		return line
	}
	replaced := line
	if !opts.KeepDriveLetter {
		replaced = regexp.MustCompile(`[A-Za-z]:\\`).ReplaceAllString(replaced, "<drive>\\")
	}
	if opts.AnonymizeMode == "names-only" {
		return replaced
	}
	replaced = regexp.MustCompile(`(?i)[A-Za-z]:\\Users\\[^\\]+`).ReplaceAllString(replaced, "<user>")
	return replaced
}

func extractJSONString(content, key string) string {
	re := regexp.MustCompile(`"` + regexp.QuoteMeta(key) + `"\s*:\s*"([^"]*)"`)
	match := re.FindStringSubmatch(content)
	if len(match) < 2 {
		return ""
	}
	return match[1]
}

func pathExists(path string) bool { return fileExists(path) }

func fileExists(path string) bool {
	if strings.TrimSpace(path) == "" {
		return false
	}
	_, err := os.Stat(path)
	return err == nil
}

func filePresenceLabel(path string) string {
	if fileExists(path) {
		return "present"
	}
	return "missing"
}

func valuePresence(value string) string {
	if strings.TrimSpace(value) == "" {
		return "unknown"
	}
	return "seen"
}

func emptyFallback(value, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	return value
}

func boolLabel(value bool) string {
	if value {
		return "yes"
	}
	return "no"
}

func modTime(info os.FileInfo) string {
	if info == nil {
		return ""
	}
	return info.ModTime().Format("2006-01-02 15:04:05")
}
