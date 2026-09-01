#include <windows.h>
#include <msctf.h>

#include <iostream>
#include <atomic>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

#include "KeyContract.h"
#include "BrokerClient.h"
#include "BrokerEndpoint.h"
#include "CandidateListUIElement.h"
#include "CandidatePopup.h"
#include "CompositionEditSession.h"
#include "ExperimentSettings.h"
#include "LanguageBarItem.h"
#include "OutputTransform.h"
#include "PunctuationPalette.h"
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
		if (unadviseOnUpdate && source) {
			unadviseOnUpdate = false;
			source->UnadviseSink(cookie);
		}
        return S_OK;
    }
    DWORD updates = 0;
    unsigned count = 0;
	ITfSource* source = nullptr;
	DWORD cookie = 0;
	bool unadviseOnUpdate = false;

private:
    std::atomic<ULONG> references_{1};
};

bool waitForLanguageBarUpdate(FakeLanguageBarSink& sink, DWORD flags, DWORD timeoutMs = 1000) {
       const ULONGLONG deadline = GetTickCount64() + timeoutMs;
       while ((sink.updates & flags) != flags && GetTickCount64() < deadline) {
              MSG message{};
              while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
                     TranslateMessage(&message);
                     DispatchMessageW(&message);
              }
              Sleep(10);
       }
       return (sink.updates & flags) == flags;
}

UINT toggleDefaultLanguageFromPopup(HMENU menu, POINT, void* context) noexcept {
    auto* seen = static_cast<bool*>(context);
       *seen = menu && GetMenuItemCount(menu) == 12 && GetSubMenu(menu, 2) &&
                     GetSubMenu(menu, 3) && GetSubMenu(menu, 4);
       return YIME_LBI_DEFAULT_LANGUAGE;
}

bool recordToolLaunch(UINT command, const std::wstring&, void* context) noexcept {
    *static_cast<UINT*>(context) = command;
    return true;
}

bool recordRuntimeEnsure(const std::wstring&, void* context) noexcept {
    ++*static_cast<int*>(context);
    // Runtime recovery is best-effort: a development host with an externally
    // supplied Broker must still be allowed to persist its output setting.
    return false;
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
           "Shift+0 must remain available for its punctuation-layer physical position");
    expect(ClassifyVirtualKey(VK_OEM_5, false).route == KeyRoute::AppendComposition,
           "base backslash must remain a composition key");
    expect(ClassifyVirtualKey(VK_OEM_5, true).route == KeyRoute::OpenPunctuationPalette,
           "Shift+backslash must open the punctuation palette");
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
          expect(shiftTap.OnKeyDown(VK_SHIFT) && !shiftTap.OnKeyDown(VK_OEM_5) &&
                !shiftTap.OnKeyUp(VK_SHIFT),
            "punctuation leader incorrectly triggered the Shift language toggle");
    const auto& labels = CandidateLabels();
    constexpr std::wstring_view expected[] = {L"⇧1", L"⇧2", L"⇧3", L"⇧4", L"⇧5", L"⇧6", L"⇧7", L"⇧8", L"⇧9"};
    for (size_t index = 0; index < labels.size(); ++index) {
        expect(labels[index] == expected[index], "candidate label lost Shift marker");
    }
}

