#include <windows.h>
#include <msctf.h>

#include <iostream>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>
#include <string_view>
#include <vector>

#include "KeyContract.h"
#include "BrokerEndpoint.h"
#include "CandidateListUIElement.h"
#include "CandidatePopup.h"
#include "ExperimentSettings.h"
#include "LanguageBarItem.h"
#include "OutputTransform.h"
#include "YimeTextServiceIds.h"

namespace {

using GetClassObject = HRESULT(__stdcall*)(REFCLSID, REFIID, void**);
using CanUnloadNow = HRESULT(__stdcall*)();

int failures = 0;

std::wstring temporaryStatePath(const wchar_t* leaf) {
    wchar_t directory[MAX_PATH]{};
    GetTempPathW(MAX_PATH, directory);
    const auto root = std::filesystem::path(directory) /
                      (std::wstring(L"yime-language-bar-") + std::to_wstring(GetCurrentProcessId()));
    std::filesystem::create_directories(root);
    return (root / leaf).wstring();
}

class FakeMenu final : public ITfMenu {
public:
    struct Entry {
        UINT id = 0;
        DWORD flags = 0;
        std::wstring text;
        FakeMenu* submenu = nullptr;
    };

    ~FakeMenu() {
        for (auto& entry : entries) if (entry.submenu) entry.submenu->Release();
    }
    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) return E_POINTER;
        *object = nullptr;
        if (!IsEqualIID(iid, IID_IUnknown) && !IsEqualIID(iid, __uuidof(ITfMenu))) return E_NOINTERFACE;
        *object = static_cast<ITfMenu*>(this);
        AddRef();
        return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
    STDMETHODIMP_(ULONG) Release() override {
        const ULONG remaining = --references_;
        if (!remaining) delete this;
        return remaining;
    }
    STDMETHODIMP AddMenuItem(UINT id, DWORD flags, HBITMAP, HBITMAP, const WCHAR* text,
                             ULONG count, ITfMenu** submenu) override {
        Entry entry{id, flags, text ? std::wstring(text, count) : std::wstring(), nullptr};
        if (submenu) {
            entry.submenu = new FakeMenu();
            entry.submenu->AddRef();
            *submenu = entry.submenu;
        }
        entries.push_back(std::move(entry));
        return S_OK;
    }

    std::vector<Entry> entries;

private:
    std::atomic<ULONG> references_{1};
};

class FakeLanguageBarSink final : public ITfLangBarItemSink {
public:
    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) return E_POINTER;
        *object = nullptr;
        if (!IsEqualIID(iid, IID_IUnknown) && !IsEqualIID(iid, __uuidof(ITfLangBarItemSink))) {
            return E_NOINTERFACE;
        }
        *object = static_cast<ITfLangBarItemSink*>(this);
        AddRef();
        return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
    STDMETHODIMP_(ULONG) Release() override { return --references_; }
    STDMETHODIMP OnUpdate(DWORD flags) override {
        updates |= flags;
        ++count;
        return S_OK;
    }
    DWORD updates = 0;
    unsigned count = 0;

private:
    std::atomic<ULONG> references_{1};
};

UINT selectChineseFromPopup(HMENU menu, POINT, void* context) noexcept {
    auto* seen = static_cast<bool*>(context);
       *seen = menu && GetMenuItemCount(menu) == 16 && GetSubMenu(menu, 3) &&
            GetSubMenu(menu, 4) && GetSubMenu(menu, 5) && GetSubMenu(menu, 6) &&
            GetSubMenu(menu, 7) && GetSubMenu(menu, 8);
    return YIME_LBI_CHINESE;
}

bool recordToolLaunch(UINT command, const std::wstring&, void* context) noexcept {
    *static_cast<UINT*>(context) = command;
    return true;
}

void expect(bool condition, const char* message) {
    if (!condition) {
        std::cerr << message << '\n';
        ++failures;
    }
}

