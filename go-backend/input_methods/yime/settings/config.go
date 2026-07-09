package settings

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

const (
	SchemaVariable  = "yime_variable"
	SchemaFull      = "yime_full"
	SchemaShorthand = "yime_shorthand"
)

// Snapshot is the current settings view shown in the settings tool.
type Snapshot struct {
	SchemaID          string
	PageSize          int
	ReverseLookupMode string
	CandidateLayout   string
	DeployerPath      string
}

// State is persisted in yime_settings_state.json.
type State struct {
	ReverseLookupDisplayMode string `json:"reverse_lookup_display_mode"`
	CandidateLayout          string `json:"candidate_layout"`
}

// SchemaOption describes one selectable schema.
type SchemaOption struct {
	ID      string
	Label   string
	Enabled bool
}

// ComboOption is a labeled value for combo boxes.
type ComboOption struct {
	Label string
	Value string
}

func AvailableSchemaOptions(sharedDir string) []SchemaOption {
	shorthandEnabled := false
	if sharedDir != "" {
		_, err := os.Stat(filepath.Join(sharedDir, "yime_shorthand.schema.yaml"))
		shorthandEnabled = err == nil
	}
	return []SchemaOption{
		{ID: SchemaVariable, Label: "变长", Enabled: true},
		{ID: SchemaFull, Label: "等长", Enabled: true},
		{ID: SchemaShorthand, Label: "省键", Enabled: shorthandEnabled},
	}
}

func ReverseLookupOptions() []ComboOption {
	return []ComboOption{
		{Label: "隐藏编码", Value: "hidden"},
		{Label: "标准拼音", Value: "standard_pinyin"},
		{Label: "音元拼音", Value: "yime_pinyin"},
		{Label: "键位序列", Value: "key_sequence"},
	}
}

func CandidateLayoutOptions() []ComboOption {
	return []ComboOption{
		{Label: "竖排", Value: "vertical"},
		{Label: "横排", Value: "horizontal"},
	}
}

func LoadSnapshot(userDir, sharedDir string) Snapshot {
	state := ReadState(userDir)
	return Snapshot{
		SchemaID:          ReadConfiguredSchema(userDir),
		PageSize:          ReadConfiguredPageSize(userDir),
		ReverseLookupMode: state.ReverseLookupDisplayMode,
		CandidateLayout:   state.CandidateLayout,
		DeployerPath:      FindDeployerPath(sharedDir),
	}
}

func SummaryText(snapshot Snapshot) string {
	schemaLabel := "变长"
	switch snapshot.SchemaID {
	case SchemaFull:
		schemaLabel = "等长"
	case SchemaShorthand:
		schemaLabel = "省键"
	}
	reverseLabel := "键位序列"
	for _, option := range ReverseLookupOptions() {
		if option.Value == snapshot.ReverseLookupMode {
			reverseLabel = option.Label
			break
		}
	}
	layoutLabel := "竖排"
	for _, option := range CandidateLayoutOptions() {
		if option.Value == snapshot.CandidateLayout {
			layoutLabel = option.Label
			break
		}
	}
	return fmt.Sprintf("当前设置：方案 %s，候选项数 %d，反查显示 %s，候选排列 %s", schemaLabel, snapshot.PageSize, reverseLabel, layoutLabel)
}

func ReadState(userDir string) State {
	defaults := State{
		ReverseLookupDisplayMode: "key_sequence",
		CandidateLayout:          "vertical",
	}
	if userDir == "" {
		return defaults
	}
	data, err := os.ReadFile(filepath.Join(userDir, "yime_settings_state.json"))
	if err != nil {
		return defaults
	}
	var state State
	if err := json.Unmarshal(data, &state); err != nil {
		return defaults
	}
	state.ReverseLookupDisplayMode = normalizeReverseLookupMode(state.ReverseLookupDisplayMode)
	state.CandidateLayout = normalizeCandidateLayout(state.CandidateLayout)
	return state
}

