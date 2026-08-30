#include "LanguageBarItem.h"

#include <algorithm>
#include <cstdio>
#include <cwchar>
#include <filesystem>
#include <mutex>
#include <unordered_map>
#include <vector>

#include "YimeTextServiceIds.h"
#include "LanguageBarResources.h"

namespace {

constexpr wchar_t kChinese[] = L"中";
constexpr wchar_t kEnglish[] = L"英";
constexpr wchar_t kTooltip[] = L"中英文切换；右键打开 Yime 自研栈试验版设置";
constexpr UINT kToolbarRefreshMilliseconds = 200;
std::mutex gRefreshTimersMutex;
std::unordered_map<UINT_PTR, LanguageBarItem*> gRefreshTimers;

BSTR copyText(const wchar_t* text) { return SysAllocString(text); }

std::wstring widenUtf8(const std::string& value) {
    if (value.empty()) return {};
    const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                                           static_cast<int>(value.size()), nullptr, 0);
    if (length <= 0) return {};
    std::wstring result(static_cast<size_t>(length), L'\0');
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                            static_cast<int>(value.size()), result.data(), length) != length) return {};
    return result;
}

const wchar_t* modeText(const yime::experiment::ExperimentSettings& settings) {
    return settings.asciiMode ? kEnglish : kChinese;
}

std::wstring defaultLanguageText(const yime::experiment::ExperimentSettings& settings) {
    return settings.asciiMode ? L"默认语言：英文" : L"默认语言：中文";
}

HRESULT addMenuItem(ITfMenu* menu, UINT id, DWORD flags, const wchar_t* text,
                    ITfMenu** submenu = nullptr) {
    return menu->AddMenuItem(id, flags, nullptr, nullptr, text,
                             text ? static_cast<ULONG>(wcslen(text)) : 0, submenu);
}

DWORD checked(bool value) { return value ? TF_LBMENUF_CHECKED : 0; }

UINT win32Checked(bool value) { return MF_STRING | (value ? MF_CHECKED : MF_UNCHECKED); }

void recordHostEvent(const std::wstring& settingsPath, const char* event, UINT command,
                     HRESULT result) noexcept {
    if (settingsPath.empty() || !event) return;
    try {
        const auto settings = yime::experiment::LoadExperimentSettings(settingsPath);
        const auto evidenceDirectory = std::filesystem::path(settingsPath).parent_path() / L"evidence";
        std::filesystem::create_directories(evidenceDirectory);
        const auto path = evidenceDirectory / L"language-bar-events.jsonl";
        SYSTEMTIME now{};
        GetSystemTime(&now);
        char line[1024]{};
        const int length = std::snprintf(
            line, sizeof(line),
            "{\"schema_version\":\"yimecore-language-bar-event-v1\","
            "\"timestamp\":\"%04u-%02u-%02uT%02u:%02u:%02u.%03uZ\","
            "\"process_id\":%lu,\"thread_id\":%lu,\"event\":\"%s\","
            "\"command_id\":%u,\"hresult\":%ld,\"ascii_mode\":%s,"
            "\"mode\":\"%s\",\"candidate_font_preset\":\"%s\","
            "\"candidate_annotation\":\"%s\",\"ascii_punctuation\":%s,"
            "\"full_shape\":%s,\"traditionalization\":%s,\"settings_revision\":%lld}\r\n",
            now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond,
            now.wMilliseconds, static_cast<unsigned long>(GetCurrentProcessId()),
            static_cast<unsigned long>(GetCurrentThreadId()), event, command,
            static_cast<long>(result), settings.asciiMode ? "true" : "false",
            settings.mode.c_str(), settings.candidateFontPreset.c_str(),
            settings.candidateAnnotation.c_str(), settings.asciiPunctuation ? "true" : "false",
            settings.fullShape ? "true" : "false",
            settings.traditionalization ? "true" : "false",
            static_cast<long long>(settings.revision));
        if (length <= 0 || static_cast<size_t>(length) >= sizeof(line)) return;
        HANDLE file = CreateFileW(path.c_str(), FILE_APPEND_DATA,
                                  FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                  nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (file == INVALID_HANDLE_VALUE) return;
        DWORD written = 0;
        WriteFile(file, line, static_cast<DWORD>(length), &written, nullptr);
        CloseHandle(file);
    } catch (...) {
    }
}

HMODULE currentModule() noexcept {
    HMODULE module = nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                           GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       reinterpret_cast<LPCWSTR>(&currentModule), &module);
    return module;
}

