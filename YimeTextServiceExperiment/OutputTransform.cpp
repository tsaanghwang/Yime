#include "OutputTransform.h"

#include <array>
#include <string_view>

namespace yime::experiment {
namespace {

bool TranslatePrintableKey(WPARAM virtualKey, bool shiftDown, char* character) noexcept {
    if (!character) return false;
    if (virtualKey >= 'A' && virtualKey <= 'Z') {
        *character = static_cast<char>(shiftDown ? virtualKey : virtualKey - 'A' + 'a');
        return true;
    }
    if (virtualKey >= '0' && virtualKey <= '9') {
        static constexpr char shiftedDigits[] = ")!@#$%^&*(";
        *character = shiftDown ? shiftedDigits[virtualKey - '0'] : static_cast<char>(virtualKey);
        return true;
    }
    if (virtualKey == VK_SPACE) {
        *character = ' ';
        return true;
    }
    struct Mapping { WPARAM key; char plain; char shifted; };
    static constexpr std::array<Mapping, 11> mappings = {{
        {VK_OEM_1, ';', ':'}, {VK_OEM_PLUS, '=', '+'}, {VK_OEM_COMMA, ',', '<'},
        {VK_OEM_MINUS, '-', '_'}, {VK_OEM_PERIOD, '.', '>'}, {VK_OEM_2, '/', '?'},
        {VK_OEM_3, '`', '~'}, {VK_OEM_4, '[', '{'}, {VK_OEM_5, '\\', '|'},
        {VK_OEM_6, ']', '}'}, {VK_OEM_7, '\'', '"'},
    }};
    for (const auto& mapping : mappings) {
        if (mapping.key == virtualKey) {
            *character = shiftDown ? mapping.shifted : mapping.plain;
            return true;
        }
    }
    return false;
}

bool IsAsciiPunctuation(char character) noexcept {
    const unsigned char value = static_cast<unsigned char>(character);
    return value >= 0x21 && value <= 0x7e &&
           !((value >= '0' && value <= '9') || (value >= 'A' && value <= 'Z') ||
             (value >= 'a' && value <= 'z'));
}

std::wstring ChinesePunctuation(char character) {
    switch (character) {
    case ',': return L"，";
    case '.': return L"。";
    case '<': return L"《";
    case '>': return L"》";
    case '/': return L"、";
    case '?': return L"？";
    case ';': return L"；";
    case ':': return L"：";
    case '\'': return L"‘";
    case '"': return L"“";
    case '\\': return L"、";
    case '|': return L"・";
    case '`': return L"｀";
    case '~': return L"～";
    case '!': return L"！";
    case '@': return L"＠";
    case '#': return L"＃";
    case '$': return L"￥";
    case '%': return L"％";
    case '^': return L"……";
    case '&': return L"＆";
    case '*': return L"＊";
    case '(': return L"（";
    case ')': return L"）";
    case '-': return L"－";
    case '_': return L"——";
    case '+': return L"＋";
    case '=': return L"＝";
    case '[': return L"「";
    case ']': return L"」";
    case '{': return L"『";
    case '}': return L"』";
    default: return {};
    }
}

std::wstring FullWidth(char character) {
    if (character == ' ') return L"　";
    const unsigned char value = static_cast<unsigned char>(character);
    if (value < 0x21 || value > 0x7e) return {};
    return std::wstring(1, static_cast<wchar_t>(0xff01 + value - 0x21));
}

std::wstring WidenUtf8(const std::string& value) {
    if (value.empty()) return {};
    const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                                           static_cast<int>(value.size()), nullptr, 0);
    if (length <= 0) return {};
    std::wstring result(static_cast<size_t>(length), L'\0');
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                            static_cast<int>(value.size()), result.data(), length) != length) return {};
    return result;
}

std::string NarrowUtf8(const std::wstring& value) {
    if (value.empty()) return {};
    const int length = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
                                           static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
    if (length <= 0) return {};
    std::string result(static_cast<size_t>(length), '\0');
    if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
                            static_cast<int>(value.size()), result.data(), length,
                            nullptr, nullptr) != length) return {};
    return result;
}

void TraditionalizeCandidate(BrokerCandidate* candidate) noexcept {
    if (!candidate) return;
    candidate->text = TraditionalizeUtf8(candidate->text);
    for (auto& segment : candidate->segments) segment.text = TraditionalizeUtf8(segment.text);
}

}  // namespace

bool TryDirectOutputKey(WPARAM virtualKey, bool shiftDown,
                        const ExperimentSettings& settings, std::string* commit) noexcept {
    if (!commit) return false;
    commit->clear();
    if (!settings.asciiMode) return false;
    char character = 0;
    if (!TranslatePrintableKey(virtualKey, shiftDown, &character)) return false;

    std::wstring transformed;
    if (IsAsciiPunctuation(character) && !settings.asciiPunctuation) {
        transformed = ChinesePunctuation(character);
    } else if (settings.fullShape) {
        transformed = FullWidth(character);
    }
    if (transformed.empty()) return false;
    *commit = NarrowUtf8(transformed);
    return !commit->empty();
}

bool TranslatePunctuationKey(WPARAM virtualKey, bool shiftDown,
                             bool asciiPunctuation, bool fullShape,
                             std::string* commit) noexcept {
    if (!commit) return false;
    commit->clear();
    char character = 0;
    if (!TranslatePrintableKey(virtualKey, shiftDown, &character) ||
        !IsAsciiPunctuation(character)) return false;

    std::wstring transformed;
    if (!asciiPunctuation) {
        transformed = ChinesePunctuation(character);
    } else if (fullShape) {
        transformed = FullWidth(character);
    } else {
        transformed.assign(1, static_cast<wchar_t>(static_cast<unsigned char>(character)));
    }
    if (transformed.empty()) return false;
    *commit = NarrowUtf8(transformed);
    return !commit->empty();
}

std::string TraditionalizeUtf8(const std::string& text) noexcept {
    if (text.empty()) return {};
    try {
        const std::wstring source = WidenUtf8(text);
        if (source.empty()) return text;
        const int length = LCMapStringEx(L"zh-Hans", LCMAP_TRADITIONAL_CHINESE,
                                         source.data(), static_cast<int>(source.size()),
                                         nullptr, 0, nullptr, nullptr, 0);
        if (length <= 0) return text;
        std::wstring converted(static_cast<size_t>(length), L'\0');
        if (LCMapStringEx(L"zh-Hans", LCMAP_TRADITIONAL_CHINESE,
                          source.data(), static_cast<int>(source.size()), converted.data(),
                          length, nullptr, nullptr, 0) != length) return text;
        const std::string result = NarrowUtf8(converted);
        return result.empty() ? text : result;
    } catch (...) {
        return text;
    }
}

void ApplyTraditionalization(BrokerUpdate* update) noexcept {
    if (!update) return;
    update->commit = TraditionalizeUtf8(update->commit);
    for (auto& candidate : update->candidates) TraditionalizeCandidate(&candidate);
    if (update->hasSentence) TraditionalizeCandidate(&update->sentence);
}

}  // namespace yime::experiment