func WriteState(userDir string, state State) error {
	if userDir == "" {
		return fmt.Errorf("用户目录为空")
	}
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		return err
	}
	payload, err := json.MarshalIndent(State{
		ReverseLookupDisplayMode: normalizeReverseLookupMode(state.ReverseLookupDisplayMode),
		CandidateLayout:          normalizeCandidateLayout(state.CandidateLayout),
	}, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(userDir, "yime_settings_state.json"), append(payload, '\n'), 0o644)
}

func Apply(userDir, sharedDir, schemaID string, pageSize int, reverseLookupMode, candidateLayout string, runBuild bool) error {
	if userDir == "" || sharedDir == "" {
		return fmt.Errorf("用户目录或共享数据目录为空")
	}
	schemaID = normalizeSchemaID(schemaID)
	if schemaID == SchemaShorthand {
		if _, err := os.Stat(filepath.Join(sharedDir, "yime_shorthand.schema.yaml")); err != nil {
			return fmt.Errorf("当前共享数据目录未包含省键方案文件")
		}
	}
	pageSize = normalizePageSize(pageSize)
	reverseLookupMode = normalizeReverseLookupMode(reverseLookupMode)
	candidateLayout = normalizeCandidateLayout(candidateLayout)

	if err := os.MkdirAll(userDir, 0o755); err != nil {
		return err
	}
	defaultCustomPath := filepath.Join(userDir, "default.custom.yaml")
	userYamlPath := filepath.Join(userDir, "user.yaml")
	defaultCustomContent, _ := readFileText(defaultCustomPath)
	userYamlContent, _ := readFileText(userYamlPath)
	if err := writeUTF8NoBOM(defaultCustomPath, updateDefaultCustomSchemaAndPageSize(defaultCustomContent, schemaID, pageSize)); err != nil {
		return err
	}
	if err := writeUTF8NoBOM(userYamlPath, updateUserYamlSelectedSchema(userYamlContent, schemaID)); err != nil {
		return err
	}
	if err := WriteState(userDir, State{ReverseLookupDisplayMode: reverseLookupMode, CandidateLayout: candidateLayout}); err != nil {
		return err
	}
	if runBuild {
		return InvokeRimeBuild(userDir, sharedDir)
	}
	return nil
}

func ReadConfiguredSchema(userDir string) string {
	if userDir == "" {
		return SchemaVariable
	}
	if schema := readPreviouslySelectedSchema(filepath.Join(userDir, "user.yaml")); schema != "" {
		return schema
	}
	if schema := readSchemaListSelection(filepath.Join(userDir, "default.custom.yaml")); schema != "" {
		return schema
	}
	return SchemaVariable
}

func ReadConfiguredPageSize(userDir string) int {
	if userDir == "" {
		return 5
	}
	content, _ := readFileText(filepath.Join(userDir, "default.custom.yaml"))
	for _, line := range splitLines(content) {
		if value, ok := parseMenuPageSizeValue(strings.TrimSpace(line)); ok {
			return normalizePageSize(atoiDefault(value, 5))
		}
	}
	return 5
}

func normalizeSchemaID(schemaID string) string {
	switch strings.TrimSpace(schemaID) {
	case SchemaFull:
		return SchemaFull
	case SchemaShorthand:
		return SchemaShorthand
	default:
		return SchemaVariable
	}
}

func normalizeReverseLookupMode(mode string) string {
	switch strings.TrimSpace(mode) {
	case "hidden", "standard_pinyin", "yime_pinyin", "key_sequence":
		return strings.TrimSpace(mode)
	default:
		return "key_sequence"
	}
}

func normalizeCandidateLayout(layout string) string {
	switch strings.TrimSpace(layout) {
	case "horizontal":
		return "horizontal"
	default:
		return "vertical"
	}
}

func normalizePageSize(size int) int {
	if size < 5 {
		return 5
	}
	if size > 9 {
		return 9
	}
	return size
}