void testKeyContract() {
    using namespace yime::experiment;
    for (WPARAM key = '0'; key <= '9'; ++key) {
        const auto plain = ClassifyVirtualKey(key, false);
        expect(plain.route == KeyRoute::AppendComposition, "base digit must remain a composition key");
    }
    for (WPARAM key = '1'; key <= '9'; ++key) {
        const auto shifted = ClassifyVirtualKey(key, true);
        expect(shifted.route == KeyRoute::SelectCandidate, "Shift+1..9 must select candidates");
        expect(shifted.candidateOrdinal == static_cast<unsigned>(key - '0'), "candidate ordinal mismatch");
    }
    expect(ClassifyVirtualKey('0', true).route == KeyRoute::AppendComposition,
           "Shift+0 must not become a candidate ordinal");
    for (const WPARAM key : {static_cast<WPARAM>(VK_RETURN), static_cast<WPARAM>(VK_SPACE)}) {
        const auto plain = ClassifyVirtualKey(key, false);
        expect(plain.route == KeyRoute::SelectCurrentCandidate,
               "plain Enter/Space must select the highlighted candidate");
        expect(ClassifyVirtualKey(key, true).route == KeyRoute::PassThrough,
               "shifted Enter/Space must retain host behavior");
    }
    expect(ClassifyVirtualKey(VK_BACK, false).route == KeyRoute::BackspaceComposition &&
               ClassifyVirtualKey(VK_BACK, true).route == KeyRoute::BackspaceComposition,
           "Backspace must edit the Broker composition regardless of Shift state");
	expect(ClassifyVirtualKey(VK_ESCAPE, false).route == KeyRoute::ClearComposition &&
			   ClassifyVirtualKey(VK_ESCAPE, true).route == KeyRoute::ClearComposition,
		   "Escape must cancel the Broker composition regardless of Shift state");
    expect(ClassifyVirtualKey(VK_PRIOR, false).route == KeyRoute::PreviousCandidatePage,
           "PageUp must request the previous Broker candidate page");
    expect(ClassifyVirtualKey(VK_NEXT, false).route == KeyRoute::NextCandidatePage,
           "PageDown must request the next Broker candidate page");
    expect(ClassifyVirtualKey(VK_UP, false).route == KeyRoute::PreviousCandidate &&
               ClassifyVirtualKey(VK_DOWN, false).route == KeyRoute::NextCandidate,
           "Up/Down must move the candidate highlight");
    expect(ClassifyVirtualKey(VK_LEFT, false).route == KeyRoute::PreviousCandidatePage &&
               ClassifyVirtualKey(VK_RIGHT, false).route == KeyRoute::NextCandidatePage,
           "Left/Right must page the Broker candidates");
       expect(ClassifyVirtualKey(VK_LEFT, false, true, false).route == KeyRoute::PreviousSentenceSegment &&
                        ClassifyVirtualKey(VK_RIGHT, false, true, false).route == KeyRoute::NextSentenceSegment,
                 "Ctrl+Left/Right must navigate sentence segments");
       expect(ClassifyVirtualKey(VK_DELETE, false, true, false).route == KeyRoute::ForgetCurrentCandidate,
                 "Ctrl+Delete must forget the highlighted candidate");
    for (const WPARAM key : {static_cast<WPARAM>('A'), static_cast<WPARAM>('C'),
                             static_cast<WPARAM>('V'), static_cast<WPARAM>('X'),
                             static_cast<WPARAM>('Y'), static_cast<WPARAM>('Z')}) {
        expect(ClassifyVirtualKey(key, false, true, false).route == KeyRoute::PassThrough,
               "Ctrl editing shortcut was captured as a composition key");
    }
    expect(ClassifyVirtualKey('Z', true, true, false).route == KeyRoute::PassThrough,
           "Ctrl+Shift+Z redo shortcut was captured as a composition key");
    expect(ClassifyVirtualKey(VK_DELETE, true, true, false).route == KeyRoute::PassThrough,
           "Ctrl+Shift+Delete must retain host behavior");
    ShiftTapTracker shiftTap;
    expect(shiftTap.OnKeyDown(VK_SHIFT) && shiftTap.OnKeyUp(VK_SHIFT),
           "single Shift tap did not request a Chinese/English toggle");
    expect(shiftTap.OnKeyDown(VK_SHIFT) && !shiftTap.OnKeyDown('A') &&
               !shiftTap.OnKeyUp(VK_SHIFT),
           "Shift used with another key incorrectly toggled Chinese/English");
    const auto& labels = CandidateLabels();
    constexpr std::wstring_view expected[] = {L"⇧1", L"⇧2", L"⇧3", L"⇧4", L"⇧5", L"⇧6", L"⇧7", L"⇧8", L"⇧9"};
    for (size_t index = 0; index < labels.size(); ++index) {
        expect(labels[index] == expected[index], "candidate label lost Shift marker");
    }
}

void testOutputTransformContract() {
    using namespace yime::experiment;
    ExperimentSettings settings;
    settings.asciiMode = false;
    settings.asciiPunctuation = false;
    std::string commit;
    expect(!TryDirectOutputKey(VK_OEM_COMMA, false, settings, &commit),
           "Chinese-mode punctuation stopped being a Yime composition key");

    settings.asciiMode = true;
    expect(TryDirectOutputKey(VK_OEM_COMMA, false, settings, &commit) && commit == u8"，",
           "Chinese punctuation did not transform an English pass-through comma");
    settings.asciiPunctuation = true;
    expect(!TryDirectOutputKey(VK_OEM_COMMA, false, settings, &commit),
           "half-width English punctuation should remain host pass-through");

    settings.fullShape = true;
    expect(TryDirectOutputKey('A', false, settings, &commit) && commit == u8"ａ",
           "full-width lowercase output transform failed");
    expect(TryDirectOutputKey('A', true, settings, &commit) && commit == u8"Ａ",
           "full-width uppercase output transform failed");
    expect(TryDirectOutputKey(VK_SPACE, false, settings, &commit) && commit == u8"　",
           "full-width space output transform failed");

    expect(TraditionalizeUtf8(u8"汉字") == u8"漢字",
           "Simplified candidate text did not receive the Windows Traditional mapping");
    BrokerUpdate update;
    update.commit = u8"汉字";
    update.candidates.push_back({"candidate", u8"汉字"});
    update.hasSentence = true;
    update.sentence = {"sentence", u8"汉字"};
    ApplyTraditionalization(&update);
    expect(update.commit == u8"漢字" && update.candidates[0].text == u8"漢字" &&
               update.sentence.text == u8"漢字",
           "Traditional output was not kept consistent across UI and commit fields");
}

