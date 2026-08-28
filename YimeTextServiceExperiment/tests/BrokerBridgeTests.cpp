#include "SurfaceSession.h"

#include <windows.h>

#include <algorithm>
#include <iostream>
#include <string>
#include <vector>

namespace {

bool sendCode(yime::experiment::SurfaceSession* surface, const std::string& code,
              yime::experiment::SurfaceOutcome* outcome, std::string* error) {
    if (!surface || !outcome) return false;
    for (char character : code) {
        bool shifted = false;
        WPARAM key = 0;
        if (character >= 'a' && character <= 'z') {
            key = static_cast<WPARAM>(character - 'a' + 'A');
        } else if (character >= 'A' && character <= 'Z') {
            key = static_cast<WPARAM>(character);
            shifted = true;
        } else if (character >= '0' && character <= '9') {
            key = static_cast<WPARAM>(character);
        } else if (character == ']') {
            key = VK_OEM_6;
        } else if (character == ',') {
            key = VK_OEM_COMMA;
        } else if (character == '.') {
            key = VK_OEM_PERIOD;
        } else if (character == '/') {
            key = VK_OEM_2;
        } else {
            if (error) *error = "unsupported bridge-test code character";
            return false;
        }
        *outcome = surface->HandleVirtualKey(key, shifted);
        if (!outcome->handled || !outcome->error.empty()) {
            if (error) *error = outcome->error;
            return false;
        }
    }
    return true;
}

bool printableASCII(const wchar_t* value, std::string* converted) {
    if (!value || !converted) return false;
    converted->clear();
    for (const wchar_t* cursor = value; *cursor; ++cursor) {
        if (*cursor < 0x20 || *cursor > 0x7e) return false;
        converted->push_back(static_cast<char>(*cursor));
    }
    return true;
}

bool runLongSegmentSession(yime::experiment::SurfaceSession* surface,
                           const std::string& sentenceCode, std::string* error) {
    yime::experiment::SurfaceOutcome outcome;
    if (!sendCode(surface, sentenceCode, &outcome, error) || !outcome.update.hasSentence ||
        outcome.update.sentence.segments.size() < 3) {
        if (error && error->empty()) *error = "long-session sentence was not segmented";
        return false;
    }
    const std::string rawInput = outcome.update.rawInput;
    outcome = surface->HandleVirtualKey(VK_RIGHT, false, true, false);
    if (!outcome.handled || outcome.update.activeSegmentStart != outcome.update.sentence.segments[0].start ||
        outcome.update.activeSegmentEnd != outcome.update.sentence.segments[0].end) {
        if (error) *error = "Ctrl+Right did not focus the first sentence segment";
        return false;
    }
    outcome = surface->HandleVirtualKey(VK_RIGHT, false, true, false);
    if (!outcome.handled || outcome.update.activeSegmentStart != outcome.update.sentence.segments[1].start ||
        outcome.update.activeSegmentEnd != outcome.update.sentence.segments[1].end) {
        if (error) *error = "Ctrl+Right did not advance to the next sentence segment";
        return false;
    }
    outcome = surface->HandleVirtualKey(VK_LEFT, false, true, false);
    if (!outcome.handled || outcome.update.activeSegmentStart != outcome.update.sentence.segments[0].start ||
        outcome.update.activeSegmentEnd != outcome.update.sentence.segments[0].end) {
        if (error) *error = "Ctrl+Left did not return to the previous sentence segment";
        return false;
    }
    constexpr int cycles = 25;
    for (int cycle = 0; cycle < cycles; ++cycle) {
        const size_t segmentCount = outcome.update.sentence.segments.size();
        const size_t targets[] = {0, segmentCount / 2, segmentCount - 1};
        for (const size_t targetIndex : targets) {
            const auto before = outcome.update.sentence.segments;
            const auto target = before[targetIndex];
            outcome = surface->FocusSentenceSegment(target.start, target.end);
            if (!outcome.handled || !outcome.update.commit.empty() ||
                outcome.update.rawInput != rawInput || !outcome.update.hasSentence ||
                outcome.update.activeSegmentStart != target.start ||
                outcome.update.activeSegmentEnd != target.end ||
                outcome.update.sentence.segments.size() != segmentCount) {
                if (error) *error = "segment focus lost the authoritative Broker snapshot";
                return false;
            }
            const size_t candidateLimit = std::min<size_t>(9, outcome.update.candidates.size());
            size_t replacementIndex = candidateLimit;
            for (size_t index = 0; index < candidateLimit; ++index) {
                if (outcome.update.candidates[index].text != before[targetIndex].text) {
                    replacementIndex = index;
                    break;
                }
            }
            if (replacementIndex == candidateLimit) {
                if (error) *error = "focused segment has no alternate Shift-selectable candidate";
                return false;
            }
            const std::string replacement = outcome.update.candidates[replacementIndex].text;
            outcome = surface->HandleVirtualKey(static_cast<WPARAM>('1' + replacementIndex), true);
            if (!outcome.handled || !outcome.update.commit.empty() ||
                outcome.update.rawInput != rawInput || !outcome.update.hasSentence ||
                outcome.update.sentence.segments.size() != segmentCount) {
                if (error) *error = "segment replacement committed or lost the sentence";
                return false;
            }
            for (size_t index = 0; index < segmentCount; ++index) {
                const std::string expected = index == targetIndex ? replacement : before[index].text;
                if (outcome.update.sentence.segments[index].text != expected) {
                    if (error) *error = "segment replacement changed an unrelated sentence segment";
                    return false;
                }
            }
        }
    }
    std::string expectedCommit;
    for (const auto& segment : outcome.update.sentence.segments) expectedCommit += segment.text;
    outcome = surface->CommitSentence();
    if (!outcome.handled || outcome.update.commit != expectedCommit ||
        !outcome.update.rawInput.empty() || outcome.update.hasSentence) {
        if (error) *error = "explicit long-session sentence commit failed";
        return false;
    }
    return true;
}

bool runCorrectedSentenceCommit(yime::experiment::SurfaceSession* surface,
                                const std::string& sentenceCode, WPARAM commitKey,
                                std::string* error) {
    yime::experiment::SurfaceOutcome outcome;
    if (!sendCode(surface, sentenceCode, &outcome, error) || !outcome.update.hasSentence ||
        outcome.update.sentence.segments.empty()) {
        if (error && error->empty()) *error = "corrected sentence was not segmented";
        return false;
    }
    const auto first = outcome.update.sentence.segments.front();
    outcome = surface->FocusSentenceSegment(first.start, first.end);
    if (!outcome.handled) {
        if (error) *error = "corrected sentence first segment was not focusable";
        return false;
    }
    size_t replacementIndex = outcome.update.candidates.size();
    for (size_t index = 0; index < outcome.update.candidates.size(); ++index) {
        if (outcome.update.candidates[index].text == u8"这是") {
            replacementIndex = index;
            break;
        }
    }
    if (replacementIndex >= 9 || replacementIndex >= outcome.update.candidates.size()) {
        if (error) *error = "corrected sentence replacement was not Shift-selectable";
        return false;
    }
    outcome = surface->HandleVirtualKey(static_cast<WPARAM>('1' + replacementIndex), true);
    if (!outcome.handled || !outcome.update.commit.empty() ||
        outcome.update.sentence.text != u8"这是一套子系统") {
        if (error) *error = "local sentence correction committed early or produced the wrong sentence";
        return false;
    }
    if (outcome.update.sentence.segments.size() < 2 || outcome.update.candidates.empty() ||
        outcome.update.activeSegmentStart != outcome.update.sentence.segments[1].start ||
        outcome.update.activeSegmentEnd != outcome.update.sentence.segments[1].end ||
        outcome.update.candidates.front().text != outcome.update.sentence.segments[1].text) {
        if (error) *error = "local sentence correction did not synchronize the next segment and candidate";
        return false;
    }
    const size_t candidateCountAfterCorrection = outcome.update.candidates.size();
    const std::string firstCandidateAfterCorrection = candidateCountAfterCorrection == 0
                                                          ? std::string{}
                                                          : outcome.update.candidates.front().text;
    if (commitKey == 0) {
        outcome = surface->CommitSentence();
    } else {
        const size_t maximumSelections = outcome.update.sentence.segments.size() + 1;
        for (size_t selection = 0; selection < maximumSelections && outcome.update.commit.empty(); ++selection) {
            outcome = surface->HandleVirtualKey(commitKey, false);
            if (!outcome.handled || (!outcome.update.commit.empty() &&
                outcome.update.commit != u8"这是一套子系统") ||
                (outcome.update.commit.empty() && outcome.update.sentence.text != u8"这是一套子系统")) {
                break;
            }
        }
    }
    if (!outcome.handled || outcome.update.commit != u8"这是一套子系统" ||
        !outcome.update.rawInput.empty() || outcome.update.hasSentence) {
        if (error) {
            *error = "corrected sentence commit returned raw code or stale state: key=" +
                     std::to_string(commitKey) + " handled=" +
                     std::to_string(outcome.handled ? 1 : 0) + " error=" + outcome.error +
                     " commit=" + outcome.update.commit +
                     " raw=" + outcome.update.rawInput + " candidates_after_correction=" +
                     std::to_string(candidateCountAfterCorrection) + " first_candidate=" +
                     firstCandidateAfterCorrection;
        }
        return false;
    }
    return true;
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    if (argc < 3) {
        std::cerr << "usage: YimeBrokerBridgeTests <pipe> <multi-page-code> [candidate-sorting-code] [whole-word-code longer-word-suffix] [--long-session-code=<code>] [--corrected-sentence-code=<code>]\n";
		return 2;
	}
    std::vector<std::string> scenarioArguments;
    std::string longSessionCode;
    std::string correctedSentenceCode;
    constexpr char longSessionPrefix[] = "--long-session-code=";
    constexpr char correctedSentencePrefix[] = "--corrected-sentence-code=";
    for (int index = 3; index < argc; ++index) {
        std::string argument;
        if (!printableASCII(argv[index], &argument)) return 2;
        if (argument.rfind(longSessionPrefix, 0) == 0) {
            if (!longSessionCode.empty()) return 2;
            longSessionCode = argument.substr(sizeof(longSessionPrefix) - 1);
        } else if (argument.rfind(correctedSentencePrefix, 0) == 0) {
            if (!correctedSentenceCode.empty()) return 2;
            correctedSentenceCode = argument.substr(sizeof(correctedSentencePrefix) - 1);
        } else {
            scenarioArguments.push_back(std::move(argument));
        }
    }
    if (scenarioArguments.size() > 2 || longSessionCode.empty() && argc > 5) return 2;
    yime::experiment::SurfaceSession surface;
    std::string error;
    if (!surface.Connect(argv[1], 5000, &error)) {
        std::cerr << error << '\n';
        return 1;
    }
    const std::string code = "2jru";
    yime::experiment::SurfaceOutcome outcome;
    for (size_t index = 0; index < code.size(); ++index) {
        const char character = code[index];
        outcome = surface.HandleVirtualKey(static_cast<WPARAM>(character >= 'a' ? character - 'a' + 'A' : character), false);
        if (!outcome.handled || !outcome.error.empty()) {
            std::cerr << "composition key failed: " << outcome.error << '\n';
            return 1;
        }
        if (index == 0) {
            if (outcome.update.rawInput != "2") {
                std::cerr << "base digit was not preserved as composition input\n";
                return 1;
            }
            if (outcome.update.candidates.empty()) {
                std::cerr << "first composition key did not publish candidates\n";
                return 1;
            }
        }
    }
    if (outcome.update.rawInput != code || outcome.update.candidates.empty()) {
        std::cerr << "Broker composition state mismatch\n";
        return 1;
    }
    const std::string selectedCode = outcome.update.candidates.front().code;
    outcome = surface.HandleVirtualKey('Z', false);
    if (!outcome.handled || outcome.update.rawInput != code + "z" || !outcome.update.candidates.empty()) {
        std::cerr << "invalid-code state did not remain editable\n";
        return 1;
    }
    outcome = surface.HandleVirtualKey(VK_BACK, false);
    if (!outcome.handled || outcome.update.rawInput != code || outcome.update.candidates.empty()) {
        std::cerr << "Backspace did not restore the Broker candidate state\n";
        return 1;
    }
    outcome = surface.HandleVirtualKey(VK_BACK, false);
    if (!outcome.handled || outcome.update.rawInput != "2jr") {
        std::cerr << "second Backspace did not update Broker raw input\n";
        return 1;
    }
    outcome = surface.HandleVirtualKey('U', false);
    if (!outcome.handled || outcome.update.rawInput != code || outcome.update.candidates.empty()) {
        std::cerr << "deleted code resurrected after continued input\n";
        return 1;
    }
    const std::string selected = outcome.update.candidates.front().text;
    outcome = surface.HandleVirtualKey('1', true);
    if (!outcome.handled || outcome.update.commit != selected || !outcome.update.rawInput.empty()) {
        std::cerr << "Shift+1 stable candidate selection failed: " << outcome.error << '\n';
        return 1;
    }
    std::string pagingCode;
    for (const wchar_t* cursor = argv[2]; *cursor; ++cursor) {
        if (*cursor < 0x20 || *cursor > 0x7e) {
            std::cerr << "multi-page code must be printable ASCII\n";
            return 2;
        }
        pagingCode.push_back(static_cast<char>(*cursor));
    }
    for (char character : pagingCode) {
        const bool shifted = character >= 'A' && character <= 'Z';
        const WPARAM key = character >= 'a' && character <= 'z'
                                ? static_cast<WPARAM>(character - 'a' + 'A')
                                : static_cast<WPARAM>(character);
        outcome = surface.HandleVirtualKey(key, shifted);
        if (!outcome.handled) {
            std::cerr << "multi-page composition key was not handled\n";
            return 1;
        }
    }
    if (outcome.update.rawInput != pagingCode || outcome.update.candidates.size() < 2 ||
        !outcome.update.hasNextPage) {
        std::cerr << "declared multi-page code did not expose a next page\n";
        return 1;
    }
    const std::string firstPageFirstId = outcome.update.candidates.front().id;
    const std::string secondCandidate = outcome.update.candidates[1].text;
    outcome = surface.HandleVirtualKey(VK_DOWN, false);
    if (!outcome.handled || outcome.update.selectedCandidateIndex != 1) {
        std::cerr << "Down did not advance the candidate highlight\n";
        return 1;
    }
    outcome = surface.HandleVirtualKey(VK_UP, false);
    if (!outcome.handled || outcome.update.selectedCandidateIndex != 0) {
        std::cerr << "Up did not restore the candidate highlight\n";
        return 1;
    }
    outcome = surface.HandleVirtualKey(VK_NEXT, false);
    if (!outcome.handled || outcome.update.pageNumber != 1 || !outcome.update.hasPreviousPage ||
        outcome.update.candidates.empty() || outcome.update.candidates.front().id == firstPageFirstId) {
        std::cerr << "PageDown did not advance the Broker candidate page\n";
        return 1;
    }
    outcome = surface.HandleVirtualKey(VK_LEFT, false);
    if (!outcome.handled || outcome.update.pageNumber != 0 || outcome.update.hasPreviousPage ||
        outcome.update.candidates.empty() ||
        outcome.update.candidates.front().id != firstPageFirstId) {
        std::cerr << "Left did not restore the previous Broker candidate page\n";
        return 1;
    }
    outcome = surface.HandleVirtualKey(VK_DOWN, false);
    outcome = surface.HandleVirtualKey(VK_RETURN, false);
    if (!outcome.handled || outcome.update.commit != secondCandidate || !outcome.update.rawInput.empty()) {
        std::cerr << "Enter did not commit the arrow-highlighted candidate\n";
        return 1;
    }
    if (!sendCode(&surface, pagingCode, &outcome, &error) || outcome.update.candidates.empty() ||
        outcome.update.candidates.front().text != secondCandidate) {
        std::cerr << "selected candidate did not become the learned first choice: " << error << '\n';
        return 1;
    }
    outcome = surface.HandleVirtualKey(VK_DELETE, false, true, false);
    if (!outcome.handled || !outcome.update.commit.empty() || outcome.update.rawInput != pagingCode ||
        outcome.update.candidates.empty() || outcome.update.candidates.front().id != firstPageFirstId) {
        std::cerr << "Ctrl+Delete did not forget the learned candidate in place: " << outcome.error << '\n';
        return 1;
    }
    for (size_t index = 0; index < pagingCode.size(); ++index) {
        outcome = surface.HandleVirtualKey(VK_BACK, false);
        if (!outcome.handled) {
            std::cerr << "post-forget composition was no longer editable\n";
            return 1;
        }
    }
    if (!outcome.update.rawInput.empty()) {
        std::cerr << "post-forget composition did not clear through Backspace\n";
        return 1;
    }
    if (!sendCode(&surface, code, &outcome, &error)) {
        std::cerr << "Escape cancellation composition failed: " << error << '\n';
        return 1;
    }
    outcome = surface.HandleVirtualKey(VK_ESCAPE, false);
    if (!outcome.handled || !outcome.update.rawInput.empty() || !outcome.update.commit.empty() ||
        outcome.update.hasSentence) {
        std::cerr << "Escape did not cancel the Broker composition\n";
        return 1;
    }
    for (const WPARAM defaultSelectionKey : {static_cast<WPARAM>(VK_SPACE), static_cast<WPARAM>(VK_RETURN)}) {
        for (char character : code) {
            outcome = surface.HandleVirtualKey(
                static_cast<WPARAM>(character >= 'a' ? character - 'a' + 'A' : character), false);
            if (!outcome.handled || !outcome.error.empty()) {
                std::cerr << "default-selection composition failed: " << outcome.error << '\n';
                return 1;
            }
        }
        if (outcome.update.candidates.empty()) {
            std::cerr << "default-selection candidate list is empty\n";
            return 1;
        }
        const std::string expected = outcome.update.candidates.front().text;
        outcome = surface.HandleVirtualKey(defaultSelectionKey, false);
        if (!outcome.handled || outcome.update.commit != expected || !outcome.update.rawInput.empty()) {
            std::cerr << "Enter/Space first-candidate selection failed: " << outcome.error << '\n';
            return 1;
        }
    }
    if (scenarioArguments.size() == 1) {
        const std::string& sentenceCode = scenarioArguments[0];
        if (!sendCode(&surface, sentenceCode, &outcome, &error) || !outcome.update.hasSentence ||
            outcome.update.sentence.text != "候选排序") {
            std::cerr << "candidate-sorting sentence row mismatch: " << error << '\n';
            return 1;
        }
        outcome = surface.CommitSentence();
        if (!outcome.handled || outcome.update.commit != "候选排序" ||
            !outcome.update.rawInput.empty()) {
            std::cerr << "explicit sentence commit did not commit the candidate-sorting sentence: "
                      << outcome.error << '\n';
            return 1;
        }
    }
    if (scenarioArguments.size() == 2) {
        const std::string& wholeWordCode = scenarioArguments[0];
        const std::string& longerWordSuffix = scenarioArguments[1];
		if (!sendCode(&surface, wholeWordCode, &outcome, &error) || !outcome.update.hasSentence ||
			outcome.update.sentence.text != "本地" || !outcome.update.sentence.segments.empty()) {
			std::cerr << "system word did not enter the sentence row as a whole: " << error << '\n';
			return 1;
		}
        const int wholeWordEnd = static_cast<int>(outcome.update.sentence.code.size());
        outcome = surface.FocusSentenceSegment(0, wholeWordEnd);
        if (!outcome.handled || outcome.update.sentence.text != "本地" ||
            !outcome.update.sentence.segments.empty() || outcome.update.activeSegmentStart != 0 ||
            outcome.update.activeSegmentEnd != wholeWordEnd) {
            std::cerr << "single-click whole-word focus expanded or rejected the virtual segment: "
                      << outcome.error << '\n';
            return 1;
        }
        outcome = surface.ExpandSentenceSegment(0, wholeWordEnd);
        std::string expandedText;
        for (const auto& segment : outcome.update.sentence.segments) expandedText += segment.text;
        if (!outcome.handled || outcome.update.sentence.segments.size() < 2 || expandedText != "本地") {
            std::cerr << "explicit whole-word expansion did not produce registered child segments: "
                      << outcome.error << '\n';
            return 1;
        }
		if (!sendCode(&surface, longerWordSuffix, &outcome, &error) || !outcome.update.hasSentence ||
			outcome.update.sentence.text != "本地人" || !outcome.update.sentence.segments.empty()) {
			std::cerr << "longer system word did not replace the shorter sentence row: " << error << '\n';
			return 1;
		}
		outcome = surface.HandleVirtualKey(VK_RETURN, false);
		if (!outcome.handled || outcome.update.commit != "本地人" || !outcome.update.rawInput.empty()) {
			std::cerr << "whole system-word sentence commit failed: " << outcome.error << '\n';
			return 1;
		}
	}
    if (!longSessionCode.empty() && !runLongSegmentSession(&surface, longSessionCode, &error)) {
        std::cerr << "long segment session failed: " << error << '\n';
        return 1;
    }
    if (!correctedSentenceCode.empty()) {
        for (const WPARAM commitKey : {static_cast<WPARAM>(VK_SPACE),
                                      static_cast<WPARAM>(VK_RETURN), static_cast<WPARAM>(0)}) {
            if (!runCorrectedSentenceCommit(&surface, correctedSentenceCode, commitKey, &error)) {
                std::cerr << "corrected sentence commit failed: " << error << '\n';
                return 1;
            }
        }
    }
    outcome = surface.HandleVirtualKey(VK_F12, false);
    if (outcome.handled) {
        std::cerr << "pass-through key was consumed\n";
        return 1;
    }
    surface.DisconnectForRecovery();
    outcome = surface.HandleVirtualKey('2', false);
    if (!outcome.handled || outcome.update.rawInput != "2") {
        std::cerr << "recoverable surface did not reconnect after host termination: " << outcome.error << '\n';
        return 1;
    }
    surface.Close();
    outcome = surface.HandleVirtualKey('2', false);
    if (outcome.handled || outcome.error.empty()) {
        std::cerr << "permanently closed surface consumed a key\n";
        return 1;
    }
    std::cout << "YimeTextService E6-B2a bridge passed; selected=" << selectedCode
              << " architecture_bits=" << (sizeof(void*) * 8) << '\n';
    return 0;
}
