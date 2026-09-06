package layoutdesigner

import (
	"reflect"
	"testing"
)

func TestProjectIDRecordKeepsSharedIdentityAndSemanticModeSelection(t *testing.T) {
	profile := defaultProfile(t)
	ids := []string{"N26", "M16", "M17", "M18", "N27", "M03", "M03", "M03"}
	before := append([]string(nil), ids...)
	target := profile
	target.Projection = cloneProjection(profile.Projection)
	if err := target.Assign("M16", "]"); err != nil {
		t.Fatal(err)
	}
	for _, layout := range []Profile{profile, target} {
		record, err := ProjectIDRecord(ids, layout)
		if err != nil {
			t.Fatal(err)
		}
		full, err := ProjectIDs(ids, layout)
		if err != nil {
			t.Fatal(err)
		}
		variable, err := ProjectIDs([]string{ids[0], ids[1], ids[2], ids[3], ids[4], ids[5]}, layout)
		if err != nil {
			t.Fatal(err)
		}
		short, err := ProjectIDs([]string{ids[0], ids[1], ids[3], ids[4], ids[5]}, layout)
		if err != nil {
			t.Fatal(err)
		}
		if record.Full != full || record.Variable != variable || record.Shorthand != short {
			t.Fatal("direct stable-ID projection diverged from semantic selection")
		}
		decoded, err := DecodeFullCode(record.Full, layout)
		if err != nil {
			t.Fatal(err)
		}
		if decoded[0] == ids[0] || decoded[4] == ids[4] {
			t.Fatal("shared-key regression fixture no longer distinguishes physical decoding from stable identity")
		}
		legacy, err := ReencodeRecord(record.Full, layout, layout)
		if err != nil || !reflect.DeepEqual(record, legacy) {
			t.Fatal("legacy physical projection changed")
		}
	}
	if !reflect.DeepEqual(ids, before) {
		t.Fatal("projection mutated stable IDs")
	}
}

func TestProjectIDRecordRejectsBrokenTupleUnknownIDAndLayout(t *testing.T) {
	profile := defaultProfile(t)
	for _, ids := range [][]string{nil, {"N01"}, {"N01", "M01", "M02"}, {"N01", "M01", "M02", "M99"}} {
		if _, err := ProjectIDRecord(ids, profile); err == nil {
			t.Fatal("invalid ID sequence accepted")
		}
	}
	profile.Projection["M01"] = ""
	if _, err := ProjectIDRecord([]string{"N01", "M01", "M02", "M03"}, profile); err == nil {
		t.Fatal("invalid layout accepted")
	}
}