void testBrokerEndpoint() {
    using namespace yime::experiment;
    wchar_t previous[512]{};
    const DWORD previousLength = GetEnvironmentVariableW(
        L"YIME_TEXTSERVICE_EXPERIMENT_PIPE", previous, static_cast<DWORD>(std::size(previous)));
    SetEnvironmentVariableW(L"YIME_TEXTSERVICE_EXPERIMENT_PIPE", nullptr);
    expect(ResolveBrokerPipeName() == kDefaultBrokerPipe,
           "ordinary installed hosts must have a stable default Broker endpoint");
    constexpr wchar_t custom[] = L"\\\\.\\pipe\\YimeBroker.Contract.Override";
    SetEnvironmentVariableW(L"YIME_TEXTSERVICE_EXPERIMENT_PIPE", custom);
    expect(ResolveBrokerPipeName() == custom, "test/supervisor Broker endpoint override was ignored");
    if (previousLength > 0 && previousLength < std::size(previous)) {
        SetEnvironmentVariableW(L"YIME_TEXTSERVICE_EXPERIMENT_PIPE", previous);
    } else {
        SetEnvironmentVariableW(L"YIME_TEXTSERVICE_EXPERIMENT_PIPE", nullptr);
    }
}

void testCandidateElement() {
    auto* candidates = new CandidateListUIElement();
    std::vector<yime::experiment::BrokerCandidate> values;
    for (int index = 0; index < 10; ++index) {
        values.push_back({"candidate-" + std::to_string(index), index == 0 ? "秋" : "候选"});
    }
    candidates->Update(nullptr, values);
    UINT count = 0;
    expect(candidates->GetCount(&count) == S_OK && count == 9, "candidate list must be capped at nine Shift ordinals");
    UINT selection = 99;
    expect(candidates->GetSelection(&selection) == S_OK && selection == 0, "candidate selection mismatch");
    BSTR first = nullptr;
    expect(candidates->GetString(0, &first) == S_OK && first && std::wstring_view(first) == L"⇧1  秋",
           "candidate display label is not Shift-aware");
    SysFreeString(first);
    BSTR ninth = nullptr;
    expect(candidates->GetString(8, &ninth) == S_OK && ninth && std::wstring_view(ninth).find(L"⇧9") == 0,
           "ninth candidate display label mismatch");
    SysFreeString(ninth);

    yime::experiment::BrokerCandidate sentence{"sentence", "秋候选组成的动态句子"};
    candidates->Update(nullptr, values, 0, "key_sequence", &sentence);
    expect(candidates->GetCount(&count) == S_OK && count == 9,
           "independent sentence row reduced the nine candidate ordinals");
    expect(candidates->SentenceDisplay() == L"句: 秋候选组成的动态句子",
		   "independent sentence row must separate the label from preedit text");
    BSTR firstAlternative = nullptr;
    expect(candidates->GetString(0, &firstAlternative) == S_OK && firstAlternative &&
               std::wstring_view(firstAlternative) == L"⇧1  秋",
           "first candidate below the sentence did not retain Shift+1");
    SysFreeString(firstAlternative);
    selection = 99;
    expect(candidates->GetSelection(&selection) == S_OK && selection == 0,
           "independent sentence row displaced candidate selection");
	const auto exactSentence = values.front();
	candidates->Update(nullptr, values, 0, "key_sequence", &exactSentence);
	expect(candidates->GetCount(&count) == S_OK && count == 9,
		   "sentence equality incorrectly removed the Shift+1 exact candidate");
	firstAlternative = nullptr;
	expect(candidates->GetString(0, &firstAlternative) == S_OK && firstAlternative &&
			   std::wstring_view(firstAlternative) == L"⇧1  秋",
		   "top exact candidate disappeared when it also owned the sentence row");
	SysFreeString(firstAlternative);

    values[0].code = "yjkl";
    values[0].yinyuan = "音元序列";
    values[0].standardPinyin = "qiū";
    for (const auto& annotation : std::array<std::pair<std::string, std::wstring>, 4>{{
             {"key_sequence", L"yjkl"}, {"yinyuan", L"音元序列"},
             {"standard_pinyin", L"qiū"}, {"hidden", L""}}}) {
        candidates->Update(nullptr, values, 0, annotation.first);
        BSTR annotated = nullptr;
        expect(candidates->GetString(0, &annotated) == S_OK && annotated,
               "annotated candidate was unavailable");
        const std::wstring display = annotated ? annotated : L"";
        SysFreeString(annotated);
        if (annotation.second.empty()) {
            expect(display == L"⇧1  秋", "hidden candidate encoding remained visible");
        } else {
            expect(display.find(annotation.second) != std::wstring::npos,
                   "selected candidate encoding was not displayed");
        }
    }
    BSTR invalid = reinterpret_cast<BSTR>(1);
    expect(candidates->GetString(9, &invalid) == E_INVALIDARG && invalid == nullptr,
           "out-of-range candidate was accepted");
    UINT pageCount = 0;
    expect(candidates->GetPageIndex(nullptr, 0, &pageCount) == E_INVALIDARG && pageCount == 1,
           "candidate page count probe mismatch");
    UINT pageIndex = 99;
    expect(candidates->GetPageIndex(&pageIndex, 1, &pageCount) == S_OK && pageCount == 1 && pageIndex == 0,
           "candidate page index mismatch");
    GUID guid{};
    expect(candidates->GetGUID(&guid) == S_OK && IsEqualGUID(guid, GUID_YimeTextServiceExperimentCandidateList),
           "candidate element GUID mismatch");
    expect(candidates->Show(TRUE) == S_OK, "candidate Show failed");
    BOOL shown = FALSE;
    expect(candidates->IsShown(&shown) == S_OK && shown, "candidate shown state mismatch");
    candidates->UpdateEmpty(nullptr, L"无匹配候选，按退格修改");
    count = 0;
    expect(candidates->GetCount(&count) == S_OK && count == 0,
		   "invalid code exposed a synthetic status candidate");
    selection = 99;
    expect(candidates->GetSelection(&selection) == E_FAIL && selection == 0,
           "empty-result status row must not become a selectable candidate");
	expect(candidates->StatusDisplay() == L"无匹配候选，按退格修改",
		   "empty-result status message was discarded");
    candidates->Release();
}

