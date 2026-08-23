#include "ExperimentSettings.h"

#include <windows.h>

#include <filesystem>
#include <fstream>

#include <nlohmann/json.hpp>

namespace yime::experiment {
namespace {

bool validMode(const std::string& mode) noexcept {
    return mode == "full" || mode == "variable" || mode == "shorthand";
}

bool validAnnotation(const std::string& annotation) noexcept {
    return annotation == "hidden" || annotation == "yinyuan" ||
           annotation == "key_sequence" || annotation == "standard_pinyin";
}

int pointsForPreset(const std::string& preset) noexcept {
    if (preset == "small") return 10;
    if (preset == "large") return 16;
    return 12;
}

}  // namespace

std::wstring ResolveExperimentSettingsPath() {
    const DWORD needed = GetEnvironmentVariableW(L"LOCALAPPDATA", nullptr, 0);
    if (needed <= 1) return {};
    std::wstring local(static_cast<size_t>(needed), L'\0');
    const DWORD written = GetEnvironmentVariableW(L"LOCALAPPDATA", local.data(), needed);
    if (written == 0 || written >= needed) return {};
    local.resize(written);
    return (std::filesystem::path(local) / L"YimeCore Experimental Trial" /
            L"yimecore_experimental_toolbar_state.json").wstring();
}

ExperimentSettings LoadExperimentSettings(const std::wstring& path) noexcept {
    ExperimentSettings settings;
    if (path.empty()) return settings;
    try {
        std::ifstream input(std::filesystem::path(path), std::ios::binary);
        if (!input) return settings;
        nlohmann::json document;
        input >> document;
        const auto mode = document.value("experiment_mode", settings.mode);
        const auto preset = document.value("candidate_font_preset", settings.candidateFontPreset);
        const auto annotation = document.value("candidate_annotation", settings.candidateAnnotation);
        if (validMode(mode)) settings.mode = mode;
        if (preset == "small" || preset == "medium" || preset == "large") {
            settings.candidateFontPreset = preset;
        }
        if (validAnnotation(annotation)) settings.candidateAnnotation = annotation;
        settings.candidateFontPoints = pointsForPreset(settings.candidateFontPreset);
        settings.revision = document.value("revision", std::int64_t{0});
    } catch (...) {
        return ExperimentSettings{};
    }
    return settings;
}

const ExperimentSettings& ExperimentSettingsCache::Get() noexcept {
    WIN32_FILE_ATTRIBUTE_DATA attributes{};
    const bool present = !path_.empty() &&
        GetFileAttributesExW(path_.c_str(), GetFileExInfoStandard, &attributes) != FALSE;
    std::uint64_t signature = 0;
    if (present) {
        signature = (static_cast<std::uint64_t>(attributes.ftLastWriteTime.dwHighDateTime) << 32) |
                    attributes.ftLastWriteTime.dwLowDateTime;
        signature ^= (static_cast<std::uint64_t>(attributes.nFileSizeHigh) << 32) |
                     attributes.nFileSizeLow;
    }
    if (!initialized_ || present != filePresent_ || signature != signature_) {
        settings_ = LoadExperimentSettings(path_);
        signature_ = signature;
        filePresent_ = present;
        initialized_ = true;
    }
    return settings_;
}

}  // namespace yime::experiment