void testPunctuationPaletteContract() {
    using namespace yime::experiment;
    PunctuationPalette palette;
    palette.Open(false, false, "candidate-1");
    expect(palette.IsActive() && palette.FrozenCandidateId() == "candidate-1",
           "punctuation palette did not freeze the commit target");
    const std::vector<std::string> expectedFirst = {
              u8"！", u8"＠", u8"＃", u8"￥", u8"％", u8"……", u8"＆", u8"＊", u8"（",
       };
       const std::vector<std::string> expectedFirstIds = {
              "digit-1", "digit-2", "digit-3", "digit-4", "digit-5",
              "digit-6", "digit-7", "digit-8", "digit-9",
    };
    expect(palette.Candidates().size() == 9,
           "punctuation first page must ignore the lexical candidate page size");
    for (size_t index = 0; index < expectedFirst.size() && index < palette.Candidates().size(); ++index) {
        expect(palette.Candidates()[index].id == "punct:zh:" + expectedFirstIds[index] &&
                   palette.Candidates()[index].text == expectedFirst[index],
               "punctuation first page lost its physical shifted-digit ordering");
    }
    auto decision = palette.Preview('1', true, false, false);
    expect(decision.route == PunctuationRoute::SelectOrdinal && decision.ordinal == 1,
           "Shift+1 did not remain an ordinal selection inside the punctuation palette");
    std::string output;
    expect(palette.Resolve(decision, &output) && output == u8"！",
           "punctuation ordinal did not resolve the matching keycap symbol");
    decision = palette.Preview('0', true, false, false);
    expect(decision.route == PunctuationRoute::DirectCommit && decision.commit == u8"）",
           "Shift+0 did not preserve the closing parenthesis at its physical position");
    decision = palette.Preview(VK_OEM_5, true, false, false);
    expect(decision.route == PunctuationRoute::Cancel,
           "repeated Shift+backslash did not cancel the punctuation palette");
    decision = palette.Preview(VK_OEM_COMMA, false, false, false);
    expect(decision.route == PunctuationRoute::DirectCommit && decision.commit == u8"，",
           "comma did not use its original physical key in punctuation mode");
    decision = palette.Preview(VK_OEM_COMMA, true, false, false);
    expect(decision.route == PunctuationRoute::DirectCommit && decision.commit == u8"《",
           "Shift+comma did not use its original title-mark key");
    decision = palette.Preview(VK_OEM_5, false, false, false);
    expect(decision.route == PunctuationRoute::DirectCommit && decision.commit == u8"、",
           "base backslash did not provide the enumeration comma inside the explicit palette");
    struct DirectPunctuationCase {
        WPARAM key;
        bool shifted;
        const char* expected;
    };
    const std::array<DirectPunctuationCase, 21> directPunctuationCases = {{
        {VK_OEM_3, false, u8"｀"}, {VK_OEM_3, true, u8"～"},
        {VK_OEM_MINUS, false, u8"－"}, {VK_OEM_MINUS, true, u8"——"},
        {VK_OEM_PLUS, false, u8"＝"}, {VK_OEM_PLUS, true, u8"＋"},
        {VK_OEM_4, false, u8"「"}, {VK_OEM_4, true, u8"『"},
        {VK_OEM_6, false, u8"」"}, {VK_OEM_6, true, u8"』"},
        {VK_OEM_5, false, u8"、"},
        {VK_OEM_1, false, u8"；"}, {VK_OEM_1, true, u8"："},
        {VK_OEM_7, false, u8"‘"}, {VK_OEM_7, true, u8"“"},
        {VK_OEM_COMMA, false, u8"，"}, {VK_OEM_COMMA, true, u8"《"},
        {VK_OEM_PERIOD, false, u8"。"}, {VK_OEM_PERIOD, true, u8"》"},
        {VK_OEM_2, false, u8"、"}, {VK_OEM_2, true, u8"？"},
    }};
    for (const auto& directCase : directPunctuationCases) {
        const auto direct = palette.Preview(directCase.key, directCase.shifted, false, false);
        expect(direct.route == PunctuationRoute::DirectCommit &&
                   direct.commit == directCase.expected,
               "a punctuation key no longer outputs at its original physical position");
    }
          expect(palette.Preview(VK_OEM_5, true, false, false).route == PunctuationRoute::Cancel &&
                        palette.Preview(VK_ESCAPE, false, false, false).route == PunctuationRoute::Cancel &&
               palette.Preview(VK_BACK, false, false, false).route == PunctuationRoute::Cancel,
           "punctuation palette cancellation keys changed");
    expect(palette.Preview('2', false, false, false).route == PunctuationRoute::Reclassify,
           "base digit stopped returning to the normal composition classifier");
    expect(palette.Preview('C', false, true, false).route == PunctuationRoute::Unrelated,
           "host Ctrl shortcut was captured by the punctuation palette");

    decision = palette.Preview(VK_NEXT, false, false, false);
    expect(decision.route == PunctuationRoute::NextPage && palette.ApplyNavigation(decision) &&
               palette.PageIndex() == 1,
           "punctuation palette did not open its second page");
    const std::vector<std::string> expectedSecond = {
        u8"（", u8"）", u8"“", u8"”", u8"‘", u8"’", u8"《", u8"》", u8"·",
    };
    expect(palette.Candidates().size() == expectedSecond.size(),
           "punctuation second page must expose nine stable ordinals");
    for (size_t index = 0; index < expectedSecond.size() && index < palette.Candidates().size(); ++index) {
        expect(palette.Candidates()[index].text == expectedSecond[index],
               "punctuation second-page ordering changed");
    }
    expect(palette.StatusText() == L"标点（中文） · 2/2",
           "punctuation palette lost its non-selectable page annotation");

    palette.Open(true, false, {});
       const std::vector<std::string> expectedEnglishFirst = {
              "!", "@", "#", "$", "%", "^", "&", "*", "(",
       };
       for (size_t index = 0; index < expectedEnglishFirst.size() && index < palette.Candidates().size(); ++index) {
              expect(palette.Candidates()[index].id == "punct:ascii:digit-" + std::to_string(index + 1) &&
                               palette.Candidates()[index].text == expectedEnglishFirst[index],
                        "half-width English punctuation lost its shifted-digit position");
       }
       decision = palette.Preview('0', true, false, false);
       expect(decision.route == PunctuationRoute::DirectCommit && decision.commit == ")",
                 "half-width English Shift+0 did not preserve its physical position");
    const std::vector<std::string> expectedEnglishSecond = {
        "(", ")", "\"", "'", "<", ">", "[", "]", u8"·",
    };
    expect(palette.ApplyNavigation(palette.Preview(VK_NEXT, false, false, false)),
           "English punctuation palette did not advance");
    for (size_t index = 0; index < expectedEnglishSecond.size() && index < palette.Candidates().size(); ++index) {
        expect(palette.Candidates()[index].text == expectedEnglishSecond[index],
               "English punctuation second-page ordering changed");
    }
    expect(palette.StatusText() == L"标点（英文） · 2/2",
           "English punctuation palette annotation is ambiguous");
    decision = palette.Preview(VK_OEM_COMMA, false, false, false);
    expect(decision.route == PunctuationRoute::DirectCommit && decision.commit == ",",
           "half-width English punctuation did not preserve its physical key output");
    palette.Open(true, true, {});
       const std::vector<std::string> expectedFullWidthFirst = {
              u8"！", u8"＠", u8"＃", u8"＄", u8"％", u8"＾", u8"＆", u8"＊", u8"（",
       };
       for (size_t index = 0; index < expectedFullWidthFirst.size() && index < palette.Candidates().size(); ++index) {
              expect(palette.Candidates()[index].text == expectedFullWidthFirst[index],
                        "full-width English punctuation lost its shifted-digit position");
       }
       decision = palette.Preview('0', true, false, false);
       expect(decision.route == PunctuationRoute::DirectCommit && decision.commit == u8"）",
                 "full-width English Shift+0 did not preserve its physical position");
    decision = palette.Preview(VK_OEM_COMMA, false, false, false);
    expect(decision.route == PunctuationRoute::DirectCommit && decision.commit == u8"，",
           "full-width English punctuation did not follow the shape setting");
    palette.Cancel();
    expect(!palette.IsActive() && palette.FrozenCandidateId().empty(),
           "punctuation palette cancellation retained stale state");
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

void testBrokerPipeTransportLiveness() {
    using namespace yime::experiment;
    const std::wstring pipeName = L"\\\\.\\pipe\\YimeBroker.Transport.Contract." +
                                  std::to_wstring(GetCurrentProcessId()) + L"." +
                                  std::to_wstring(GetTickCount64());
    HANDLE server = CreateNamedPipeW(
        pipeName.c_str(), PIPE_ACCESS_DUPLEX,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT, 1, 4096, 4096, 0, nullptr);
    expect(server != INVALID_HANDLE_VALUE, "could not create transport-liveness test pipe");
    HANDLE client = CreateFileW(pipeName.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                                OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    expect(client != INVALID_HANDLE_VALUE, "could not open transport-liveness test pipe");
    const BOOL connected = ConnectNamedPipe(server, nullptr);
    expect(connected || GetLastError() == ERROR_PIPE_CONNECTED,
           "transport-liveness test pipe did not connect");
    expect(IsBrokerPipeTransportAlive(client),
           "connected Broker transport was reported as stale");

    DisconnectNamedPipe(server);
    CloseHandle(server);
    bool detectedDisconnect = false;
    for (int attempt = 0; attempt < 50; ++attempt) {
        if (!IsBrokerPipeTransportAlive(client)) {
            detectedDisconnect = true;
            break;
        }
        Sleep(10);
    }
    expect(detectedDisconnect,
           "disconnected Broker transport was reported as live after server restart");
    CloseHandle(client);
}

void testBrokerPipeSecurityAndTimeouts() {
    using namespace yime::experiment;
    const DWORD flags = BrokerPipeClientOpenFlags();
    expect((flags & FILE_FLAG_OVERLAPPED) != 0,
           "Broker client pipe is not opened for cancellable overlapped I/O");
    expect((flags & SECURITY_SQOS_PRESENT) != 0 && (flags & SECURITY_IDENTIFICATION) != 0,
           "Broker client pipe does not cap a server at identification impersonation");

    const std::wstring pipeName = L"\\\\.\\pipe\\YimeBroker.Timeout.Contract." +
                                  std::to_wstring(GetCurrentProcessId()) + L"." +
                                  std::to_wstring(GetTickCount64());
    HANDLE server = CreateNamedPipeW(
        pipeName.c_str(), PIPE_ACCESS_DUPLEX,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT, 1, 4096, 4096, 0, nullptr);
    expect(server != INVALID_HANDLE_VALUE, "could not create Broker timeout test pipe");
    if (server == INVALID_HANDLE_VALUE) return;
    std::atomic<int> impersonationLevel{-1};
    std::thread stalledServer([&] {
        const BOOL connected = ConnectNamedPipe(server, nullptr);
        if (!connected && GetLastError() != ERROR_PIPE_CONNECTED) return;
        if (ImpersonateNamedPipeClient(server)) {
            HANDLE token = nullptr;
            if (OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &token)) {
                SECURITY_IMPERSONATION_LEVEL level = SecurityAnonymous;
                DWORD returned = 0;
                if (GetTokenInformation(token, TokenImpersonationLevel, &level,
                                        sizeof(level), &returned)) {
                    impersonationLevel.store(static_cast<int>(level));
                }
                CloseHandle(token);
            }
            RevertToSelf();
        }
        char request[4096]{};
        DWORD read = 0;
        ReadFile(server, request, sizeof(request), &read, nullptr);
        Sleep(400);
        DisconnectNamedPipe(server);
    });
    BrokerClient client;
    std::string error;
    const auto started = std::chrono::steady_clock::now();
    const bool connected = client.Connect(pipeName, 100, "variable", 9, &error);
    const auto elapsed = std::chrono::steady_clock::now() - started;
    expect(!connected && error.find("timeout") != std::string::npos,
           "stalled Broker open did not fail with a timeout");
    expect(elapsed < std::chrono::seconds(1),
           "stalled Broker open blocked the host beyond its deadline");
    stalledServer.join();
    expect(impersonationLevel.load() == static_cast<int>(SecurityIdentification),
           "spoofed Broker server obtained a client token above Identification level");
    CloseHandle(server);

    const std::wstring closePipeName = L"\\\\.\\pipe\\YimeBroker.CloseTimeout.Contract." +
                                       std::to_wstring(GetCurrentProcessId()) + L"." +
                                       std::to_wstring(GetTickCount64());
    server = CreateNamedPipeW(
        closePipeName.c_str(), PIPE_ACCESS_DUPLEX,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT, 1, 4096, 4096, 0, nullptr);
    expect(server != INVALID_HANDLE_VALUE, "could not create Broker close-timeout test pipe");
    if (server == INVALID_HANDLE_VALUE) return;
    std::thread closeServer([&] {
        const BOOL accepted = ConnectNamedPipe(server, nullptr);
        if (!accepted && GetLastError() != ERROR_PIPE_CONNECTED) return;
        char request[4096]{};
        DWORD read = 0;
        if (!ReadFile(server, request, sizeof(request), &read, nullptr)) return;
        constexpr char response[] =
            "{\"version\":1,\"sequence\":1,\"session_id\":\"contract-session\","
            "\"result\":{\"state\":{}}}\n";
        DWORD written = 0;
        if (!WriteFile(server, response, static_cast<DWORD>(sizeof(response) - 1),
                       &written, nullptr)) return;
        ReadFile(server, request, sizeof(request), &read, nullptr);
        Sleep(400);
        DisconnectNamedPipe(server);
    });
    error.clear();
    expect(client.Connect(closePipeName, 100, "variable", 9, &error),
           "fake Broker did not complete the close-timeout setup handshake");
    const auto closeStarted = std::chrono::steady_clock::now();
    client.Close();
    const auto closeElapsed = std::chrono::steady_clock::now() - closeStarted;
    expect(closeElapsed < std::chrono::seconds(1),
           "Broker Close blocked COM deactivation beyond its deadline");
    closeServer.join();
    CloseHandle(server);
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
    yime::experiment::PunctuationPalette palette;
    palette.Open(false, false, {});
    candidates->UpdatePalette(nullptr, palette.Candidates(), palette.SelectedIndex(),
                              palette.StatusText(), palette.Description());
    count = 0;
    expect(candidates->GetCount(&count) == S_OK && count == 9 &&
               candidates->StatusDisplay() == L"标点（中文） · 1/2",
           "local punctuation palette did not expose nine selectable rows plus a status annotation");
    BSTR description = nullptr;
    expect(candidates->GetDescription(&description) == S_OK && description &&
               std::wstring_view(description) == L"Yime 标点（中文）第 1 页",
           "host-rendered punctuation palette description is ambiguous");
    SysFreeString(description);
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
       const std::wstring settingsPath = temporaryStatePath(L"candidate-popup-font-settings.json");
       auto replaceDisplaySettings = [&](const char* preset, const char* family,
                                          const char* annotation, const char* layout,
                                          bool traditionalization, std::int64_t revision) {
              const std::wstring temporaryPath = settingsPath + L".tmp";
              DeleteFileW(temporaryPath.c_str());
              {
                     std::ofstream output(std::filesystem::path(temporaryPath),
                                                         std::ios::binary | std::ios::trunc);
                     output << R"({"version":1,"candidate_font_preset":")" << preset
                               << R"(","candidate_font_family":")" << family
                               << R"(","candidate_annotation":")" << annotation
                               << R"(","candidate_layout":")" << layout
                               << R"(","traditionalization":)"
                               << (traditionalization ? "true" : "false")
                               << R"(,"revision":)" << revision << "}\n";
              }
              expect(MoveFileExW(temporaryPath.c_str(), settingsPath.c_str(),
                                             MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != FALSE,
                        "could not atomically replace candidate popup display settings");
       };
       DeleteFileW(settingsPath.c_str());
       replaceDisplaySettings("medium", "Microsoft YaHei UI", "key_sequence",
                              "vertical", false, 1);
       CandidatePopup popup(settingsPath);
    expect(popup.FontPoints() == 12, "candidate popup medium font is not 12 points");
    expect(popup.FontFamily() == L"Microsoft YaHei UI",
           "candidate popup did not retain its current font as the default");
    popup.SetFontFamily(L"system-ui");
    expect(popup.FontFamily() == L"system-ui", "candidate popup rejected the system UI font");
    expect(popup.EffectiveFontFamily() == L"system-ui",
           "candidate popup changed the configured UI font without Yinyuan annotations");
    popup.SetUseYinyuanFont(true);
    expect(popup.UsesYinyuanFont() && popup.EffectiveFontFamily() == L"YinYuan",
           "Yinyuan annotations did not force the private PUA font over the configured UI font");
    popup.SetUseYinyuanFont(false);
    expect(!popup.UsesYinyuanFont() && popup.EffectiveFontFamily() == L"system-ui",
           "candidate popup did not restore the configured UI font after Yinyuan annotations");
    popup.SetFontFamily(L"YinYuan");
    expect(popup.FontFamily() == L"YinYuan" && popup.UsesYinyuanFont() &&
               popup.EffectiveFontFamily() == L"YinYuan",
           "candidate popup rejected the explicit Yinyuan font option");
    popup.SetFontFamily(L"unsupported");
    expect(popup.FontFamily() == L"Microsoft YaHei UI",
           "candidate popup invalid font did not return to the current font");
    popup.SetFontPoints(10);
    expect(popup.FontPoints() == 10, "candidate popup small font was rejected");
    popup.SetFontPoints(16);
    expect(popup.FontPoints() == 16, "candidate popup large font was rejected");
    popup.SetFontPoints(99);
    expect(popup.FontPoints() == 12, "candidate popup invalid font did not return to medium");
    popup.SetForgetEnabled(false);
    expect(!popup.ForgetEnabled(), "punctuation popup did not disable lexical forgetting");
    popup.SetForgetEnabled(true);
    expect(popup.ForgetEnabled(), "lexical candidate popup did not restore forgetting");
       popup.SetHorizontal(true);
       expect(popup.IsHorizontal(), "candidate popup did not select horizontal layout");
       popup.SetHorizontal(false);
    unsigned selected = 0;
    popup.SetSelectionHandler([](void* context, unsigned ordinal) noexcept {
        *static_cast<unsigned*>(context) = ordinal;
    }, &selected);
       unsigned forgotten = 0;
       bool forgetMenuPresented = false;
       popup.SetForgetHandler([](void* context, unsigned ordinal) noexcept {
              *static_cast<unsigned*>(context) = ordinal;
       }, &forgotten);
       popup.SetForgetMenuPresenter([](HMENU, POINT, HWND, void* context) noexcept -> UINT {
              *static_cast<bool*>(context) = true;
              return 1;
       }, &forgetMenuPresented);
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
    SendMessageW(window, WM_TIMER, CandidatePopup::SettingsRefreshTimerId, 0);
    const LONG mediumHeight = popup.Bounds().bottom - popup.Bounds().top;
    replaceDisplaySettings("large", "system-ui", "standard_pinyin", "horizontal", true, 2);
    SendMessageW(window, WM_TIMER, CandidatePopup::SettingsRefreshTimerId, 0);
    const LONG largeHeight = popup.Bounds().bottom - popup.Bounds().top;
    expect(popup.FontPoints() == 16 && popup.FontFamily() == L"system-ui" &&
               popup.IsHorizontal(),
           "visible candidate popup did not synchronize all external display settings");
    expect(largeHeight < mediumHeight,
           "horizontal live refresh did not collapse the candidate rows");
    replaceDisplaySettings("small", "YinYuan", "yinyuan", "vertical", false, 3);
    SendMessageW(window, WM_TIMER, CandidatePopup::SettingsRefreshTimerId, 0);
    const LONG smallHeight = popup.Bounds().bottom - popup.Bounds().top;
    expect(popup.FontPoints() == 10 && popup.EffectiveFontFamily() == L"YinYuan" &&
               !popup.IsHorizontal() && smallHeight > largeHeight,
           "visible candidate popup did not synchronize Yinyuan and vertical settings");
    replaceDisplaySettings("medium", "Microsoft YaHei UI", "key_sequence",
                           "vertical", false, 4);
    SendMessageW(window, WM_TIMER, CandidatePopup::SettingsRefreshTimerId, 0);
    expect(popup.FontPoints() == 12 && popup.FontFamily() == L"Microsoft YaHei UI" &&
               popup.EffectiveFontFamily() == L"Microsoft YaHei UI",
           "visible candidate popup did not restore all external display settings");
    expect(popup.Count() == 9, "owned candidate popup exceeded Shift ordinal count");
    expect((GetWindowLongPtrW(window, GWL_EXSTYLE) & (WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW)) ==
               (WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW),
           "owned candidate popup can activate or enters the taskbar");
    expect(IsWindowVisible(window), "owned candidate popup did not become visible");
    SendMessageW(window, WM_LBUTTONUP, 0, MAKELPARAM(20, 10));
    expect(selected == 1, "owned candidate popup did not route the first mouse row");
    SendMessageW(window, WM_RBUTTONUP, 0, MAKELPARAM(20, 10));
    expect(forgetMenuPresented && forgotten == 1,
           "owned candidate popup did not route quick forget for the clicked row");
    popup.SetForgetEnabled(false);
    forgotten = 0;
    forgetMenuPresented = false;
    SendMessageW(window, WM_RBUTTONUP, 0, MAKELPARAM(20, 10));
    expect(!forgetMenuPresented && forgotten == 0,
           "local punctuation rows exposed lexical quick forget");
    popup.SetForgetEnabled(true);
    selected = 0;
    forgotten = 0;
    forgetMenuPresented = false;
    SendMessageW(window, WM_LBUTTONUP, 0, MAKELPARAM(1, 1));
    expect(selected == 0, "owned candidate popup accepted a border click");
    SendMessageW(window, WM_RBUTTONUP, 0, MAKELPARAM(1, 1));
    expect(!forgetMenuPresented && forgotten == 0,
           "owned candidate popup offered quick forget outside a candidate row");
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
    DestroyWindow(window);
    expect(!IsWindow(window), "external candidate popup destruction failed");
    expect(popup.Update({L"⇧1  重建"}, centeredAnchor, nullptr),
           "candidate popup did not recover after its HWND was destroyed by the host");
    expect(popup.Window() && IsWindow(popup.Window()) && popup.Window() != window,
           "candidate popup retained a stale HWND after host destruction");
    popup.Destroy();
    expect(!popup.Window(), "owned candidate popup did not clear its HWND");
       DeleteFileW(settingsPath.c_str());
}

