package userlexicon

import "fmt"

// ImportConflict describes one import conflict row.
type ImportConflict struct {
	Phrase         string
	CurrentPinyin  string
	CurrentWeight  string
	ImportedPinyin string
	ImportedWeight string
}

// ImportNewEntry describes one newly imported entry.
type ImportNewEntry struct {
	Phrase         string
	ImportedPinyin string
	ImportedWeight string
}

// ImportPreview summarizes an import operation.
type ImportPreview struct {
	NewCount     int
	ReplaceCount int
	SameCount    int
	Samples      []string
	Conflicts    []ImportConflict
	NewEntries   []ImportNewEntry
}

// BuildImportPreview compares current and imported entries.
func BuildImportPreview(currentEntries, importEntries []Entry) ImportPreview {
	currentByPhrase := make(map[string]Entry, len(currentEntries))
	for _, entry := range currentEntries {
		currentByPhrase[entry.Phrase] = entry
	}

	preview := ImportPreview{
		Conflicts:  make([]ImportConflict, 0),
		NewEntries: make([]ImportNewEntry, 0),
		Samples:    make([]string, 0),
	}
	for _, entry := range importEntries {
		current, ok := currentByPhrase[entry.Phrase]
		if !ok {
			preview.NewCount++
			preview.NewEntries = append(preview.NewEntries, ImportNewEntry{
				Phrase:         entry.Phrase,
				ImportedPinyin: entry.Pinyin,
				ImportedWeight: entry.Weight,
			})
			continue
		}
		if current.Pinyin == entry.Pinyin && current.Weight == entry.Weight {
			preview.SameCount++
			continue
		}
		preview.ReplaceCount++
		preview.Conflicts = append(preview.Conflicts, ImportConflict{
			Phrase:         entry.Phrase,
			CurrentPinyin:  current.Pinyin,
			CurrentWeight:  current.Weight,
			ImportedPinyin: entry.Pinyin,
			ImportedWeight: entry.Weight,
		})
		if len(preview.Samples) < 5 {
			preview.Samples = append(preview.Samples, fmt.Sprintf("%s: %s/%s -> %s/%s",
				entry.Phrase, current.Pinyin, current.Weight, entry.Pinyin, entry.Weight))
		}
	}
	return preview
}

// FilterMergeImportEntries returns import entries to merge with selected conflicts.
func FilterMergeImportEntries(currentEntries, importEntries []Entry, selectedConflicts map[string]bool) []Entry {
	currentByPhrase := make(map[string]Entry, len(currentEntries))
	for _, entry := range currentEntries {
		currentByPhrase[entry.Phrase] = entry
	}
	filtered := make([]Entry, 0, len(importEntries))
	for _, entry := range importEntries {
		current, ok := currentByPhrase[entry.Phrase]
		if !ok {
			filtered = append(filtered, entry.Clone())
			continue
		}
		if current.Pinyin == entry.Pinyin && current.Weight == entry.Weight {
			continue
		}
		if selectedConflicts[entry.Phrase] {
			filtered = append(filtered, entry.Clone())
		}
	}
	return filtered
}