func readPreviouslySelectedSchema(path string) string {
	content, err := readFileText(path)
	if err != nil {
		return ""
	}
	for _, line := range splitLines(content) {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "previously_selected_schema:") {
			return normalizeSchemaID(strings.TrimSpace(strings.TrimPrefix(trimmed, "previously_selected_schema:")))
		}
	}
	return ""
}

func readSchemaListSelection(path string) string {
	content, err := readFileText(path)
	if err != nil {
		return ""
	}
	for _, line := range splitLines(content) {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "- schema:") {
			return normalizeSchemaID(strings.TrimSpace(strings.TrimPrefix(trimmed, "- schema:")))
		}
	}
	return ""
}

func updateDefaultCustomSchemaAndPageSize(content, schemaID string, pageSize int) string {
	schemaID = normalizeSchemaID(schemaID)
	pageSize = normalizePageSize(pageSize)
	schemaLine := "    - schema: " + schemaID
	pageLine := `  "menu/page_size": ` + strconv.Itoa(pageSize)
	if strings.TrimSpace(content) == "" {
		return "patch:\n  schema_list:\n" + schemaLine + "\n" + pageLine + "\n"
	}
	lines := splitLines(content)
	header := []string{}
	for _, line := range lines {
		if strings.TrimSpace(line) == "patch:" {
			break
		}
		header = append(header, line)
	}
	for len(header) > 0 && strings.TrimSpace(header[len(header)-1]) == "" {
		header = header[:len(header)-1]
	}
	out := append([]string{}, header...)
	if len(header) > 0 {
		out = append(out, "")
	}
	out = append(out, "patch:", "  schema_list:", schemaLine, pageLine)
	return strings.Join(out, "\n") + "\n"
}

func updateUserYamlSelectedSchema(content, schemaID string) string {
	schemaID = normalizeSchemaID(schemaID)
	if strings.TrimSpace(content) == "" {
		return "var:\n  previously_selected_schema: " + schemaID + "\n"
	}
	lines := splitLines(content)
	foundVar := false
	updated := false
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "var:" {
			foundVar = true
		}
		if strings.HasPrefix(trimmed, "previously_selected_schema:") {
			indent := line[:len(line)-len(strings.TrimLeft(line, " \t"))]
			lines[i] = indent + "previously_selected_schema: " + schemaID
			updated = true
		}
	}
	if !updated {
		if !foundVar {
			if len(lines) > 0 && strings.TrimSpace(lines[len(lines)-1]) != "" {
				lines = append(lines, "")
			}
			lines = append(lines, "var:")
		}
		insertAt := len(lines)
		for i, line := range lines {
			if strings.TrimSpace(line) == "var:" {
				insertAt = i + 1
				break
			}
		}
		lines = append(lines[:insertAt], append([]string{"  previously_selected_schema: " + schemaID}, lines[insertAt:]...)...)
	}
	return strings.Join(lines, "\n") + "\n"
}

func parseMenuPageSizeValue(trimmed string) (string, bool) {
	if idx := strings.Index(trimmed, "#"); idx >= 0 {
		trimmed = strings.TrimSpace(trimmed[:idx])
	}
	switch {
	case strings.HasPrefix(trimmed, "menu/page_size:"):
		return strings.TrimSpace(strings.TrimPrefix(trimmed, "menu/page_size:")), true
	case strings.HasPrefix(trimmed, `"menu/page_size":`):
		return strings.TrimSpace(strings.TrimPrefix(trimmed, `"menu/page_size":`)), true
	default:
		return "", false
	}
}

func readFileText(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

func writeUTF8NoBOM(path string, content string) error {
	return os.WriteFile(path, []byte(content), 0o644)
}

func splitLines(content string) []string {
	return strings.Split(strings.ReplaceAll(content, "\r\n", "\n"), "\n")
}

func atoiDefault(value string, fallback int) int {
	n, err := strconv.Atoi(strings.TrimSpace(value))
	if err != nil {
		return fallback
	}
	return n
}