std::wstring quoteArgument(const std::wstring& value) {
    std::wstring quoted = L"\"";
    size_t slashes = 0;
    for (const wchar_t character : value) {
        if (character == L'\\') {
            ++slashes;
            continue;
        }
        if (character == L'\"') {
            quoted.append(slashes * 2 + 1, L'\\');
            quoted.push_back(character);
            slashes = 0;
            continue;
        }
        quoted.append(slashes, L'\\');
        slashes = 0;
        quoted.push_back(character);
    }
    quoted.append(slashes * 2, L'\\');
    quoted.push_back(L'\"');
    return quoted;
}

std::filesystem::path trialInstallRoot() {
    std::vector<wchar_t> path(512);
    for (;;) {
        const DWORD length = GetModuleFileNameW(currentModule(), path.data(),
                                                static_cast<DWORD>(path.size()));
        if (length == 0) return {};
        if (length < path.size() - 1) {
            path.resize(length);
            break;
        }
        path.resize(path.size() * 2);
    }
    return std::filesystem::path(path.data()).parent_path().parent_path();
}

bool startDetached(const std::filesystem::path& executable,
                   const std::vector<std::wstring>& arguments) noexcept {
    if (!std::filesystem::is_regular_file(executable)) return false;
    std::wstring commandLine = quoteArgument(executable.wstring());
    for (const auto& argument : arguments) {
        commandLine.push_back(L' ');
        commandLine += quoteArgument(argument);
    }
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    const BOOL started = CreateProcessW(executable.c_str(), commandLine.data(), nullptr, nullptr,
                                        FALSE, CREATE_UNICODE_ENVIRONMENT, nullptr,
                                        executable.parent_path().c_str(), &startup, &process);
    if (!started) return false;
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return true;
}

}  // namespace

std::atomic<DWORD> LanguageBarItem::nextCookie_{1};

LanguageBarItem::LanguageBarItem(std::wstring settingsPath, PopupPresenter presenter,
                                 void* presenterContext, ToolLauncher toolLauncher,
                                 void* toolLauncherContext) noexcept
    : settingsPath_(std::move(settingsPath)),
      presenter_(presenter ? presenter : PresentPopup),
      presenterContext_(presenterContext),
      toolLauncher_(toolLauncher ? toolLauncher : LaunchTool),
      toolLauncherContext_(toolLauncherContext) {
        const auto settings = yime::experiment::LoadExperimentSettings(settingsPath_);
        lastAsciiMode_ = settings.asciiMode;
        lastFullShape_ = settings.fullShape;
        lastAsciiPunctuation_ = settings.asciiPunctuation;
        lastTraditionalization_ = settings.traditionalization;
        lastRevision_ = settings.revision;
        refreshTimerId_ = SetTimer(nullptr, 0, kToolbarRefreshMilliseconds, RefreshTimerProc);
        if (refreshTimerId_) {
            const std::lock_guard<std::mutex> lock(gRefreshTimersMutex);
            gRefreshTimers.emplace(refreshTimerId_, this);
        }
}

LanguageBarItem::~LanguageBarItem() {
    if (refreshTimerId_) {
        KillTimer(nullptr, refreshTimerId_);
        const std::lock_guard<std::mutex> lock(gRefreshTimersMutex);
        gRefreshTimers.erase(refreshTimerId_);
    }
    for (auto& sink : sinks_) sink.second->Release();
}

