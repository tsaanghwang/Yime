#include <windows.h>
#include <msctf.h>

#include <iostream>
#include <string_view>

#include "KeyContract.h"
#include "CandidateListUIElement.h"
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
    testCandidateElement();
    testComLifecycle(argv[1]);
    if (failures != 0) return 1;
    std::cout << "YimeTextService E6-B1 contracts passed\n";
    return 0;
}
