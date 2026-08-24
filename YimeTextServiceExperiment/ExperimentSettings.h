#pragma once

#include <cstdint>
#include <string>
#include <utility>

namespace yime::experiment {

struct ExperimentSettings {
    bool asciiMode = false;
    std::string mode = "variable";
    std::string candidateFontPreset = "medium";
    std::string candidateAnnotation = "key_sequence";
    int candidateFontPoints = 12;
    std::int64_t revision = 0;
};

enum class ExperimentSettingsCommand {
    ToggleAscii,
    Chinese,
    English,
    ModeVariable,
    ModeFull,
    ModeShorthand,
    FontSmall,
    FontMedium,
    FontLarge,
    AnnotationKeySequence,
    AnnotationYinyuan,
    AnnotationStandardPinyin,
    AnnotationHidden,
};

std::wstring ResolveExperimentSettingsPath();
ExperimentSettings LoadExperimentSettings(const std::wstring& path = ResolveExperimentSettingsPath()) noexcept;
bool ApplyExperimentSettingsCommand(
    ExperimentSettingsCommand command,
    const std::wstring& path = ResolveExperimentSettingsPath(),
    ExperimentSettings* updated = nullptr) noexcept;

// Candidate updates can happen on every keystroke. This cache checks the
// small state file metadata and only reparses JSON after an atomic replacement.
class ExperimentSettingsCache final {
public:
    explicit ExperimentSettingsCache(std::wstring path = ResolveExperimentSettingsPath())
        : path_(std::move(path)) {}

    const ExperimentSettings& Get() noexcept;

private:
    std::wstring path_;
    ExperimentSettings settings_;
    std::uint64_t signature_ = 0;
    bool filePresent_ = false;
    bool initialized_ = false;
};

}  // namespace yime::experiment
