#include <windows.h>
#include <msctf.h>

#include <iostream>
#include <string_view>

#include "KeyContract.h"
#include "BrokerEndpoint.h"
#include "CandidateListUIElement.h"
#include "CandidatePopup.h"
#include "LanguageBarItem.h"
#include "YimeTextServiceIds.h"

namespace {

using GetClassObject = HRESULT(__stdcall*)(REFCLSID, REFIID, void**);
using CanUnloadNow = HRESULT(__stdcall*)();

int failures = 0;

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
    const auto& labels = CandidateLabels();
    constexpr std::wstring_view expected[] = {L"⇧1", L"⇧2", L"⇧3", L"⇧4", L"⇧5", L"⇧6", L"⇧7", L"⇧8", L"⇧9"};
    for (size_t index = 0; index < labels.size(); ++index) {
        expect(labels[index] == expected[index], "candidate label lost Shift marker");
    }
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
    candidates->Release();
}

void testOwnedCandidatePopup() {
    CandidatePopup popup;
    unsigned selected = 0;
    popup.SetSelectionHandler([](void* context, unsigned ordinal) noexcept {
        *static_cast<unsigned*>(context) = ordinal;
    }, &selected);
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
    const RECT bounds = popup.Bounds();
    HMONITOR monitor = MonitorFromRect(&anchor, MONITOR_DEFAULTTONEAREST);
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

void testLanguageBarItem() {
    auto* item = new LanguageBarItem();
    TF_LANGBARITEMINFO info{};
    expect(item->GetInfo(&info) == S_OK, "language bar GetInfo failed");
    expect(IsEqualGUID(info.clsidService, CLSID_YimeTextServiceExperiment), "language bar service CLSID mismatch");
    expect(IsEqualGUID(info.guidItem, GUID_YimeTextServiceExperimentLangBar), "language bar item GUID mismatch");
    expect(info.dwStyle == TF_LBI_STYLE_BTN_BUTTON, "language bar must remain a button without a menu");
    expect(std::wstring_view(info.szDescription) == L"Yime 自研栈试验版", "language bar description mismatch");
    DWORD status = ~DWORD{0};
    expect(item->GetStatus(&status) == S_OK && status == 0, "language bar initial status mismatch");
    expect(item->Show(FALSE) == S_OK && item->GetStatus(&status) == S_OK &&
               (status & TF_LBI_STATUS_HIDDEN) != 0,
           "language bar hide state mismatch");
    expect(item->Show(TRUE) == S_OK && item->GetStatus(&status) == S_OK &&
               (status & TF_LBI_STATUS_HIDDEN) == 0,
           "language bar show state mismatch");
    HICON icon = reinterpret_cast<HICON>(1);
    expect(item->GetIcon(&icon) == E_NOTIMPL && icon == nullptr, "language bar unexpectedly supplied an icon");
    BSTR text = nullptr;
    expect(item->GetText(&text) == S_OK && text && std::wstring_view(text) == L"Yime 自研栈试验版",
           "language bar text mismatch");
    SysFreeString(text);
    expect(item->InitMenu(nullptr) == E_NOTIMPL, "language bar unexpectedly exposed a menu");
    expect(item->OnMenuSelect(1) == E_INVALIDARG, "language bar unexpectedly accepted a command ID");
    item->Release();
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
    testBrokerEndpoint();
    testCandidateElement();
    testOwnedCandidatePopup();
    testLanguageBarItem();
    testComLifecycle(argv[1]);
    if (failures != 0) return 1;
    std::cout << "YimeTextService E6-B1 contracts passed\n";
    return 0;
}
