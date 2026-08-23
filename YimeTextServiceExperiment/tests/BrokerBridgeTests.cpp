#include "SurfaceSession.h"

#include <windows.h>

#include <iostream>
#include <string>

int wmain(int argc, wchar_t** argv) {
    if (argc != 2) {
        std::cerr << "usage: YimeBrokerBridgeTests <pipe>\n";
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
    const std::string selected = outcome.update.candidates.front().text;
    outcome = surface.HandleVirtualKey('1', true);
    if (!outcome.handled || outcome.update.commit != selected || !outcome.update.rawInput.empty()) {
        std::cerr << "Shift+1 stable candidate selection failed: " << outcome.error << '\n';
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
