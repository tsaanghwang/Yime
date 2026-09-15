#pragma once

#include <windows.h>

#include <string>

#include "BrokerClient.h"
#include "ExperimentSettings.h"

namespace yime::experiment {

// Direct output transforms are intentionally limited to English pass-through
// state. In Chinese state every printable Yime alphabet key, including bare
// punctuation and digits, remains composition data.
bool TryDirectOutputKey(WPARAM virtualKey, bool shiftDown,
                        const ExperimentSettings& settings, std::string* commit) noexcept;

// Resolves a printable punctuation key for the explicit local punctuation
// palette. Unlike TryDirectOutputKey, ASCII half-width punctuation is returned
// as an explicit commit instead of being left to the host.
bool TranslatePunctuationKey(WPARAM virtualKey, bool shiftDown,
                             bool asciiPunctuation, bool fullShape,
                             std::string* commit) noexcept;

std::string TraditionalizeUtf8(const std::string& text) noexcept;
void ApplyTraditionalization(BrokerUpdate* update) noexcept;

}  // namespace yime::experiment
