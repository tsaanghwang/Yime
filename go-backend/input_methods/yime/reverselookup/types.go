package reverselookup

type Mode string

const (
	ModeVariable  Mode = "variable"
	ModeFull      Mode = "full"
	ModeShorthand Mode = "shorthand"
)

type CodeRecord struct {
	Full       string
	Variable   string
	Shorthand  string
}

type UserPhraseEntry struct {
	Phrase string
	Pinyin string
}

type Result struct {
	Phrase         string
	Source         string
	NumericPinyin  string
	StandardPinyin string
	ActiveCode     string
	FullCode       string
	VariableCode   string
	ShorthandCode  string
}

func SchemaIDFromMode(mode Mode) string {
	switch mode {
	case ModeFull:
		return "yime_full"
	case ModeShorthand:
		return "yime_shorthand"
	default:
		return "yime_variable"
	}
}

func CodeColumnFromMode(mode Mode) string {
	switch mode {
	case ModeFull:
		return "full"
	case ModeShorthand:
		return "shorthand"
	default:
		return "variable"
	}
}

func codeValue(record CodeRecord, column string) string {
	switch column {
	case "full":
		return record.Full
	case "shorthand":
		return record.Shorthand
	default:
		return record.Variable
	}
}
