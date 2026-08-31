#pragma once

#include <ctfutb.h>
#include <ocidl.h>
#include <olectl.h>

#include <atomic>
#include <string>
#include <utility>
#include <vector>

#include "ExperimentSettings.h"

inline constexpr UINT YIME_LBI_DEFAULT_LANGUAGE = 0x6C00;
inline constexpr UINT YIME_LBI_PUNCTUATION_CHINESE = 0x6C50;
inline constexpr UINT YIME_LBI_PUNCTUATION_ENGLISH = 0x6C51;
inline constexpr UINT YIME_LBI_SHAPE_HALF = 0x6C60;
inline constexpr UINT YIME_LBI_SHAPE_FULL = 0x6C61;
inline constexpr UINT YIME_LBI_SCRIPT_SIMPLIFIED = 0x6C70;
inline constexpr UINT YIME_LBI_SCRIPT_TRADITIONAL = 0x6C71;
inline constexpr UINT YIME_LBI_INPUT_TOOLBAR = 0x6C40;
inline constexpr UINT YIME_LBI_REVERSE_LOOKUP = 0x6C41;
inline constexpr UINT YIME_LBI_USER_LEXICON = 0x6C42;
inline constexpr UINT YIME_LBI_SETTINGS_TOOL = 0x6C43;
inline constexpr UINT YIME_LBI_TRAINER_TOOL = 0x6C44;
inline constexpr UINT YIME_LBI_TOOL_CENTER = 0x6C45;

std::wstring SelectTrialInstallRoot(const std::wstring& moduleRoot,
                                    const std::wstring& registeredRoot) noexcept;

class LanguageBarItem final : public ITfLangBarItemButton, public ITfSource {
public:
    using PopupPresenter = UINT (*)(HMENU menu, POINT point, void* context) noexcept;
    using ToolLauncher = bool (*)(UINT command, const std::wstring& settingsPath,
                                  void* context) noexcept;
    using RuntimeEnsurer = bool (*)(const std::wstring& settingsPath,
                                    void* context) noexcept;
    using SettingsChangedHandler = void (*)(
        void* context, const yime::experiment::ExperimentSettings& settings) noexcept;

    explicit LanguageBarItem(
        std::wstring settingsPath = yime::experiment::ResolveExperimentSettingsPath(),
        PopupPresenter presenter = nullptr, void* presenterContext = nullptr,
        ToolLauncher toolLauncher = nullptr, void* toolLauncherContext = nullptr,
        RuntimeEnsurer runtimeEnsurer = nullptr, void* runtimeEnsurerContext = nullptr) noexcept;

    STDMETHODIMP QueryInterface(REFIID iid, void** object) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;
    STDMETHODIMP GetInfo(TF_LANGBARITEMINFO* info) override;
    STDMETHODIMP GetStatus(DWORD* status) override;
    STDMETHODIMP Show(BOOL show) override;
    STDMETHODIMP GetTooltipString(BSTR* tooltip) override;
    STDMETHODIMP OnClick(TfLBIClick click, POINT point, const RECT* area) override;
    STDMETHODIMP InitMenu(ITfMenu* menu) override;
    STDMETHODIMP OnMenuSelect(UINT id) override;
    STDMETHODIMP GetIcon(HICON* icon) override;
    STDMETHODIMP GetText(BSTR* text) override;
    STDMETHODIMP AdviseSink(REFIID iid, IUnknown* sink, DWORD* cookie) override;
    STDMETHODIMP UnadviseSink(DWORD cookie) override;

    void Refresh() noexcept;
    void SetSettingsChangedHandler(SettingsChangedHandler handler, void* context) noexcept {
        settingsChangedHandler_ = handler;
        settingsChangedContext_ = context;
    }

private:
    ~LanguageBarItem();
    bool Apply(UINT id) noexcept;
    HMENU BuildPopupMenu() const noexcept;
    void Notify(DWORD flags) noexcept;
    static void CALLBACK RefreshTimerProc(HWND, UINT, UINT_PTR timerId, DWORD) noexcept;
    static UINT PresentPopup(HMENU menu, POINT point, void* context) noexcept;
    static bool LaunchTool(UINT command, const std::wstring& settingsPath,
                           void* context) noexcept;
    static bool EnsureTrialRuntime(const std::wstring& settingsPath,
                                   void* context) noexcept;

    std::atomic<ULONG> references_{1};
    std::wstring settingsPath_;
    PopupPresenter presenter_ = nullptr;
    void* presenterContext_ = nullptr;
    ToolLauncher toolLauncher_ = nullptr;
    void* toolLauncherContext_ = nullptr;
    RuntimeEnsurer runtimeEnsurer_ = nullptr;
    void* runtimeEnsurerContext_ = nullptr;
    DWORD status_ = 0;
    bool lastAsciiMode_ = false;
    bool lastFullShape_ = false;
    bool lastAsciiPunctuation_ = false;
    bool lastTraditionalization_ = false;
    std::int64_t lastRevision_ = 0;
    SettingsChangedHandler settingsChangedHandler_ = nullptr;
    void* settingsChangedContext_ = nullptr;
    UINT_PTR refreshTimerId_ = 0;
    std::vector<std::pair<DWORD, ITfLangBarItemSink*>> sinks_;
    static std::atomic<DWORD> nextCookie_;
};
