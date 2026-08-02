package trainer

type ContentReadiness struct {
	YinyuanTotal        int
	FingeringCovered    int
	AudioDeclared       int
	AudioAvailable      int
	EncodedSyllables    int
	CandidateSimulation bool
}

func (resolver *Resolver) ContentReadiness() ContentReadiness {
	if resolver == nil {
		return ContentReadiness{}
	}
	result := ContentReadiness{YinyuanTotal: len(resolver.catalog.Entries), CandidateSimulation: true}
	for _, entry := range resolver.catalog.Entries {
		assignment := fingerForKey(resolver.layout.Projection[entry.ID])
		if assignment.Hand != "未指定" && assignment.Finger != "未指定" {
			result.FingeringCovered++
		}
		if entry.Audio != "" {
			result.AudioDeclared++
		}
		if resolver.catalog.AudioPath(entry) != "" {
			result.AudioAvailable++
		}
	}
	for _, row := range resolver.decomposition {
		if row.Status == "ok" {
			result.EncodedSyllables++
		}
	}
	return result
}