STDMETHODIMP LanguageBarItem::QueryInterface(REFIID iid, void** object) {
    if (!object) return E_POINTER;
    *object = nullptr;
    if (IsEqualIID(iid, IID_IUnknown) || IsEqualIID(iid, __uuidof(ITfLangBarItem)) ||
        IsEqualIID(iid, __uuidof(ITfLangBarItemButton))) {
        *object = static_cast<ITfLangBarItemButton*>(this);
    } else if (IsEqualIID(iid, __uuidof(ITfSource))) {
        *object = static_cast<ITfSource*>(this);
    } else {
        return E_NOINTERFACE;
    }
    AddRef();
    return S_OK;
}

STDMETHODIMP_(ULONG) LanguageBarItem::AddRef() { return ++references_; }

STDMETHODIMP_(ULONG) LanguageBarItem::Release() {
    const ULONG remaining = --references_;
    if (!remaining) delete this;
    return remaining;
}

STDMETHODIMP LanguageBarItem::GetInfo(TF_LANGBARITEMINFO* info) {
    if (!info) return E_POINTER;
    *info = {};
    info->clsidService = CLSID_YimeTextServiceExperiment;
    info->guidItem = GUID_YimeTextServiceExperimentLangBar;
    // Match the production PIME input-mode item. Microsoft documents
    // TF_LBI_STYLE_SHOWNINTRAY as unsupported; GUID_LBI_INPUTMODE is what makes
    // this button eligible for the Windows 8+ taskbar input indicator.
    info->dwStyle = TF_LBI_STYLE_BTN_BUTTON;
    info->ulSort = 0;
    wcsncpy_s(info->szDescription,
              modeText(yime::experiment::LoadExperimentSettings(settingsPath_)), _TRUNCATE);
    return S_OK;
}

STDMETHODIMP LanguageBarItem::GetStatus(DWORD* status) {
    if (!status) return E_POINTER;
    *status = status_;
    return S_OK;
}

STDMETHODIMP LanguageBarItem::Show(BOOL show) {
    const DWORD previous = status_;
    if (show) status_ &= ~TF_LBI_STATUS_HIDDEN;
    else status_ |= TF_LBI_STATUS_HIDDEN;
    if (previous != status_) Notify(TF_LBI_STATUS);
    return S_OK;
}

STDMETHODIMP LanguageBarItem::GetTooltipString(BSTR* tooltip) {
    if (!tooltip) return E_POINTER;
    *tooltip = copyText(kTooltip);
    return *tooltip ? S_OK : E_OUTOFMEMORY;
}

STDMETHODIMP LanguageBarItem::OnClick(TfLBIClick click, POINT point, const RECT*) {
    if (click == TF_LBI_CLK_LEFT) {
        const UINT command = YIME_LBI_DEFAULT_LANGUAGE;
        const HRESULT result = Apply(command) ? S_OK : E_FAIL;
        recordHostEvent(settingsPath_, "left_click", command, result);
        return result;
    }
    if (click != TF_LBI_CLK_RIGHT) return S_OK;
    HMENU menu = BuildPopupMenu();
    if (!menu) {
        recordHostEvent(settingsPath_, "right_click_open", 0, E_OUTOFMEMORY);
        return E_OUTOFMEMORY;
    }
    recordHostEvent(settingsPath_, "right_click_open", 0, S_OK);
    const UINT command = presenter_(menu, point, presenterContext_);
    DestroyMenu(menu);
    if (command == 0) {
        recordHostEvent(settingsPath_, "right_click_cancel", 0, S_OK);
        return S_OK;
    }
    const HRESULT result = Apply(command) ? S_OK : E_INVALIDARG;
    recordHostEvent(settingsPath_, "right_click_command", command, result);
    return result;
}

