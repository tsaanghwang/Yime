#ifndef IME_CANDIDATE_WINDOW_CLICK_POLICY_H
#define IME_CANDIDATE_WINDOW_CLICK_POLICY_H

namespace Ime {

enum class CandidateWindowClickKind {
    None,
    CompositionSegment,
    Candidate,
};

struct CandidateWindowClickTarget {
    CandidateWindowClickKind kind;
    int index;
};

inline CandidateWindowClickTarget candidateWindowClickTarget(
    int compositionSegment, int candidate) {
    if(compositionSegment >= 0)
        return {CandidateWindowClickKind::CompositionSegment, compositionSegment};
    if(candidate >= 0)
        return {CandidateWindowClickKind::Candidate, candidate};
    return {CandidateWindowClickKind::None, -1};
}

inline int candidateWindowForgetTarget(
    int compositionSegment, int candidate) {
    if(compositionSegment >= 0)
        return -1;
    return candidate;
}

} // namespace Ime

#endif