LRESULT CALLBACK conflictingCandidatePopupProcedure(HWND window, UINT message, WPARAM wParam,
											 LPARAM lParam) {
	return DefWindowProcW(window, message, wParam, lParam);
}

void testCandidatePopupClassAndDpiLifecycle() {
	const RECT anchor{100, 100, 101, 101};
	{
		CandidatePopup popup;
		expect(popup.Update({L"⇧1  缩放"}, anchor, nullptr),
			   "candidate popup could not register its owned window class");
		const int at96 = popup.TextColumnLeft();
		SendMessageW(popup.Window(), WM_DPICHANGED, MAKELONG(192, 192), 0);
		expect(popup.TextColumnLeft() > at96,
			   "candidate popup DIP metrics did not scale after WM_DPICHANGED");
	}
	WNDCLASSEXW stale{};
	stale.cbSize = sizeof(stale);
	expect(GetClassInfoExW(GetModuleHandleW(nullptr), CandidatePopup::ClassName(), &stale) == FALSE,
		   "candidate popup class remained registered after its final lease was released");

	WNDCLASSEXW conflict{};
	conflict.cbSize = sizeof(conflict);
	conflict.lpfnWndProc = conflictingCandidatePopupProcedure;
	conflict.hInstance = GetModuleHandleW(nullptr);
	conflict.lpszClassName = CandidatePopup::ClassName();
	expect(RegisterClassExW(&conflict) != 0, "could not seed conflicting candidate popup class");
	{
		CandidatePopup popup;
		expect(!popup.Update({L"⇧1  冲突"}, anchor, nullptr),
			   "candidate popup reused a same-name class with a foreign window procedure");
	}
	UnregisterClassW(CandidatePopup::ClassName(), GetModuleHandleW(nullptr));
}

