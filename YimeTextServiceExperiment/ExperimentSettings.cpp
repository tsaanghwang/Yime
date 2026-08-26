#include "ExperimentSettings.h"

#include <windows.h>

#include <filesystem>
#include <fstream>
#include <cstdio>
#include <iomanip>
#include <stdexcept>

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

class StateFileLock final {
public:
    explicit StateFileLock(std::wstring path) : path_(std::move(path)) {}
    ~StateFileLock() {
        if (owned_) DeleteFileW(path_.c_str());
    }
    bool Acquire() noexcept {
        const ULONGLONG deadline = GetTickCount64() + 3000;
        while (GetTickCount64() <= deadline) {
            HANDLE file = CreateFileW(path_.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
                                      FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_TEMPORARY, nullptr);
            if (file != INVALID_HANDLE_VALUE) {
                SYSTEMTIME now{};
                GetSystemTime(&now);
                char token[64]{};
                const int count = std::snprintf(token, sizeof(token), "%04u-%02u-%02uT%02u:%02u:%02uZ",
                                                now.wYear, now.wMonth, now.wDay, now.wHour,
                                                now.wMinute, now.wSecond);
                DWORD written = 0;
                if (count > 0) WriteFile(file, token, static_cast<DWORD>(count), &written, nullptr);
                CloseHandle(file);
                owned_ = true;
                return true;
            }
            WIN32_FILE_ATTRIBUTE_DATA attributes{};
            if (GetFileAttributesExW(path_.c_str(), GetFileExInfoStandard, &attributes)) {
                FILETIME nowFile{};
                GetSystemTimeAsFileTime(&nowFile);
                ULARGE_INTEGER now{}, modified{};
                now.LowPart = nowFile.dwLowDateTime;
                now.HighPart = nowFile.dwHighDateTime;
                modified.LowPart = attributes.ftLastWriteTime.dwLowDateTime;
                modified.HighPart = attributes.ftLastWriteTime.dwHighDateTime;
                constexpr ULONGLONG thirtySeconds = 30ULL * 10'000'000ULL;
                if (now.QuadPart > modified.QuadPart + thirtySeconds) {
                    DeleteFileW(path_.c_str());
                    continue;
                }
            }
            Sleep(10);
        }
        return false;
    }

private:
    std::wstring path_;
    bool owned_ = false;
};

std::int64_t revisionNow(std::int64_t previous) noexcept {
    FILETIME fileTime{};
    GetSystemTimeAsFileTime(&fileTime);
    ULARGE_INTEGER ticks{};
    ticks.LowPart = fileTime.dwLowDateTime;
    ticks.HighPart = fileTime.dwHighDateTime;
    constexpr ULONGLONG windowsToUnixTicks = 11644473600ULL * 10'000'000ULL;
    const auto nanos = static_cast<std::int64_t>((ticks.QuadPart - windowsToUnixTicks) * 100ULL);
    return nanos > previous ? nanos : previous + 1;
}

std::string utcTimestamp() {
    SYSTEMTIME now{};
    GetSystemTime(&now);
    char value[40]{};
    std::snprintf(value, sizeof(value), "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ",
                  now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute,
                  now.wSecond, now.wMilliseconds);
    return value;
}

bool applyCommand(ExperimentSettingsCommand command, nlohmann::json& document) {
    switch (command) {
    case ExperimentSettingsCommand::ToggleAscii:
        document["ascii_mode"] = !document.value("ascii_mode", false);
        return true;
    case ExperimentSettingsCommand::Chinese: document["ascii_mode"] = false; return true;
    case ExperimentSettingsCommand::English: document["ascii_mode"] = true; return true;
    case ExperimentSettingsCommand::ModeVariable: document["experiment_mode"] = "variable"; return true;
    case ExperimentSettingsCommand::ModeFull: document["experiment_mode"] = "full"; return true;
    case ExperimentSettingsCommand::ModeShorthand: document["experiment_mode"] = "shorthand"; return true;
    case ExperimentSettingsCommand::FontSmall: document["candidate_font_preset"] = "small"; return true;
    case ExperimentSettingsCommand::FontMedium: document["candidate_font_preset"] = "medium"; return true;
    case ExperimentSettingsCommand::FontLarge: document["candidate_font_preset"] = "large"; return true;
    case ExperimentSettingsCommand::AnnotationKeySequence:
        document["candidate_annotation"] = "key_sequence"; return true;
    case ExperimentSettingsCommand::AnnotationYinyuan:
        document["candidate_annotation"] = "yinyuan"; return true;
    case ExperimentSettingsCommand::AnnotationStandardPinyin:
        document["candidate_annotation"] = "standard_pinyin"; return true;
    case ExperimentSettingsCommand::AnnotationHidden:
        document["candidate_annotation"] = "hidden"; return true;
    case ExperimentSettingsCommand::PunctuationChinese:
        document["ascii_punctuation"] = false; return true;
    case ExperimentSettingsCommand::PunctuationEnglish:
        document["ascii_punctuation"] = true; return true;
    case ExperimentSettingsCommand::ShapeHalf:
        document["full_shape"] = false; return true;
    case ExperimentSettingsCommand::ShapeFull:
        document["full_shape"] = true; return true;
    case ExperimentSettingsCommand::ScriptSimplified:
        document["traditionalization"] = false; return true;
    case ExperimentSettingsCommand::ScriptTraditional:
        document["traditionalization"] = true; return true;
    }
    return false;
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
        settings.asciiMode = document.value("ascii_mode", false);
        settings.fullShape = document.value("full_shape", false);
        settings.asciiPunctuation = document.value("ascii_punctuation", false);
        settings.traditionalization = document.value("traditionalization", false);
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

bool ApplyExperimentSettingsCommand(ExperimentSettingsCommand command, const std::wstring& path,
                                    ExperimentSettings* updated) noexcept {
    if (path.empty()) return false;
    try {
        const std::filesystem::path statePath(path);
        std::filesystem::create_directories(statePath.parent_path());
        StateFileLock lock(path + L".lock");
        if (!lock.Acquire()) return false;

        nlohmann::json document = nlohmann::json::object();
        {
            std::ifstream input(statePath, std::ios::binary);
            if (input) input >> document;
        }
        if (!document.is_object()) return false;
        const auto previous = document.value("revision", std::int64_t{0});
        if (!applyCommand(command, document)) return false;
        document["version"] = 1;
        document["revision"] = revisionNow(previous);
        document["updated_at"] = utcTimestamp();
        document["source"] = "yimecore-language-bar";
        if (!document.contains("experiment_mode")) document["experiment_mode"] = "variable";
        if (!document.contains("candidate_font_preset")) document["candidate_font_preset"] = "medium";
        if (!document.contains("candidate_annotation")) document["candidate_annotation"] = "key_sequence";

        wchar_t tempPath[MAX_PATH]{};
        if (!GetTempFileNameW(statePath.parent_path().c_str(), L"ylb", 0, tempPath)) return false;
        const std::filesystem::path temporary(tempPath);
        bool replaced = false;
        try {
            {
                std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
                if (!output) throw std::runtime_error("open temporary state");
                output << std::setw(2) << document << '\n';
                output.flush();
                if (!output) throw std::runtime_error("write temporary state");
            }
            replaced = MoveFileExW(temporary.c_str(), statePath.c_str(),
                                   MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != FALSE;
        } catch (...) {
            DeleteFileW(temporary.c_str());
            throw;
        }
        if (!replaced) {
            DeleteFileW(temporary.c_str());
            return false;
        }
        if (updated) *updated = LoadExperimentSettings(path);
        return true;
    } catch (...) {
        return false;
    }
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