STDMETHODIMP LanguageBarItem::InitMenu(ITfMenu* menu) {
    if (!menu) return E_POINTER;
    const auto settings = yime::experiment::LoadExperimentSettings(settingsPath_);
    const auto language = defaultLanguageText(settings);
    if (FAILED(addMenuItem(menu, YIME_LBI_DEFAULT_LANGUAGE, 0, language.c_str())) ||
        FAILED(addMenuItem(menu, 0, TF_LBMENUF_SEPARATOR, nullptr))) return E_FAIL;

    ITfMenu* punctuation = nullptr;
    if (FAILED(addMenuItem(menu, 0, TF_LBMENUF_SUBMENU, L"标点样式", &punctuation)) ||
        !punctuation) return E_FAIL;
    const bool punctuationOk =
        SUCCEEDED(addMenuItem(punctuation, YIME_LBI_PUNCTUATION_CHINESE,
                              checked(!settings.asciiPunctuation), L"中文标点")) &&
        SUCCEEDED(addMenuItem(punctuation, YIME_LBI_PUNCTUATION_ENGLISH,
                              checked(settings.asciiPunctuation), L"英文标点"));
    punctuation->Release();
    if (!punctuationOk) return E_FAIL;

    ITfMenu* shape = nullptr;
    if (FAILED(addMenuItem(menu, 0, TF_LBMENUF_SUBMENU, L"字符宽度", &shape)) || !shape) return E_FAIL;
    const bool shapeOk = SUCCEEDED(addMenuItem(shape, YIME_LBI_SHAPE_HALF,
                                               checked(!settings.fullShape), L"半宽")) &&
                         SUCCEEDED(addMenuItem(shape, YIME_LBI_SHAPE_FULL,
                                               checked(settings.fullShape), L"全宽"));
    shape->Release();
    if (!shapeOk) return E_FAIL;

    ITfMenu* script = nullptr;
    if (FAILED(addMenuItem(menu, 0, TF_LBMENUF_SUBMENU, L"汉字字形", &script)) || !script) return E_FAIL;
    const bool scriptOk =
        SUCCEEDED(addMenuItem(script, YIME_LBI_SCRIPT_SIMPLIFIED,
                              checked(!settings.traditionalization), L"简体")) &&
        SUCCEEDED(addMenuItem(script, YIME_LBI_SCRIPT_TRADITIONAL,
                              checked(settings.traditionalization), L"繁体"));
    script->Release();
    if (!scriptOk ||
        FAILED(addMenuItem(menu, 0, TF_LBMENUF_SEPARATOR, nullptr)) ||
        FAILED(addMenuItem(menu, YIME_LBI_INPUT_TOOLBAR, 0, L"基本设置")) ||
        FAILED(addMenuItem(menu, YIME_LBI_REVERSE_LOOKUP, 0, L"反查编码")) ||
        FAILED(addMenuItem(menu, YIME_LBI_USER_LEXICON, 0, L"用户词库")) ||
        FAILED(addMenuItem(menu, YIME_LBI_TRAINER_TOOL, 0, L"指法练习")) ||
        FAILED(addMenuItem(menu, YIME_LBI_TOOL_CENTER, 0, L"工具中心")) ||
        FAILED(addMenuItem(menu, YIME_LBI_SETTINGS_TOOL, 0, L"候选设置"))) return E_FAIL;
    recordHostEvent(settingsPath_, "init_menu", 0, S_OK);
    return S_OK;
}

STDMETHODIMP LanguageBarItem::OnMenuSelect(UINT id) {
    const HRESULT result = Apply(id) ? S_OK : E_INVALIDARG;
    recordHostEvent(settingsPath_, "menu_select", id, result);
    return result;
}

STDMETHODIMP LanguageBarItem::GetIcon(HICON* icon) {
    if (!icon) return E_POINTER;
    const auto settings = yime::experiment::LoadExperimentSettings(settingsPath_);
    const int resource = settings.asciiMode
        ? (settings.fullShape ? IDI_YIME_MODE_ENGLISH_FULL : IDI_YIME_MODE_ENGLISH_HALF)
        : (settings.fullShape ? IDI_YIME_MODE_CHINESE_FULL : IDI_YIME_MODE_CHINESE_HALF);
    const HICON shared = static_cast<HICON>(LoadImageW(currentModule(), MAKEINTRESOURCEW(resource),
                                                       IMAGE_ICON, 0, 0, LR_DEFAULTCOLOR));
    *icon = shared ? static_cast<HICON>(CopyImage(shared, IMAGE_ICON, 0, 0, 0)) : nullptr;
    return *icon ? S_OK : E_OUTOFMEMORY;
}

