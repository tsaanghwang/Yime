package trainer

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestTrainerPreferencesDirectoryStaysOutsideRimeUserDirectory(t *testing.T) {
	rimeDir := filepath.Join(t.TempDir(), "PIME", "Rime")
	got := PreferencesDirectoryFromRimeUserDir(rimeDir)
	want := filepath.Join(filepath.Dir(rimeDir), PreferencesDirName)
	if got != want {
		t.Fatalf("preferences directory=%q want %q", got, want)
	}
	if strings.HasPrefix(got+string(os.PathSeparator), rimeDir+string(os.PathSeparator)) {
		t.Fatalf("trainer preferences must not be stored under Rime: %q", got)
	}
}

func TestTrainerPreferencesDefaultToMediumSoftGray(t *testing.T) {
	got, err := LoadPreferences(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if got.Version != PreferencesVersion || got.FontSize != FontSizeMedium || got.Background != BackgroundSoftGray {
		t.Fatalf("unexpected defaults: %#v", got)
	}
}

func TestTrainerPreferencesRoundTripAndNormalizeUnknownValues(t *testing.T) {
	dir := t.TempDir()
	want := Preferences{FontSize: FontSizeXLarge, Background: BackgroundWarmBeige, LastMode: "full", LastSectionID: "encoding-practice", ReviewFilter: ReviewWrong}
	if err := SavePreferences(dir, want); err != nil {
		t.Fatal(err)
	}
	got, err := LoadPreferences(dir)
	if err != nil {
		t.Fatal(err)
	}
	if got.Version != PreferencesVersion || got.FontSize != want.FontSize || got.Background != want.Background || got.LastMode != want.LastMode || got.LastSectionID != want.LastSectionID || got.ReviewFilter != want.ReviewFilter {
		t.Fatalf("round trip=%#v want=%#v", got, want)
	}
	updated := Preferences{FontSize: FontSizeLarge, Background: BackgroundGrayBlue}
	if err := SavePreferences(dir, updated); err != nil {
		t.Fatal(err)
	}
	got, err = LoadPreferences(dir)
	if err != nil {
		t.Fatal(err)
	}
	if got.FontSize != updated.FontSize || got.Background != updated.Background {
		t.Fatalf("updated preferences=%#v want=%#v", got, updated)
	}

	path := filepath.Join(dir, PreferencesFileName)
	if err := os.WriteFile(path, []byte(`{"version":99,"font_size":"tiny","background":"white"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	got, err = LoadPreferences(dir)
	if err != nil {
		t.Fatal(err)
	}
	if got != DefaultPreferences() {
		t.Fatalf("unknown values were not normalized: %#v", got)
	}
}
