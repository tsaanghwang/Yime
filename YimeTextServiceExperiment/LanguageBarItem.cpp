#include "LanguageBarItem.h"

#include <algorithm>
#include <cwchar>

#include "YimeTextServiceIds.h"
#include "LanguageBarResources.h"

namespace {

constexpr wchar_t kChinese[] = L"中";
constexpr wchar_t kEnglish[] = L"英";
constexpr wchar_t kTooltip[] = L"中英文切换；右键打开 Yime 自研栈试验版设置";

BSTR copyText(const wchar_t* text) { return SysAllocString(text); }

const wchar_t* modeText(const yime::experiment::ExperimentSettings& settings) {
    return settings.asciiMode ? kEnglish : kChinese;
}

HRESULT addMenuItem(ITfMenu* menu, UINT id, DWORD flags, const wchar_t* text,
                    ITfMenu** submenu = nullptr) {
    return menu->AddMenuItem(id, flags, nullptr, nullptr, text,
                             text ? static_cast<ULONG>(wcslen(text)) : 0, submenu);
}

DWORD checked(bool value) { return value ? TF_LBMENUF_CHECKED : 0; }

UINT win32Checked(bool value) { return MF_STRING | (value ? MF_CHECKED : MF_UNCHECKED); }

HMODULE currentModule() noexcept {
    HMODULE module = nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                           GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       reinterpret_cast<LPCWSTR>(&currentModule), &module);
    return module;
}

}  // namespace

std::atomic<DWORD> LanguageBarItem::nextCookie_{1};

LanguageBarItem::LanguageBarItem(std::wstring settingsPath, PopupPresenter presenter,
                                 void* presenterContext) noexcept
    : settingsPath_(std::move(settingsPath)),
      presenter_(presenter ? presenter : PresentPopup),
      presenterContext_(presenterContext) {
    lastAsciiMode_ = yime::experiment::LoadExperimentSettings(settingsPath_).asciiMode;
}

LanguageBarItem::~LanguageBarItem() {
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
        const bool asciiMode = yime::experiment::LoadExperimentSettings(settingsPath_).asciiMode;
        return Apply(asciiMode ? YIME_LBI_CHINESE : YIME_LBI_ENGLISH) ? S_OK : E_FAIL;
    }
    if (click != TF_LBI_CLK_RIGHT) return S_OK;
    HMENU menu = BuildPopupMenu();
    if (!menu) return E_OUTOFMEMORY;
    const UINT command = presenter_(menu, point, presenterContext_);
    DestroyMenu(menu);
    if (command == 0) return S_OK;
    return Apply(command) ? S_OK : E_INVALIDARG;
}

STDMETHODIMP LanguageBarItem::InitMenu(ITfMenu* menu) {
    if (!menu) return E_POINTER;
    const auto settings = yime::experiment::LoadExperimentSettings(settingsPath_);
    if (FAILED(addMenuItem(menu, YIME_LBI_CHINESE, checked(!settings.asciiMode), L"中文输入")) ||
        FAILED(addMenuItem(menu, YIME_LBI_ENGLISH, checked(settings.asciiMode), L"英文输入")) ||
        FAILED(addMenuItem(menu, 0, TF_LBMENUF_SEPARATOR, nullptr))) return E_FAIL;

    ITfMenu* mode = nullptr;
    if (FAILED(addMenuItem(menu, 0, TF_LBMENUF_SUBMENU, L"输入方案", &mode)) || !mode) return E_FAIL;
    const bool modeOk = SUCCEEDED(addMenuItem(mode, YIME_LBI_MODE_VARIABLE,
                                              checked(settings.mode == "variable"), L"变长模式")) &&
                        SUCCEEDED(addMenuItem(mode, YIME_LBI_MODE_FULL,
                                              checked(settings.mode == "full"), L"等长模式")) &&
                        SUCCEEDED(addMenuItem(mode, YIME_LBI_MODE_SHORTHAND,
                                              checked(settings.mode == "shorthand"), L"省键模式"));
    mode->Release();
    if (!modeOk) return E_FAIL;

    ITfMenu* font = nullptr;
    if (FAILED(addMenuItem(menu, 0, TF_LBMENUF_SUBMENU, L"候选字号", &font)) || !font) return E_FAIL;
    const bool fontOk = SUCCEEDED(addMenuItem(font, YIME_LBI_FONT_SMALL,
                                              checked(settings.candidateFontPreset == "small"), L"小")) &&
                        SUCCEEDED(addMenuItem(font, YIME_LBI_FONT_MEDIUM,
                                              checked(settings.candidateFontPreset == "medium"), L"中")) &&
                        SUCCEEDED(addMenuItem(font, YIME_LBI_FONT_LARGE,
                                              checked(settings.candidateFontPreset == "large"), L"大"));
    font->Release();
    if (!fontOk) return E_FAIL;

    ITfMenu* annotation = nullptr;
    if (FAILED(addMenuItem(menu, 0, TF_LBMENUF_SUBMENU, L"显示编码", &annotation)) || !annotation) return E_FAIL;
    const bool annotationOk =
        SUCCEEDED(addMenuItem(annotation, YIME_LBI_ANNOTATION_KEYS,
                              checked(settings.candidateAnnotation == "key_sequence"), L"键位序列")) &&
        SUCCEEDED(addMenuItem(annotation, YIME_LBI_ANNOTATION_YINYUAN,
                              checked(settings.candidateAnnotation == "yinyuan"), L"音元")) &&
        SUCCEEDED(addMenuItem(annotation, YIME_LBI_ANNOTATION_PINYIN,
                              checked(settings.candidateAnnotation == "standard_pinyin"), L"标准拼音")) &&
        SUCCEEDED(addMenuItem(annotation, YIME_LBI_ANNOTATION_HIDDEN,
                              checked(settings.candidateAnnotation == "hidden"), L"隐藏"));
    annotation->Release();
    return annotationOk ? S_OK : E_FAIL;
}