STDMETHODIMP LanguageBarItem::GetText(BSTR* text) {
    if (!text) return E_POINTER;
    *text = copyText(modeText(yime::experiment::LoadExperimentSettings(settingsPath_)));
    return *text ? S_OK : E_OUTOFMEMORY;
}

STDMETHODIMP LanguageBarItem::AdviseSink(REFIID iid, IUnknown* sink, DWORD* cookie) {
    if (!sink || !cookie) return E_POINTER;
    if (!IsEqualIID(iid, __uuidof(ITfLangBarItemSink))) return CONNECT_E_CANNOTCONNECT;
    ITfLangBarItemSink* itemSink = nullptr;
    if (FAILED(sink->QueryInterface(__uuidof(ITfLangBarItemSink), reinterpret_cast<void**>(&itemSink)))) {
        return E_NOINTERFACE;
    }
    *cookie = nextCookie_++;
    sinks_.emplace_back(*cookie, itemSink);
    return S_OK;
}

STDMETHODIMP LanguageBarItem::UnadviseSink(DWORD cookie) {
    const auto found = std::find_if(sinks_.begin(), sinks_.end(),
                                    [cookie](const auto& value) { return value.first == cookie; });
    if (found == sinks_.end()) return CONNECT_E_NOCONNECTION;
    found->second->Release();
    sinks_.erase(found);
    return S_OK;
}

bool LanguageBarItem::Apply(UINT id) noexcept {
    if (id == YIME_LBI_INPUT_TOOLBAR || id == YIME_LBI_REVERSE_LOOKUP ||
        id == YIME_LBI_USER_LEXICON || id == YIME_LBI_TRAINER_TOOL ||
        id == YIME_LBI_TOOL_CENTER || id == YIME_LBI_SETTINGS_TOOL) {
        return toolLauncher_ && toolLauncher_(id, settingsPath_, toolLauncherContext_);
    }
    using Command = yime::experiment::ExperimentSettingsCommand;
    Command command{};
    switch (id) {
    case YIME_LBI_DEFAULT_LANGUAGE: command = Command::ToggleAscii; break;
    case YIME_LBI_PUNCTUATION_CHINESE: command = Command::PunctuationChinese; break;
    case YIME_LBI_PUNCTUATION_ENGLISH: command = Command::PunctuationEnglish; break;
    case YIME_LBI_SHAPE_HALF: command = Command::ShapeHalf; break;
    case YIME_LBI_SHAPE_FULL: command = Command::ShapeFull; break;
    case YIME_LBI_SCRIPT_SIMPLIFIED: command = Command::ScriptSimplified; break;
    case YIME_LBI_SCRIPT_TRADITIONAL: command = Command::ScriptTraditional; break;
    default: return false;
    }
    yime::experiment::ExperimentSettings updated;
    if (!yime::experiment::ApplyExperimentSettingsCommand(command, settingsPath_, &updated)) return false;
    const bool textChanged = updated.asciiMode != lastAsciiMode_;
    const bool iconChanged = textChanged || updated.fullShape != lastFullShape_;
    lastAsciiMode_ = updated.asciiMode;
    lastFullShape_ = updated.fullShape;
    lastAsciiPunctuation_ = updated.asciiPunctuation;
    lastTraditionalization_ = updated.traditionalization;
    Notify(TF_LBI_STATUS | (textChanged ? TF_LBI_TEXT : 0) |
        (iconChanged ? TF_LBI_ICON : 0));
    return true;
}