void testOwnedCandidatePopup() {
    CandidatePopup popup;
    expect(popup.FontPoints() == 12, "candidate popup medium font is not 12 points");
    popup.SetFontPoints(10);
    expect(popup.FontPoints() == 10, "candidate popup small font was rejected");
    popup.SetFontPoints(16);
    expect(popup.FontPoints() == 16, "candidate popup large font was rejected");
    popup.SetFontPoints(99);
    expect(popup.FontPoints() == 12, "candidate popup invalid font did not return to medium");
    popup.SetUseYinyuanFont(true);
    expect(popup.UsesYinyuanFont(), "candidate popup did not select the Yinyuan font");
    popup.SetUseYinyuanFont(false);
    expect(!popup.UsesYinyuanFont(), "candidate popup did not restore the UI font");
       popup.SetHorizontal(true);
       expect(popup.IsHorizontal(), "candidate popup did not select horizontal layout");
       popup.SetHorizontal(false);
    unsigned selected = 0;
    popup.SetSelectionHandler([](void* context, unsigned ordinal) noexcept {
        *static_cast<unsigned*>(context) = ordinal;
    }, &selected);
       bool selectedSentence = false;
       popup.SetSentenceHandler([](void* context) noexcept {
              *static_cast<bool*>(context) = true;
       }, &selectedSentence);
    std::array<int, 2> selectedSegment{-1, -1};
    popup.SetSegmentHandler([](void* context, int start, int end) noexcept {
        *static_cast<std::array<int, 2>*>(context) = {start, end};
    }, &selectedSegment);
       std::array<int, 2> expandedSegment{-1, -1};
       popup.SetSegmentExpandHandler([](void* context, int start, int end) noexcept {
              *static_cast<std::array<int, 2>*>(context) = {start, end};
       }, &expandedSegment);
    std::vector<std::wstring> candidates;
    for (int index = 1; index <= 10; ++index) {
        candidates.push_back(L"⇧" + std::to_wstring(index) + L"  候选");
    }
    RECT anchor{GetSystemMetrics(SM_CXSCREEN) - 5, GetSystemMetrics(SM_CYSCREEN) - 5,
                GetSystemMetrics(SM_CXSCREEN) - 4, GetSystemMetrics(SM_CYSCREEN) - 4};
    expect(popup.Update(candidates, anchor, nullptr), "owned candidate popup update failed");
    popup.Show(true);
    const HWND window = popup.Window();
    expect(window && IsWindow(window), "owned candidate popup window missing");
    expect(popup.Count() == 9, "owned candidate popup exceeded Shift ordinal count");
    expect((GetWindowLongPtrW(window, GWL_EXSTYLE) & (WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW)) ==
               (WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW),
           "owned candidate popup can activate or enters the taskbar");
    expect(IsWindowVisible(window), "owned candidate popup did not become visible");
    SendMessageW(window, WM_LBUTTONUP, 0, MAKELPARAM(20, 10));
    expect(selected == 1, "owned candidate popup did not route the first mouse row");
    selected = 0;
    SendMessageW(window, WM_LBUTTONUP, 0, MAKELPARAM(1, 1));
    expect(selected == 0, "owned candidate popup accepted a border click");
       const std::wstring emptyStatus = L"无匹配候选，按退格修改";
       selected = 0;
       expect(popup.Update({}, anchor, nullptr, false, 0, nullptr, -1, -1, &emptyStatus),
                 "owned candidate popup rejected empty-result status");
       expect(popup.RowCount() == 1, "empty-result status did not occupy one independent row");
       SendMessageW(window, WM_LBUTTONUP, 0, MAKELPARAM(20, 10));
       expect(selected == 0, "empty-result status became a selectable candidate");

    popup.SetHorizontal(true);
    expect(popup.Update({L"⇧1  甲", L"⇧2  乙"}, anchor, nullptr),
           "horizontal candidate popup update failed");
    expect(popup.RowCount() == 1, "horizontal candidates were not kept on one row");
    RECT horizontalClient{};
    GetClientRect(window, &horizontalClient);
    selected = 0;
    SendMessageW(window, WM_LBUTTONUP, 0,
                 MAKELPARAM(horizontalClient.right - 10, horizontalClient.bottom / 2));
    expect(selected == 2, "horizontal candidate popup did not route the second cell");
    popup.SetHorizontal(false);

    const RECT centeredAnchor{100, 100, 101, 101};
    yime::experiment::BrokerCandidate editableSentence{"sentence", "甲丙"};
    editableSentence.segments = {{0, 2, "甲", "ab"}, {2, 4, "丙", "cd"}};
       expect(popup.Update({L"⇧1  甲  ab", L"⇧2  乙  ab"}, centeredAnchor, nullptr,
                        false, 0, &editableSentence, 0, 2),
           "owned sentence popup update failed");
    popup.Show(true);
    selected = 0;
    const int textColumnLeft = popup.TextColumnLeft();
    SendMessageW(window, WM_LBUTTONDOWN, 0, MAKELPARAM(textColumnLeft - 1, 10));
    SendMessageW(window, WM_LBUTTONUP, 0, MAKELPARAM(textColumnLeft - 1, 10));
    expect(selectedSentence, "sentence label did not route whole-sentence selection");
    expect(selected == 0 && selectedSegment == std::array<int, 2>{-1, -1},
           "sentence label leaked into candidate or segment selection");
    SendMessageW(window, WM_LBUTTONDOWN, 0, MAKELPARAM(textColumnLeft, 10));
    SendMessageW(window, WM_LBUTTONUP, 0, MAKELPARAM(textColumnLeft, 10));
    expect(selectedSegment == std::array<int, 2>{0, 2},
           "sentence row did not route the clicked editable segment span");
    SendMessageW(window, WM_LBUTTONDBLCLK, 0, MAKELPARAM(textColumnLeft, 10));
    expect(expandedSegment == std::array<int, 2>{0, 2},
           "sentence row did not route the double-clicked segment for expansion");
    RECT client{};
    GetClientRect(window, &client);
    const int sentenceRowHeight = (client.bottom - 16) / static_cast<int>(popup.RowCount());
    selected = 0;
    SendMessageW(window, WM_LBUTTONUP, 0,
                 MAKELPARAM(20, 8 + sentenceRowHeight + sentenceRowHeight / 2));
    expect(selected == 1, "first candidate below the independent sentence lost Shift ordinal one");

       yime::experiment::BrokerCandidate wholeWord{"whole-word", "本地", "abcdef"};
    selected = 0;
    selectedSegment = {-1, -1};
    expect(popup.Update({}, centeredAnchor, nullptr, false, 0,
                        &wholeWord, -1, -1),
           "whole system-word sentence popup update failed");
    expect(popup.RowCount() == 1, "whole system word was duplicated below its sentence row");
       SendMessageW(window, WM_LBUTTONDOWN, 0, MAKELPARAM(popup.TextColumnLeft(), 10));
       SendMessageW(window, WM_LBUTTONUP, 0, MAKELPARAM(popup.TextColumnLeft(), 10));
       expect(selectedSegment == std::array<int, 2>{0, 6},
           "whole system-word sentence row did not request recursive expansion");
    expect(selected == 0, "whole system-word sentence row leaked into candidate ordinal selection");

    expect(popup.Update({L"⇧1  甲  ab"}, centeredAnchor, nullptr),
           "short three-part candidate popup update failed");
    const LONG shortCandidateWidth = popup.Bounds().right - popup.Bounds().left;
    expect(popup.Update({L"⇧1  很长的候选字词  very-long-key-sequence"}, centeredAnchor, nullptr),
           "long three-part candidate popup update failed");
    const LONG fullCandidateWidth = popup.Bounds().right - popup.Bounds().left;
    expect(fullCandidateWidth > shortCandidateWidth,
           "candidate label, word, annotation and their gaps did not drive popup width");
    yime::experiment::BrokerCandidate longSentence{"long-sentence", "这是一个明显长于普通候选默认宽度的动态组句结果"};
    longSentence.segments = {{0, 1, "这是一个明显长于普通候选默认宽度的动态组句结果", "ab"}};
    expect(popup.Update({L"⇧1  甲  ab"}, centeredAnchor, nullptr, false, 0,
                        &longSentence, 0, 1),
           "long sentence popup update failed");
    const LONG sentenceWidth = popup.Bounds().right - popup.Bounds().left;
    expect(sentenceWidth > shortCandidateWidth,
           "dynamic sentence row did not expand popup beyond candidate width");
    const RECT bounds = popup.Bounds();
    HMONITOR monitor = MonitorFromRect(&centeredAnchor, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    expect(GetMonitorInfoW(monitor, &info) != FALSE, "popup monitor work area unavailable");
    expect(bounds.left >= info.rcWork.left && bounds.top >= info.rcWork.top &&
               bounds.right <= info.rcWork.right && bounds.bottom <= info.rcWork.bottom,
           "owned candidate popup escaped the monitor work area");
    popup.Show(false);
    expect(!IsWindowVisible(window), "owned candidate popup did not hide");
    popup.Destroy();
    expect(!IsWindow(window), "owned candidate popup did not destroy its HWND");
}

void testExperimentSettings() {
    using namespace yime::experiment;
    const auto missing = LoadExperimentSettings(L"Z:\\missing-yimecore-experiment-settings.json");
    expect(missing.mode == "variable", "experiment default mode is not variable");
    expect(missing.candidateFontPreset == "medium" && missing.candidateFontPoints == 12,
           "experiment medium font default is not 12 points");
    expect(missing.candidateAnnotation == "key_sequence",
           "experiment candidate encoding default is not key sequence");
    expect(missing.candidatePageSize == 5 && missing.candidateLayout == "vertical",
           "experiment candidate count/layout defaults do not match the production UI");

    const std::wstring path = temporaryStatePath(L"settings.json");
    DeleteFileW(path.c_str());
    ExperimentSettings updated;
    expect(ApplyExperimentSettingsCommand(ExperimentSettingsCommand::English, path, &updated) &&
               updated.asciiMode && updated.revision > 0,
           "language-bar state update did not persist English mode atomically");
    const auto englishRevision = updated.revision;
    expect(ApplyExperimentSettingsCommand(ExperimentSettingsCommand::ModeFull, path, &updated) &&
               updated.asciiMode && updated.mode == "full" && updated.revision > englishRevision,
           "single-field language-bar update overwrote another trial setting");
    DeleteFileW(path.c_str());
}

void testLanguageBarItem() {
    using namespace yime::experiment;
    const std::wstring path = temporaryStatePath(L"language-bar.json");
    DeleteFileW(path.c_str());
    ExperimentSettings initial;
    expect(ApplyExperimentSettingsCommand(ExperimentSettingsCommand::Chinese, path, &initial),
           "could not seed language-bar state");
    bool popupSeen = false;
    UINT launchedTool = 0;
    auto* item = new LanguageBarItem(path, selectChineseFromPopup, &popupSeen,
                                     recordToolLaunch, &launchedTool);
    TF_LANGBARITEMINFO info{};
    expect(item->GetInfo(&info) == S_OK, "language bar GetInfo failed");
    expect(IsEqualGUID(info.clsidService, CLSID_YimeTextServiceExperiment), "language bar service CLSID mismatch");
    expect(IsEqualGUID(info.guidItem, GUID_YimeTextServiceExperimentLangBar), "language bar item GUID mismatch");
    expect((info.dwStyle & TF_LBI_STYLE_BTN_BUTTON) != 0 &&
               (info.dwStyle & TF_LBI_STYLE_SHOWNINTRAY) == 0,
           "input-mode button must match the PIME-compatible taskbar style");
    expect(std::wstring_view(info.szDescription) == L"中",
           "Chinese mode must replace the host CH label with 中");
    DWORD status = ~DWORD{0};
    expect(item->GetStatus(&status) == S_OK && status == 0, "language bar initial status mismatch");
    expect(item->Show(FALSE) == S_OK && item->GetStatus(&status) == S_OK &&
               (status & TF_LBI_STATUS_HIDDEN) != 0,
           "language bar hide state mismatch");
    expect(item->Show(TRUE) == S_OK && item->GetStatus(&status) == S_OK &&
               (status & TF_LBI_STATUS_HIDDEN) == 0,
           "language bar show state mismatch");
    HICON icon = nullptr;
    expect(item->GetIcon(&icon) == S_OK && icon,
           "docked taskbar language bar did not receive the Chinese mode icon");
    DestroyIcon(icon);
    BSTR text = nullptr;
    expect(item->GetText(&text) == S_OK && text && std::wstring_view(text) == L"中",
           "language bar Chinese text mismatch");
    SysFreeString(text);
    expect(item->InitMenu(nullptr) == E_POINTER,
           "language bar menu path must validate the host ITfMenu callback");

    auto* menu = new FakeMenu();
       expect(item->InitMenu(menu) == S_OK && menu->entries.size() == 16,
           "host right-click path did not build the complete trial menu");
    expect(menu->entries[3].text == L"输入方案" && menu->entries[3].submenu &&
               menu->entries[3].submenu->entries.size() == 3,
           "input scheme cascade is missing");
    expect(menu->entries[4].text == L"候选字号" && menu->entries[4].submenu &&
               menu->entries[4].submenu->entries.size() == 3,
           "candidate font cascade is missing");
    expect(menu->entries[5].text == L"显示编码" && menu->entries[5].submenu &&
               menu->entries[5].submenu->entries.size() == 4,
           "candidate annotation cascade is missing");
    expect(menu->entries[6].text == L"标点样式" && menu->entries[6].submenu &&
               menu->entries[6].submenu->entries.size() == 2 &&
               menu->entries[6].submenu->entries[0].id == YIME_LBI_PUNCTUATION_CHINESE &&
               menu->entries[6].submenu->entries[1].id == YIME_LBI_PUNCTUATION_ENGLISH,
           "Chinese/English punctuation cascade is missing");
    expect(menu->entries[7].text == L"字符宽度" && menu->entries[7].submenu &&
               menu->entries[7].submenu->entries.size() == 2 &&
               menu->entries[7].submenu->entries[0].id == YIME_LBI_SHAPE_HALF &&
               menu->entries[7].submenu->entries[1].id == YIME_LBI_SHAPE_FULL,
           "half/full-width cascade is missing");
    expect(menu->entries[8].text == L"汉字字形" && menu->entries[8].submenu &&
               menu->entries[8].submenu->entries.size() == 2 &&
               menu->entries[8].submenu->entries[0].id == YIME_LBI_SCRIPT_SIMPLIFIED &&
               menu->entries[8].submenu->entries[1].id == YIME_LBI_SCRIPT_TRADITIONAL,
           "simplified/traditional cascade is missing");
    expect((menu->entries[9].flags & TF_LBMENUF_SEPARATOR) != 0,
           "tool commands are not separated from composition settings");
       expect(menu->entries[10].id == YIME_LBI_INPUT_TOOLBAR &&
                        menu->entries[10].text == L"输入法工具栏" &&
               (menu->entries[10].flags & TF_LBMENUF_CHECKED) == 0,
                 "input toolbar must be present and default off");
    expect(menu->entries[11].id == YIME_LBI_REVERSE_LOOKUP &&
               menu->entries[11].text == L"反查编码",
           "reverse-lookup host click path is missing");
    expect(menu->entries[12].id == YIME_LBI_USER_LEXICON &&
               menu->entries[12].text == L"用户词库",
           "user-lexicon host click path is missing");
       expect(menu->entries[13].id == YIME_LBI_TRAINER_TOOL &&
                        menu->entries[13].text == L"指法练习",
                 "trainer host click path is missing");
       expect(menu->entries[14].id == YIME_LBI_TOOL_CENTER &&
                        menu->entries[14].text == L"工具中心",
                 "tool-center host click path is missing");
       expect(menu->entries[15].id == YIME_LBI_SETTINGS_TOOL &&
                        menu->entries[15].text == L"设置工具",
           "settings-tool host click path is missing");
    menu->Release();

    FakeLanguageBarSink sink;
    ITfSource* source = nullptr;
    expect(item->QueryInterface(__uuidof(ITfSource), reinterpret_cast<void**>(&source)) == S_OK && source,
           "language bar does not expose ITfSource updates");
    DWORD cookie = 0;
    expect(source && source->AdviseSink(__uuidof(ITfLangBarItemSink), &sink, &cookie) == S_OK,
           "language bar sink subscription failed");
    expect(item->OnClick(TF_LBI_CLK_LEFT, {}, nullptr) == S_OK,
           "desktop language-bar left click did not toggle to English");
    text = nullptr;
    expect(item->GetText(&text) == S_OK && text && std::wstring_view(text) == L"英",
           "English mode must replace the host EN label with 英");
    SysFreeString(text);
    icon = nullptr;
    expect(item->GetIcon(&icon) == S_OK && icon,
           "docked taskbar language bar did not receive the English mode icon");
    DestroyIcon(icon);
    expect((sink.updates & (TF_LBI_TEXT | TF_LBI_ICON)) == (TF_LBI_TEXT | TF_LBI_ICON),
           "English toggle did not notify the host text and icon slots");
    expect(item->OnClick(TF_LBI_CLK_RIGHT, {}, nullptr) == S_OK && popupSeen,
           "docked taskbar right click did not route through the cascading popup");
    expect(!LoadExperimentSettings(path).asciiMode,
           "taskbar popup command did not switch back to Chinese");
    expect(item->OnMenuSelect(YIME_LBI_MODE_FULL) == S_OK &&
               LoadExperimentSettings(path).mode == "full",
           "host submenu click did not persist the requested trial mode");
    expect(item->OnMenuSelect(YIME_LBI_PUNCTUATION_CHINESE) == S_OK &&
               !LoadExperimentSettings(path).asciiPunctuation,
           "host submenu click did not select Chinese punctuation");
    expect(item->OnMenuSelect(YIME_LBI_SHAPE_FULL) == S_OK &&
               LoadExperimentSettings(path).fullShape,
           "host submenu click did not select full-width output");
    expect(item->OnMenuSelect(YIME_LBI_SCRIPT_TRADITIONAL) == S_OK &&
               LoadExperimentSettings(path).traditionalization,
           "host submenu click did not select Traditional output");
    for (const UINT command : {YIME_LBI_INPUT_TOOLBAR, YIME_LBI_REVERSE_LOOKUP,
                               YIME_LBI_USER_LEXICON, YIME_LBI_TRAINER_TOOL,
                               YIME_LBI_TOOL_CENTER, YIME_LBI_SETTINGS_TOOL}) {
        launchedTool = 0;
        expect(item->OnMenuSelect(command) == S_OK && launchedTool == command,
               "language-bar tool command did not reach its exact launcher path");
    }
    expect(item->OnMenuSelect(1) == E_INVALIDARG,
           "language bar accepted an unknown host command ID");
    const auto eventPath = std::filesystem::path(path).parent_path() / L"evidence" /
                           L"language-bar-events.jsonl";
    std::ifstream eventInput(eventPath, std::ios::binary);
    const std::string eventText((std::istreambuf_iterator<char>(eventInput)),
                                std::istreambuf_iterator<char>());
    expect(eventText.find("\"event\":\"init_menu\"") != std::string::npos &&
               eventText.find("\"event\":\"left_click\"") != std::string::npos &&
               eventText.find("\"event\":\"right_click_open\"") != std::string::npos &&
               eventText.find("\"event\":\"menu_select\"") != std::string::npos,
           "language-bar host callbacks were not captured in the live evidence stream");
    if (source) {
        expect(source->UnadviseSink(cookie) == S_OK, "language bar sink unsubscribe failed");
        source->Release();
    }
    item->Release();
    DeleteFileW(path.c_str());
    std::error_code cleanupError;
    std::filesystem::remove(eventPath, cleanupError);
}

void testComLifecycle(const wchar_t* dllPath) {
    HMODULE module = LoadLibraryW(dllPath);
    expect(module != nullptr, "could not load experiment DLL");
    if (!module) return;
    const auto getClassObject = reinterpret_cast<GetClassObject>(GetProcAddress(module, "DllGetClassObject"));
    const auto canUnload = reinterpret_cast<CanUnloadNow>(GetProcAddress(module, "DllCanUnloadNow"));
    expect(getClassObject != nullptr && canUnload != nullptr, "required COM exports missing");
    expect(GetProcAddress(module, "DllRegisterServer") == nullptr,
           "E6-B1 DLL must not expose self-registration");
    if (!getClassObject || !canUnload) {
        FreeLibrary(module);
        return;
    }
    expect(canUnload() == S_OK, "fresh DLL must be unloadable");
    GUID wrong = CLSID_YimeTextServiceExperiment;
    ++wrong.Data1;
    void* unavailable = nullptr;
    expect(getClassObject(wrong, IID_IClassFactory, &unavailable) == CLASS_E_CLASSNOTAVAILABLE && unavailable == nullptr,
           "wrong CLSID was not rejected");

    IClassFactory* factory = nullptr;
    expect(SUCCEEDED(getClassObject(CLSID_YimeTextServiceExperiment, IID_IClassFactory,
                                    reinterpret_cast<void**>(&factory))) && factory,
           "class factory creation failed");
    expect(canUnload() == S_FALSE, "live factory not reflected by DllCanUnloadNow");
    if (factory) {
        ITfTextInputProcessorEx* processor = nullptr;
        expect(SUCCEEDED(factory->CreateInstance(nullptr, __uuidof(ITfTextInputProcessorEx),
                                                 reinterpret_cast<void**>(&processor))) && processor,
               "ITfTextInputProcessorEx creation failed");
        IUnknown* aggregateProbe = reinterpret_cast<IUnknown*>(1);
        expect(factory->CreateInstance(reinterpret_cast<IUnknown*>(factory), IID_IUnknown,
                                       reinterpret_cast<void**>(&aggregateProbe)) == CLASS_E_NOAGGREGATION && aggregateProbe == nullptr,
               "aggregation was not rejected");
        if (processor) {
            ITfKeyEventSink* keySink = nullptr;
            expect(SUCCEEDED(processor->QueryInterface(__uuidof(ITfKeyEventSink),
                                                       reinterpret_cast<void**>(&keySink))) && keySink,
                   "ITfKeyEventSink query failed");
            expect(processor->ActivateEx(nullptr, TF_CLIENTID_NULL, 0) == E_INVALIDARG,
                   "invalid activation parameters were accepted");
            if (keySink) {
                BOOL eaten = TRUE;
                expect(keySink->OnTestKeyDown(nullptr, '1', 0, &eaten) == S_OK && eaten == FALSE,
                       "inert B1 shell swallowed a key");
                keySink->Release();
            }
            processor->Release();
        }
        for (int iteration = 0; iteration < 1000; ++iteration) {
            IUnknown* repeated = nullptr;
            const HRESULT createResult = factory->CreateInstance(nullptr, IID_IUnknown,
                                                                  reinterpret_cast<void**>(&repeated));
            expect(SUCCEEDED(createResult) && repeated, "repeated COM creation failed");
            if (repeated) repeated->Release();
        }
        factory->Release();
    }
    expect(canUnload() == S_OK, "released COM graph is not unloadable");
    FreeLibrary(module);
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    if (argc != 2) {
        std::cerr << "usage: YimeTextServiceContractTests <dll>\n";
        return 2;
    }
    testKeyContract();
    testOutputTransformContract();
    testBrokerEndpoint();
    testCandidateElement();
    testOwnedCandidatePopup();
    testExperimentSettings();
    testLanguageBarItem();
    testComLifecycle(argv[1]);
    if (failures != 0) return 1;
    std::cout << "YimeTextService E6-B1 contracts passed\n";
    return 0;
}