STDMETHODIMP LanguageBarItem::OnMenuSelect(UINT id) { return Apply(id) ? S_OK : E_INVALIDARG; }

STDMETHODIMP LanguageBarItem::GetIcon(HICON* icon) {
    if (!icon) return E_POINTER;
    const bool asciiMode = yime::experiment::LoadExperimentSettings(settingsPath_).asciiMode;
    const int resource = asciiMode ? IDI_YIME_MODE_ENGLISH : IDI_YIME_MODE_CHINESE;
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
    using Command = yime::experiment::ExperimentSettingsCommand;
    Command command{};
    switch (id) {
    case YIME_LBI_CHINESE: command = Command::Chinese; break;
    case YIME_LBI_ENGLISH: command = Command::English; break;
    case YIME_LBI_MODE_VARIABLE: command = Command::ModeVariable; break;
    case YIME_LBI_MODE_FULL: command = Command::ModeFull; break;
    case YIME_LBI_MODE_SHORTHAND: command = Command::ModeShorthand; break;
    case YIME_LBI_FONT_SMALL: command = Command::FontSmall; break;
    case YIME_LBI_FONT_MEDIUM: command = Command::FontMedium; break;
    case YIME_LBI_FONT_LARGE: command = Command::FontLarge; break;
    case YIME_LBI_ANNOTATION_KEYS: command = Command::AnnotationKeySequence; break;
    case YIME_LBI_ANNOTATION_YINYUAN: command = Command::AnnotationYinyuan; break;
    case YIME_LBI_ANNOTATION_PINYIN: command = Command::AnnotationStandardPinyin; break;
    case YIME_LBI_ANNOTATION_HIDDEN: command = Command::AnnotationHidden; break;
    default: return false;
    }
    yime::experiment::ExperimentSettings updated;
    if (!yime::experiment::ApplyExperimentSettingsCommand(command, settingsPath_, &updated)) return false;
    const bool textChanged = updated.asciiMode != lastAsciiMode_;
    lastAsciiMode_ = updated.asciiMode;
    Notify(textChanged ? TF_LBI_TEXT | TF_LBI_ICON | TF_LBI_STATUS : TF_LBI_STATUS);
    return true;
}

HMENU LanguageBarItem::BuildPopupMenu() const noexcept {
    const auto settings = yime::experiment::LoadExperimentSettings(settingsPath_);
    HMENU root = CreatePopupMenu();
    HMENU mode = CreatePopupMenu();
    HMENU font = CreatePopupMenu();
    HMENU annotation = CreatePopupMenu();
    if (!root || !mode || !font || !annotation) {
        if (annotation) DestroyMenu(annotation);
        if (font) DestroyMenu(font);
        if (mode) DestroyMenu(mode);
        if (root) DestroyMenu(root);
        return nullptr;
    }
    AppendMenuW(root, win32Checked(!settings.asciiMode), YIME_LBI_CHINESE, L"中文输入");
    AppendMenuW(root, win32Checked(settings.asciiMode), YIME_LBI_ENGLISH, L"英文输入");
    AppendMenuW(root, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(mode, win32Checked(settings.mode == "variable"), YIME_LBI_MODE_VARIABLE, L"变长模式");
    AppendMenuW(mode, win32Checked(settings.mode == "full"), YIME_LBI_MODE_FULL, L"等长模式");
    AppendMenuW(mode, win32Checked(settings.mode == "shorthand"), YIME_LBI_MODE_SHORTHAND, L"省键模式");
    AppendMenuW(root, MF_POPUP | MF_STRING, reinterpret_cast<UINT_PTR>(mode), L"输入方案");
    AppendMenuW(font, win32Checked(settings.candidateFontPreset == "small"), YIME_LBI_FONT_SMALL, L"小");
    AppendMenuW(font, win32Checked(settings.candidateFontPreset == "medium"), YIME_LBI_FONT_MEDIUM, L"中");
    AppendMenuW(font, win32Checked(settings.candidateFontPreset == "large"), YIME_LBI_FONT_LARGE, L"大");
    AppendMenuW(root, MF_POPUP | MF_STRING, reinterpret_cast<UINT_PTR>(font), L"候选字号");
    AppendMenuW(annotation, win32Checked(settings.candidateAnnotation == "key_sequence"), YIME_LBI_ANNOTATION_KEYS, L"键位序列");
    AppendMenuW(annotation, win32Checked(settings.candidateAnnotation == "yinyuan"), YIME_LBI_ANNOTATION_YINYUAN, L"音元");
    AppendMenuW(annotation, win32Checked(settings.candidateAnnotation == "standard_pinyin"), YIME_LBI_ANNOTATION_PINYIN, L"标准拼音");
    AppendMenuW(annotation, win32Checked(settings.candidateAnnotation == "hidden"), YIME_LBI_ANNOTATION_HIDDEN, L"隐藏");
    AppendMenuW(root, MF_POPUP | MF_STRING, reinterpret_cast<UINT_PTR>(annotation), L"显示编码");
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

void LanguageBarItem::Refresh() noexcept {
    const bool asciiMode = yime::experiment::LoadExperimentSettings(settingsPath_).asciiMode;
    if (asciiMode == lastAsciiMode_) return;
    lastAsciiMode_ = asciiMode;
    Notify(TF_LBI_TEXT | TF_LBI_ICON | TF_LBI_STATUS);
}

void LanguageBarItem::Notify(DWORD flags) noexcept {
    for (const auto& sink : sinks_) sink.second->OnUpdate(flags);
}