HMENU LanguageBarItem::BuildPopupMenu() const noexcept {
    const auto settings = yime::experiment::LoadExperimentSettings(settingsPath_);
    HMENU root = CreatePopupMenu();
    HMENU punctuation = CreatePopupMenu();
    HMENU shape = CreatePopupMenu();
    HMENU script = CreatePopupMenu();
    if (!root || !punctuation || !shape || !script) {
        if (script) DestroyMenu(script);
        if (shape) DestroyMenu(shape);
        if (punctuation) DestroyMenu(punctuation);
        if (root) DestroyMenu(root);
        return nullptr;
    }
    const auto language = defaultLanguageText(settings);
    AppendMenuW(root, MF_STRING, YIME_LBI_DEFAULT_LANGUAGE, language.c_str());
    AppendMenuW(root, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(punctuation, win32Checked(!settings.asciiPunctuation), YIME_LBI_PUNCTUATION_CHINESE, L"中文标点");
    AppendMenuW(punctuation, win32Checked(settings.asciiPunctuation), YIME_LBI_PUNCTUATION_ENGLISH, L"英文标点");
    AppendMenuW(root, MF_POPUP | MF_STRING, reinterpret_cast<UINT_PTR>(punctuation), L"标点样式");
    AppendMenuW(shape, win32Checked(!settings.fullShape), YIME_LBI_SHAPE_HALF, L"半宽");
    AppendMenuW(shape, win32Checked(settings.fullShape), YIME_LBI_SHAPE_FULL, L"全宽");
    AppendMenuW(root, MF_POPUP | MF_STRING, reinterpret_cast<UINT_PTR>(shape), L"字符宽度");
    AppendMenuW(script, win32Checked(!settings.traditionalization), YIME_LBI_SCRIPT_SIMPLIFIED, L"简体");
    AppendMenuW(script, win32Checked(settings.traditionalization), YIME_LBI_SCRIPT_TRADITIONAL, L"繁体");
    AppendMenuW(root, MF_POPUP | MF_STRING, reinterpret_cast<UINT_PTR>(script), L"汉字字形");
    AppendMenuW(root, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(root, MF_STRING, YIME_LBI_INPUT_TOOLBAR, L"基本设置");
    AppendMenuW(root, MF_STRING, YIME_LBI_REVERSE_LOOKUP, L"反查编码");
    AppendMenuW(root, MF_STRING, YIME_LBI_USER_LEXICON, L"用户词库");
    AppendMenuW(root, MF_STRING, YIME_LBI_TRAINER_TOOL, L"指法练习");
    AppendMenuW(root, MF_STRING, YIME_LBI_TOOL_CENTER, L"工具中心");
    AppendMenuW(root, MF_STRING, YIME_LBI_SETTINGS_TOOL, L"候选设置");
    return root;
}

UINT LanguageBarItem::PresentPopup(HMENU menu, POINT point, void*) noexcept {
    HWND owner = GetForegroundWindow();
    if (!owner) owner = GetDesktopWindow();
    const UINT command = TrackPopupMenu(menu, TPM_NONOTIFY | TPM_RETURNCMD | TPM_LEFTALIGN |
                                               TPM_BOTTOMALIGN | TPM_RIGHTBUTTON,
                                        point.x, point.y, 0, owner, nullptr);
    if (owner) PostMessageW(owner, WM_NULL, 0, 0);
    return command;
}

bool LanguageBarItem::LaunchTool(UINT command, const std::wstring& settingsPath,
                                 void*) noexcept {
    try {
        const auto installRoot = trialInstallRoot();
        if (installRoot.empty() || settingsPath.empty()) return false;
        const auto stateRoot = std::filesystem::path(settingsPath).parent_path();
        const auto sharedDir = installRoot / L"data";
        const auto indexRoot = installRoot / L"indexes";
        const auto settings = yime::experiment::LoadExperimentSettings(settingsPath);
        switch (command) {
        case YIME_LBI_INPUT_TOOLBAR:
            return startDetached(installRoot / L"bin" / L"YimeCoreInputToolbar.exe",
                                 {L"-StatePath", settingsPath,
                                  L"-SettingsTool", (installRoot / L"bin" / L"YimeCoreSettingsTool.exe").wstring(),
                                  L"-TrainerTool", (installRoot / L"bin" / L"YimeCoreTrainer.exe").wstring(),
                                  L"-ToolCenterTool", (installRoot / L"bin" / L"YimeCoreToolCenter.exe").wstring(),
                                  L"-SharedDir", sharedDir.wstring(), L"-UserDir", stateRoot.wstring(),
                                  L"-HelpDir", (installRoot / L"help").wstring(),
                                  L"-LogDir", (stateRoot / L"logs").wstring(),
                                  L"-Experimental"});
        case YIME_LBI_REVERSE_LOOKUP:
            return startDetached(installRoot / L"bin" / L"YimeCoreReverseLookup.exe",
                                 {L"-SharedDir", sharedDir.wstring(), L"-UserDir", stateRoot.wstring(),
                                  L"-IndexRoot", indexRoot.wstring(), L"-Mode", widenUtf8(settings.mode)});
        case YIME_LBI_USER_LEXICON:
            return startDetached(installRoot / L"bin" / L"YimeCoreLexiconManager.exe",
                                 {L"-SharedDir", sharedDir.wstring(), L"-UserDir", stateRoot.wstring(),
                                  L"-IndexRoot", indexRoot.wstring(), L"-Mode", widenUtf8(settings.mode),
                                  L"-Experimental"});
        case YIME_LBI_TRAINER_TOOL:
            return startDetached(installRoot / L"bin" / L"YimeCoreTrainer.exe",
                                 {L"-SharedDir", sharedDir.wstring(), L"-UserDir", stateRoot.wstring(),
                                  L"-Mode", widenUtf8(settings.mode), L"-Experimental"});
        case YIME_LBI_TOOL_CENTER:
            return startDetached(installRoot / L"bin" / L"YimeCoreToolCenter.exe",
                                 {L"-InstallRoot", installRoot.wstring(),
                                  L"-StateRoot", stateRoot.wstring(), L"-StatePath", settingsPath,
                                  L"-Mode", widenUtf8(settings.mode), L"-Experimental"});
        case YIME_LBI_SETTINGS_TOOL:
            return startDetached(installRoot / L"bin" / L"YimeCoreSettingsTool.exe",
                                 {L"-UserDir", stateRoot.wstring(), L"-SharedDir", sharedDir.wstring(),
                                  L"-StatePath", settingsPath, L"-Experimental"});
        default:
            return false;
        }
    } catch (...) {
        return false;
    }
}

void LanguageBarItem::Refresh() noexcept {
    const auto settings = yime::experiment::LoadExperimentSettings(settingsPath_);
    const bool settingsChanged = settings.revision != lastRevision_;
    const bool textChanged = settings.asciiMode != lastAsciiMode_;
    const bool iconChanged = textChanged || settings.fullShape != lastFullShape_;
    const bool menuChanged = settings.asciiPunctuation != lastAsciiPunctuation_ ||
                             settings.traditionalization != lastTraditionalization_;
    lastRevision_ = settings.revision;
    if (settingsChanged && settingsChangedHandler_) {
        settingsChangedHandler_(settingsChangedContext_, settings);
    }
    if (!textChanged && !iconChanged && !menuChanged) return;
    lastAsciiMode_ = settings.asciiMode;
    lastFullShape_ = settings.fullShape;
    lastAsciiPunctuation_ = settings.asciiPunctuation;
    lastTraditionalization_ = settings.traditionalization;
    Notify(TF_LBI_STATUS | (textChanged ? TF_LBI_TEXT : 0) |
           (iconChanged ? TF_LBI_ICON : 0));
}

void CALLBACK LanguageBarItem::RefreshTimerProc(HWND, UINT, UINT_PTR timerId, DWORD) noexcept {
    LanguageBarItem* item = nullptr;
    {
        const std::lock_guard<std::mutex> lock(gRefreshTimersMutex);
        const auto found = gRefreshTimers.find(timerId);
        if (found != gRefreshTimers.end()) item = found->second;
    }
    if (item) item->Refresh();
}

void LanguageBarItem::Notify(DWORD flags) noexcept {
    for (const auto& sink : sinks_) sink.second->OnUpdate(flags);
}
