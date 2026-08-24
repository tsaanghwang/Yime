#pragma once

#include <ctfutb.h>
#include <ocidl.h>
#include <olectl.h>

#include <atomic>
#include <string>
#include <utility>
#include <vector>

#include "ExperimentSettings.h"

inline constexpr UINT YIME_LBI_CHINESE = 0x6C01;
inline constexpr UINT YIME_LBI_ENGLISH = 0x6C02;
inline constexpr UINT YIME_LBI_MODE_VARIABLE = 0x6C10;
inline constexpr UINT YIME_LBI_MODE_FULL = 0x6C11;
inline constexpr UINT YIME_LBI_MODE_SHORTHAND = 0x6C12;
inline constexpr UINT YIME_LBI_FONT_SMALL = 0x6C20;
inline constexpr UINT YIME_LBI_FONT_MEDIUM = 0x6C21;
inline constexpr UINT YIME_LBI_FONT_LARGE = 0x6C22;
inline constexpr UINT YIME_LBI_ANNOTATION_KEYS = 0x6C30;
inline constexpr UINT YIME_LBI_ANNOTATION_YINYUAN = 0x6C31;
inline constexpr UINT YIME_LBI_ANNOTATION_PINYIN = 0x6C32;
inline constexpr UINT YIME_LBI_ANNOTATION_HIDDEN = 0x6C33;

class LanguageBarItem final : public ITfLangBarItemButton, public ITfSource {
public:
    using PopupPresenter = UINT (*)(HMENU menu, POINT point, void* context) noexcept;

    explicit LanguageBarItem(
        std::wstring settingsPath = yime::experiment::ResolveExperimentSettingsPath(),
        PopupPresenter presenter = nullptr, void* presenterContext = nullptr) noexcept;

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

private:
    ~LanguageBarItem();
    bool Apply(UINT id) noexcept;
    HMENU BuildPopupMenu() const noexcept;
    void Notify(DWORD flags) noexcept;
    static UINT PresentPopup(HMENU menu, POINT point, void* context) noexcept;

    std::atomic<ULONG> references_{1};
    std::wstring settingsPath_;
    PopupPresenter presenter_ = nullptr;
    void* presenterContext_ = nullptr;
    DWORD status_ = 0;
    bool lastAsciiMode_ = false;
    std::vector<std::pair<DWORD, ITfLangBarItemSink*>> sinks_;
    static std::atomic<DWORD> nextCookie_;
};
