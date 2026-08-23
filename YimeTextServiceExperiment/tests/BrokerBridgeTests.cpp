#include "SurfaceSession.h"

#include <windows.h>

#include <iostream>
#include <string>

int wmain(int argc, wchar_t** argv) {
    if (argc != 3) {
        std::cerr << "usage: YimeBrokerBridgeTests <pipe> <multi-page-code>\n";
        return 2;
    }
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
        if (index == 0 && outcome.update.rawInput != "2") {
            std::cerr << "base digit was not preserved as composition input\n";
            return 1;
        }
    }
    if (outcome.update.rawInput != code || outcome.update.candidates.empty()) {
        std::cerr << "Broker composition state mismatch\n";
        return 1;
    }
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
    std::cout << "YimeTextService E6-B2a bridge passed; selected=" << selected
              << " architecture_bits=" << (sizeof(void*) * 8) << '\n';
    return 0;
}
