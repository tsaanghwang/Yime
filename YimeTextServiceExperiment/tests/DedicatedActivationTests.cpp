// Native DLL contract only: all TSF interfaces are in-memory substitutes.
// No CoCreateInstance, real TSF activation, registry, documents or user input.
#include <windows.h>
#include <msctf.h>
#include <wrl/client.h>
#include <iostream>
#include <stdexcept>
#include <thread>
#include "DedicatedTouchService.h"
#include "YimeTextServiceIds.h"
using Microsoft::WRL::ComPtr;
namespace {
void check(bool value, const char* reason) { if (!value) throw std::runtime_error(reason); }
constexpr TfClientId serviceClient = 37;
class Manager final : public ITfThreadMgr, public ITfKeystrokeMgr, public ITfSource, public ITfSourceSingle {
public:
    ULONG refs=1;
    HRESULT keyResult=S_OK, observerResult=S_OK, providerResult=S_OK;
    bool exposeSourceSingle=true;
    unsigned keyCalls=0, observerCalls=0, providerCalls=0;
    unsigned keyRemoves=0, observerRemoves=0, providerRemoves=0;
    ComPtr<ITfKeyEventSink> keys;
    ComPtr<IUnknown> observer;
    ComPtr<ITfFunctionProvider> provider;
    STDMETHODIMP QueryInterface(REFIID iid, void** out) override {
        if (!out) return E_POINTER; *out=nullptr;
        if (iid==IID_IUnknown || iid==__uuidof(ITfThreadMgr)) *out=static_cast<ITfThreadMgr*>(this);
        else if(iid==__uuidof(ITfKeystrokeMgr)) *out=static_cast<ITfKeystrokeMgr*>(this);
        else if(iid==__uuidof(ITfSource)) *out=static_cast<ITfSource*>(this);
        else if(iid==__uuidof(ITfSourceSingle) && exposeSourceSingle) *out=static_cast<ITfSourceSingle*>(this);
        else return E_NOINTERFACE;
        AddRef();return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++refs; }
    STDMETHODIMP_(ULONG) Release() override { return --refs; } // Test owns the stack object.
    STDMETHODIMP AdviseKeyEventSink(TfClientId id, ITfKeyEventSink* sink, BOOL foreground) override {
        ++keyCalls;if(id!=serviceClient || !sink || !foreground)return E_INVALIDARG;
        if(keyResult==S_OK)keys=sink;return keyResult;
    }
    STDMETHODIMP UnadviseKeyEventSink(TfClientId id) override {
        if(id!=serviceClient || !keys)return E_INVALIDARG;++keyRemoves;keys.Reset();return S_OK;
    }
    STDMETHODIMP AdviseSink(REFIID iid,IUnknown* sink,DWORD* cookie) override {
        ++observerCalls;if(iid!=__uuidof(ITfThreadMgrEventSink) || !sink || !cookie)return E_INVALIDARG;
        if(observerResult==S_OK){observer=sink;*cookie=123;}return observerResult;
    }
    STDMETHODIMP UnadviseSink(DWORD cookie) override {
        if(cookie!=123 || !observer)return E_INVALIDARG;++observerRemoves;observer.Reset();return S_OK;
    }
    STDMETHODIMP AdviseSingleSink(TfClientId id,REFIID iid,IUnknown* sink) override {
        ++providerCalls;if(id!=serviceClient || iid!=__uuidof(ITfFunctionProvider) || !sink)return E_INVALIDARG;
        if(providerResult!=S_OK)return providerResult;
        return sink->QueryInterface(IID_PPV_ARGS(&provider));
    }
    STDMETHODIMP UnadviseSingleSink(TfClientId id,REFIID iid) override {
        if(id!=serviceClient || iid!=__uuidof(ITfFunctionProvider) || !provider)return E_INVALIDARG;
        ++providerRemoves;provider.Reset();return S_OK;
    }
    STDMETHODIMP GetFunctionProvider(REFCLSID clsid,ITfFunctionProvider** out) override {
        if(!out)return E_POINTER;*out=nullptr;
        if(!provider || clsid!=CLSID_YimeTextServiceExperiment)return TF_E_NOPROVIDER;
        return provider.CopyTo(out);
    }
    STDMETHODIMP Activate(TfClientId*) override {return E_NOTIMPL;}
    STDMETHODIMP Deactivate() override {return E_NOTIMPL;}
    STDMETHODIMP CreateDocumentMgr(ITfDocumentMgr**) override {return E_NOTIMPL;}
    STDMETHODIMP EnumDocumentMgrs(IEnumTfDocumentMgrs**) override {return E_NOTIMPL;}
    STDMETHODIMP GetFocus(ITfDocumentMgr**) override {return E_NOTIMPL;}
    STDMETHODIMP SetFocus(ITfDocumentMgr*) override {return E_NOTIMPL;}
    STDMETHODIMP AssociateFocus(HWND,ITfDocumentMgr*,ITfDocumentMgr**) override {return E_NOTIMPL;}
    STDMETHODIMP IsThreadFocus(BOOL*) override {return E_NOTIMPL;}
    STDMETHODIMP EnumFunctionProviders(IEnumTfFunctionProviders**) override {return E_NOTIMPL;}
    STDMETHODIMP GetGlobalCompartment(ITfCompartmentMgr**) override {return E_NOTIMPL;}
    STDMETHODIMP GetForeground(CLSID*) override {return E_NOTIMPL;}
    STDMETHODIMP TestKeyDown(WPARAM,LPARAM,BOOL*) override {return E_NOTIMPL;}
    STDMETHODIMP TestKeyUp(WPARAM,LPARAM,BOOL*) override {return E_NOTIMPL;}
    STDMETHODIMP KeyDown(WPARAM,LPARAM,BOOL*) override {return E_NOTIMPL;}
    STDMETHODIMP KeyUp(WPARAM,LPARAM,BOOL*) override {return E_NOTIMPL;}
    STDMETHODIMP GetPreservedKey(ITfContext*,const TF_PRESERVEDKEY*,GUID*) override {return E_NOTIMPL;}
    STDMETHODIMP IsPreservedKey(REFGUID,const TF_PRESERVEDKEY*,BOOL*) override {return E_NOTIMPL;}
    STDMETHODIMP PreserveKey(TfClientId,REFGUID,const TF_PRESERVEDKEY*,const WCHAR*,ULONG) override {return E_NOTIMPL;}
    STDMETHODIMP UnpreserveKey(REFGUID,const TF_PRESERVEDKEY*) override {return E_NOTIMPL;}
    STDMETHODIMP SetPreservedKeyDescription(REFGUID,const WCHAR*,ULONG) override {return E_NOTIMPL;}
    STDMETHODIMP GetPreservedKeyDescription(REFGUID,BSTR*) override {return E_NOTIMPL;}
    STDMETHODIMP SimulatePreservedKey(ITfContext*,REFGUID,BOOL*) override {return E_NOTIMPL;}
};
ComPtr<ITfTextInputProcessorEx> create(IClassFactory* factory) {
    ComPtr<ITfTextInputProcessorEx> tip;
    check(factory->CreateInstance(nullptr,IID_PPV_ARGS(&tip))==S_OK,"create dedicated TIP");return tip;
}
void success(IClassFactory* factory) {
    Manager manager;auto tip=create(factory);
    ComPtr<ITfFunctionProvider> inactive;check(tip.As(&inactive)==S_OK,"function provider QI");
    ComPtr<IUnknown> route;
    check(inactive->GetFunction(GUID_NULL,__uuidof(IDedicatedTouchService),&route)==TF_E_DISCONNECTED && !route,"unactivated route rejected");
    check(tip->ActivateEx(&manager,serviceClient,0)==S_OK,"activate with substitute manager");
    ComPtr<ITfFunctionProvider> provider;
    check(manager.GetFunctionProvider(CLSID_YimeTextServiceExperiment,&provider)==S_OK,"lookup activated instance");
    GUID type{};check(provider->GetType(&type)==S_OK && type==CLSID_YimeTextServiceExperiment,"provider identity");
    check(provider->GetType(nullptr)==E_POINTER,"type null rejected");
    BSTR description=nullptr;check(provider->GetDescription(&description)==S_OK && SysStringLen(description)>0,"provider description");SysFreeString(description);
    check(provider->GetDescription(nullptr)==E_POINTER,"description null rejected");
    check(provider->GetFunction(GUID_NULL,__uuidof(IDedicatedTouchService),nullptr)==E_POINTER,"route null rejected");
    check(provider->GetFunction(CLSID_YimeTextServiceExperiment,__uuidof(IDedicatedTouchService),&route)==E_NOINTERFACE && !route,"unknown function rejected");
    check(provider->GetFunction(GUID_NULL,IID_IUnknown,&route)==E_NOINTERFACE && !route,"unknown route interface rejected");
    check(provider->GetFunction(GUID_NULL,__uuidof(IDedicatedTouchService),&route)==S_OK,"route supplied");
    ComPtr<IUnknown> original,returned;check(tip.As(&original)==S_OK && route.As(&returned)==S_OK && original.Get()==returned.Get(),"same COM instance, not a new TIP");
    HRESULT wrongThread=S_OK;std::thread worker([&]{ComPtr<IUnknown> value;wrongThread=provider->GetFunction(GUID_NULL,__uuidof(IDedicatedTouchService),&value);});worker.join();
    check(wrongThread==RPC_E_WRONG_THREAD,"cross-thread lookup rejected");
    check(tip->Deactivate()==S_OK,"deactivate");
    route.Reset();check(provider->GetFunction(GUID_NULL,__uuidof(IDedicatedTouchService),&route)==TF_E_DISCONNECTED && !route,"retained provider disconnected");
    check(!manager.provider && !manager.keys && !manager.observer && manager.refs==1,"all callbacks and manager references released");
    check(manager.providerRemoves==1 && manager.keyRemoves==1 && manager.observerRemoves==1,"callbacks removed once");
    check(tip->Deactivate()==S_OK && manager.providerRemoves==1,"repeated deactivation harmless");
    check(tip->ActivateEx(&manager,serviceClient,0)==S_OK && tip->Deactivate()==S_OK,"reactivation after complete release");
    check(manager.refs==1 && manager.providerRemoves==2,"reactivation does not leak");
}
void failures(IClassFactory* factory) {
    for(unsigned which=0;which<5;++which){
        Manager manager;auto tip=create(factory);
        if(which==0)manager.keyResult=E_INVALIDARG;
        if(which==1)manager.observerResult=E_FAIL;
        if(which==2)manager.providerResult=E_ACCESSDENIED;
        if(which==3)manager.providerResult=S_FALSE;
        if(which==4)manager.exposeSourceSingle=false;
        check(FAILED(tip->ActivateEx(&manager,serviceClient,0)),"activation failure retained");
        check(!manager.keys && !manager.observer && !manager.provider && manager.refs==1,"failure unwinds subscriptions");
        check(manager.providerRemoves==0,"failed provider never unadvised as installed");
        check(manager.keyRemoves==(which==0?0u:1u),"key cleanup ownership");
        check(manager.observerRemoves==(which<2?0u:1u),"observer cleanup ownership");
        check(manager.providerCalls==(which==2 || which==3?1u:0u),"provider not exposed before earlier gates");
        check(tip->Deactivate()==S_OK && manager.refs==1,"failed activation can deactivate");
    }
}
}
int wmain(int argc,wchar_t** argv) {
    HMODULE module=nullptr;
    try {
        check(argc==2,"explicit DLL path required");
        check(GetEnvironmentVariableW(L"YIME_TEXTSERVICE_EXPERIMENT_DIRECT_TEST",nullptr,0)==0,"direct-test bypass is forbidden");
        module=LoadLibraryExW(argv[1],nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_SYSTEM32);
        check(module!=nullptr,"load fixed DLL");
        auto entry=reinterpret_cast<HRESULT(STDAPICALLTYPE*)(REFCLSID,REFIID,LPVOID*)>(GetProcAddress(module,"DllGetClassObject"));
        auto unload=reinterpret_cast<HRESULT(STDAPICALLTYPE*)()>(GetProcAddress(module,"DllCanUnloadNow"));
        check(entry && unload,"DLL exports");
        {
            ComPtr<IClassFactory> factory;check(entry(CLSID_YimeTextServiceExperiment,IID_PPV_ARGS(&factory))==S_OK,"factory");
            success(factory.Get());failures(factory.Get());
        }
        check(unload()==S_OK,"no DLL-owned references leaked");
        FreeLibrary(module);std::cout<<"PASS: dedicated provider lifecycle, identity, thread and five failure paths; substitute TSF only\n";return 0;
    }catch(const std::exception& error){std::cerr<<error.what()<<'\n';if(module)FreeLibrary(module);return 1;}
}