void testExperimentSettings() {
    using namespace yime::experiment;
    const auto missing = LoadExperimentSettings(L"Z:\\missing-yimecore-experiment-settings.json");
    expect(missing.mode == "variable", "experiment default mode is not variable");
    expect(missing.candidateFontPreset == "medium" && missing.candidateFontPoints == 12,
           "experiment medium font default is not 12 points");
    expect(missing.candidateFontFamily == "Microsoft YaHei UI",
           "experiment candidate font family did not preserve the current font default");
    expect(missing.candidateAnnotation == "key_sequence",
           "experiment candidate encoding default is not key sequence");
    expect(missing.candidatePageSize == 5 && missing.candidateLayout == "vertical",
           "experiment candidate count/layout defaults do not match the production UI");

       const std::wstring fontPath = temporaryStatePath(L"yinyuan-font-settings.json");
       {
              std::ofstream output(std::filesystem::path(fontPath), std::ios::binary | std::ios::trunc);
              output << R"({"version":1,"candidate_font_preset":"large","candidate_font_family":"YinYuan","candidate_annotation":"yinyuan"})";
       }
       const auto yinyuanFont = LoadExperimentSettings(fontPath);
       expect(yinyuanFont.candidateFontPreset == "large" &&
                        yinyuanFont.candidateFontPoints == 16 &&
                        yinyuanFont.candidateFontFamily == "YinYuan" &&
                        yinyuanFont.candidateAnnotation == "yinyuan",
                 "experiment settings discarded the candidate size or required Yinyuan PUA font");
       DeleteFileW(fontPath.c_str());

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
	{
		std::ofstream held(std::filesystem::path(path + L".lock"),
						   std::ios::binary | std::ios::trunc);
		held << "held";
	}
	const ULONGLONG contentionStarted = GetTickCount64();
	expect(!ApplyExperimentSettingsCommand(ExperimentSettingsCommand::Chinese, path, &updated),
		   "contended settings lock unexpectedly succeeded");
	expect(GetTickCount64() - contentionStarted < 500,
		   "contended language-bar settings lock blocked the host UI thread too long");
	DeleteFileW((path + L".lock").c_str());
    DeleteFileW(path.c_str());
}

