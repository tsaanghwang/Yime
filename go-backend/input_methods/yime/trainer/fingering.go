package trainer

import "strings"

// FingerAssignment describes the touch-typing hand, finger and home key for
// one physical US-layout key. Shifted Yime keys retain the same finger as
// their unshifted physical key.
type FingerAssignment struct {
	Hand    string
	Finger  string
	HomeKey string
}

func fingerForKey(key string) FingerAssignment {
	base := physicalBaseKey(key)
	assignments := []struct {
		keys, hand, finger, home string
	}{
		{"`1qaz", "左手", "小指", "A"},
		{"2wsx", "左手", "无名指", "S"},
		{"3edc", "左手", "中指", "D"},
		{"45rtfgvb", "左手", "食指", "F"},
		{"67yuhjnm", "右手", "食指", "J"},
		{"8ik,", "右手", "中指", "K"},
		{"9ol.", "右手", "无名指", "L"},
		{"0-=p[]\\;'/", "右手", "小指", ";"},
	}
	for _, assignment := range assignments {
		if strings.Contains(assignment.keys, base) {
			return FingerAssignment{Hand: assignment.hand, Finger: assignment.finger, HomeKey: assignment.home}
		}
	}
	return FingerAssignment{Hand: "未指定", Finger: "未指定", HomeKey: ""}
}

func physicalBaseKey(key string) string {
	base := strings.TrimSpace(key)
	shifted := map[string]string{
		"!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
		"_": "-", "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/",
	}
	if unshifted := shifted[base]; unshifted != "" {
		base = unshifted
	}
	return strings.ToLower(base)
}

func FingeringForKey(key string) FingerAssignment {
	return fingerForKey(key)
}
