#include <windows.h>

#include <atomic>
#include <new>

#include "ModuleState.h"
#include "TextService.h"
#include "YimeTextServiceIds.h"

namespace {

std::atomic<long> moduleReferences{0};

class ClassFactory final : public IClassFactory {
public:
    ClassFactory() noexcept { YimeModuleAddRef(); }
    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) return E_POINTER;
        *object = nullptr;
        if (!IsEqualIID(iid, IID_IUnknown) && !IsEqualIID(iid, IID_IClassFactory)) return E_NOINTERFACE;
        *object = static_cast<IClassFactory*>(this);
        AddRef();
        return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
    STDMETHODIMP_(ULONG) Release() override {
        const ULONG remaining = --references_;
        if (remaining == 0) delete this;
        return remaining;
    }
    STDMETHODIMP CreateInstance(IUnknown* outer, REFIID iid, void** object) override {
        if (!object) return E_POINTER;
        *object = nullptr;
        if (outer) return CLASS_E_NOAGGREGATION;
        auto* service = new (std::nothrow) YimeTextService();
        if (!service) return E_OUTOFMEMORY;
        const HRESULT result = service->QueryInterface(iid, object);
        service->Release();
        return result;
    }
    STDMETHODIMP LockServer(BOOL lock) override {
        if (lock) YimeModuleAddRef();
        else YimeModuleRelease();
        return S_OK;
    }
private:
    ~ClassFactory() { YimeModuleRelease(); }
    std::atomic<ULONG> references_{1};
};

}  // namespace

void YimeModuleAddRef() noexcept { ++moduleReferences; }
void YimeModuleRelease() noexcept { --moduleReferences; }
long YimeModuleRefCount() noexcept { return moduleReferences.load(); }

extern "C" BOOL WINAPI DllMain(HINSTANCE, DWORD, void*) { return TRUE; }

extern "C" HRESULT __stdcall DllCanUnloadNow() {
    return YimeModuleRefCount() == 0 ? S_OK : S_FALSE;
}

extern "C" HRESULT __stdcall DllGetClassObject(REFCLSID classId, REFIID iid, void** object) {
    if (!object) return E_POINTER;
    *object = nullptr;
    if (!IsEqualCLSID(classId, CLSID_YimeTextServiceExperiment)) return CLASS_E_CLASSNOTAVAILABLE;
    auto* factory = new (std::nothrow) ClassFactory();
    if (!factory) return E_OUTOFMEMORY;
    const HRESULT result = factory->QueryInterface(iid, object);
    factory->Release();
    return result;
}