void testLanguageBarItem() {
    using namespace yime::experiment;
    const std::wstring path = temporaryStatePath(L"language-bar.json");
    DeleteFileW(path.c_str());
    const auto installRootTest = std::filesystem::path(path).parent_path() / L"install-root-selection";
    const auto staleModuleRoot = installRootTest / L"stale-module-root";
    const auto activeRegisteredRoot = installRootTest / L"active-registered-root";
    std::filesystem::create_directories(activeRegisteredRoot);
    {
        std::ofstream manifest(activeRegisteredRoot / L"package-manifest.json", std::ios::binary);
        manifest << "{}";
    }
    expect(std::filesystem::path(SelectTrialInstallRoot(staleModuleRoot.wstring(),
                                                        activeRegisteredRoot.wstring())) ==
               activeRegisteredRoot,
           "upgraded host did not prefer the active registered Trial install root");
    std::filesystem::remove(activeRegisteredRoot / L"package-manifest.json");
    expect(std::filesystem::path(SelectTrialInstallRoot(staleModuleRoot.wstring(),
                                                        activeRegisteredRoot.wstring())) ==
               staleModuleRoot,
           "invalid registered Trial install root displaced the module-root fallback");
    ExperimentSettings initial;
    expect(ApplyExperimentSettingsCommand(ExperimentSettingsCommand::Chinese, path, &initial),
           "could not seed language-bar state");
    bool popupSeen = false;
    UINT launchedTool = 0;
    int runtimeEnsures = 0;
       auto* item = new LanguageBarItem(path, toggleDefaultLanguageFromPopup, &popupSeen,
                                     recordToolLaunch, &launchedTool,
                                     recordRuntimeEnsure, &runtimeEnsures);
    struct LanguageBarSettingsObservation {
        int calls = 0;
        std::string annotation;
        std::int64_t revision = 0;
    } settingsObservation;
    item->SetSettingsChangedHandler(
        [](void* context, const ExperimentSettings& settings) noexcept {
            auto* observation = static_cast<LanguageBarSettingsObservation*>(context);
            ++observation->calls;
            observation->annotation = settings.candidateAnnotation;
            observation->revision = settings.revision;
        },
        &settingsObservation);
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
    expect(item->InitMenu(menu) == S_OK && menu->entries.size() == 12,
           "host right-click path did not build the complete trial menu");
    expect(menu->entries[0].id == YIME_LBI_DEFAULT_LANGUAGE &&
               menu->entries[0].text == L"默认语言：中文" && !menu->entries[0].submenu,
           "default language toggle is missing or does not show its current state");
    expect((menu->entries[1].flags & TF_LBMENUF_SEPARATOR) != 0,
           "default language toggle is not separated from output settings");
    expect(menu->entries[2].text == L"标点样式" && menu->entries[2].submenu &&
               menu->entries[2].submenu->entries.size() == 2 &&
               menu->entries[2].submenu->entries[0].id == YIME_LBI_PUNCTUATION_CHINESE &&
               menu->entries[2].submenu->entries[1].id == YIME_LBI_PUNCTUATION_ENGLISH,
           "Chinese/English punctuation cascade is missing");
    expect(menu->entries[3].text == L"字符宽度" && menu->entries[3].submenu &&
               menu->entries[3].submenu->entries.size() == 2 &&
               menu->entries[3].submenu->entries[0].id == YIME_LBI_SHAPE_HALF &&
               menu->entries[3].submenu->entries[1].id == YIME_LBI_SHAPE_FULL,
           "half/full-width cascade is missing");
    expect(menu->entries[4].text == L"汉字字形" && menu->entries[4].submenu &&
               menu->entries[4].submenu->entries.size() == 2 &&
               menu->entries[4].submenu->entries[0].id == YIME_LBI_SCRIPT_SIMPLIFIED &&
               menu->entries[4].submenu->entries[1].id == YIME_LBI_SCRIPT_TRADITIONAL,
           "simplified/traditional cascade is missing");
    expect((menu->entries[5].flags & TF_LBMENUF_SEPARATOR) != 0,
           "tool commands are not separated from composition settings");
    expect(menu->entries[6].id == YIME_LBI_INPUT_TOOLBAR &&
               menu->entries[6].text == L"基本设置" &&
               (menu->entries[6].flags & TF_LBMENUF_CHECKED) == 0,
           "basic settings must still launch the input toolbar");
    expect(menu->entries[7].id == YIME_LBI_REVERSE_LOOKUP &&
               menu->entries[7].text == L"反查编码",
           "reverse-lookup host click path is missing");
    expect(menu->entries[8].id == YIME_LBI_USER_LEXICON &&
               menu->entries[8].text == L"用户词库",
           "user-lexicon host click path is missing");
    expect(menu->entries[9].id == YIME_LBI_TRAINER_TOOL &&
               menu->entries[9].text == L"指法练习",
           "trainer host click path is missing");
    expect(menu->entries[10].id == YIME_LBI_TOOL_CENTER &&
               menu->entries[10].text == L"工具中心",
           "tool-center host click path is missing");
    expect(menu->entries[11].id == YIME_LBI_SETTINGS_TOOL &&
               menu->entries[11].text == L"候选设置",
           "settings-tool host click path is missing");
    menu->Release();

    FakeLanguageBarSink sink;
    ITfSource* source = nullptr;
    expect(item->QueryInterface(__uuidof(ITfSource), reinterpret_cast<void**>(&source)) == S_OK && source,
           "language bar does not expose ITfSource updates");
    DWORD cookie = 0;
    expect(source && source->AdviseSink(__uuidof(ITfLangBarItemSink), &sink, &cookie) == S_OK,
           "language bar sink subscription failed");
    ExperimentSettings annotationUpdate;
    expect(ApplyExperimentSettingsCommand(ExperimentSettingsCommand::AnnotationStandardPinyin,
                                          path, &annotationUpdate),
           "could not simulate an external candidate annotation update");
    item->Refresh();
    expect(settingsObservation.calls == 1 &&
               settingsObservation.annotation == "standard_pinyin" &&
               settingsObservation.revision == annotationUpdate.revision,
            "non-icon settings did not reach the active text service refresh callback");
	expect(runtimeEnsures == 0,
		   "passive language-bar refresh synchronously started or waited for the Trial runtime");
	FakeLanguageBarSink reentrantSink;
	DWORD reentrantCookie = 0;
	expect(source->AdviseSink(__uuidof(ITfLangBarItemSink), &reentrantSink,
						  &reentrantCookie) == S_OK,
		   "reentrant language-bar sink subscription failed");
	reentrantSink.source = source;
	reentrantSink.cookie = reentrantCookie;
	reentrantSink.unadviseOnUpdate = true;
    const auto expectToolbarRefresh = [&](ExperimentSettingsCommand command, DWORD flags,
                                          const char* applyFailure, const char* refreshFailure) {
        ExperimentSettings toolbarUpdate;
        sink.updates = 0;
        expect(ApplyExperimentSettingsCommand(command, path, &toolbarUpdate), applyFailure);
        expect(waitForLanguageBarUpdate(sink, flags), refreshFailure);
    };
    expectToolbarRefresh(ExperimentSettingsCommand::English, TF_LBI_TEXT | TF_LBI_ICON,
                         "could not simulate the desktop toolbar English command",
                         "desktop toolbar language change did not refresh the language-bar text and icon");
    expectToolbarRefresh(ExperimentSettingsCommand::Chinese, TF_LBI_TEXT | TF_LBI_ICON,
                         "could not restore the desktop toolbar Chinese command",
                         "desktop toolbar language restore did not refresh the language-bar text and icon");
    expectToolbarRefresh(ExperimentSettingsCommand::ShapeFull, TF_LBI_ICON,
                         "could not simulate the desktop toolbar full-width command",
                         "desktop toolbar width change did not refresh the language-bar icon");
    expectToolbarRefresh(ExperimentSettingsCommand::ShapeHalf, TF_LBI_ICON,
                         "could not restore the desktop toolbar half-width command",
                         "desktop toolbar width restore did not refresh the language-bar icon");
    expectToolbarRefresh(ExperimentSettingsCommand::PunctuationEnglish, TF_LBI_STATUS,
                         "could not simulate the desktop toolbar English-punctuation command",
                         "desktop toolbar punctuation change did not refresh the language-bar menu state");
    expectToolbarRefresh(ExperimentSettingsCommand::PunctuationChinese, TF_LBI_STATUS,
                         "could not restore the desktop toolbar Chinese-punctuation command",
                         "desktop toolbar punctuation restore did not refresh the language-bar menu state");
    expectToolbarRefresh(ExperimentSettingsCommand::ScriptTraditional, TF_LBI_STATUS,
                         "could not simulate the desktop toolbar Traditional command",
                         "desktop toolbar script change did not refresh the language-bar menu state");
    expectToolbarRefresh(ExperimentSettingsCommand::ScriptSimplified, TF_LBI_STATUS,
                         "could not restore the desktop toolbar Simplified command",
                         "desktop toolbar script restore did not refresh the language-bar menu state");
    sink.updates = 0;
    expect(item->OnClick(TF_LBI_CLK_LEFT, {}, nullptr) == S_OK,
           "desktop language-bar left click did not toggle to English");
	expect(reentrantSink.count == 1 && !reentrantSink.unadviseOnUpdate,
		   "language-bar sink could not safely unadvise itself during notification");
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
           "default-language popup command did not switch back to Chinese");
       expect(item->OnMenuSelect(0x6C11) == E_INVALIDARG,
                 "removed input-scheme language-bar command remains reachable");
    expect(item->OnMenuSelect(YIME_LBI_PUNCTUATION_CHINESE) == S_OK &&
               !LoadExperimentSettings(path).asciiPunctuation,
           "host submenu click did not select Chinese punctuation");
       sink.updates = 0;
    expect(item->OnMenuSelect(YIME_LBI_SHAPE_FULL) == S_OK &&
               LoadExperimentSettings(path).fullShape,
           "host submenu click did not select full-width output");
       expect((sink.updates & TF_LBI_ICON) != 0,
                 "full-width selection did not refresh the four-state language icon");
    const int runtimeEnsuresBeforeTraditional = runtimeEnsures;
    expect(item->OnMenuSelect(YIME_LBI_SCRIPT_TRADITIONAL) == S_OK &&
               LoadExperimentSettings(path).traditionalization,
           "host submenu click did not select Traditional output");
    expect(runtimeEnsures == runtimeEnsuresBeforeTraditional + 1,
           "Traditional selection did not ensure the Trial runtime before returning to the host");
    for (const UINT command : {YIME_LBI_INPUT_TOOLBAR, YIME_LBI_REVERSE_LOOKUP,
                               YIME_LBI_USER_LEXICON, YIME_LBI_TRAINER_TOOL,
                               YIME_LBI_TOOL_CENTER, YIME_LBI_SETTINGS_TOOL}) {
        launchedTool = 0;
        const int runtimeEnsuresBeforeTool = runtimeEnsures;
        expect(item->OnMenuSelect(command) == S_OK && launchedTool == command &&
                   runtimeEnsures == runtimeEnsuresBeforeTool + 1,
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
    for (const UINT command : {YIME_LBI_INPUT_TOOLBAR, YIME_LBI_REVERSE_LOOKUP,
                               YIME_LBI_USER_LEXICON, YIME_LBI_TRAINER_TOOL,
                               YIME_LBI_TOOL_CENTER, YIME_LBI_SETTINGS_TOOL}) {
        expect(eventText.find("\"command_id\":" + std::to_string(command)) != std::string::npos,
               "one of the six right-click tool commands was not captured by its exact host ID");
    }
    if (source) {
        expect(source->UnadviseSink(cookie) == S_OK, "language bar sink unsubscribe failed");
        source->Release();
    }
    item->Release();
    DeleteFileW(path.c_str());
    std::error_code cleanupError;
    std::filesystem::remove(eventPath, cleanupError);
    std::filesystem::remove_all(installRootTest, cleanupError);
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
    testPunctuationPaletteContract();
    testOutputTransformContract();
    testBrokerEndpoint();
    testBrokerPipeTransportLiveness();
    testBrokerPipeSecurityAndTimeouts();
    testCandidateElement();
	expect(yime::experiment::ValidateCompositionRangeResult(S_OK, nullptr) == E_UNEXPECTED,
		   "successful TSF insertion with a null range was not rejected");
	testOwnedCandidatePopup();
	testCandidatePopupClassAndDpiLifecycle();
    testExperimentSettings();
    testLanguageBarItem();
    testComLifecycle(argv[1]);
    if (failures != 0) return 1;
    std::cout << "YimeTextService E6-B1 contracts passed\n";
    return 0;
}
