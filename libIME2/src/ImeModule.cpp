//
//    Copyright (C) 2013 - 2020 Hong Jen Yee (PCMan) <pcman.tw@gmail.com>
//
//    This library is free software; you can redistribute it and/or
//    modify it under the terms of the GNU Library General Public
//    License as published by the Free Software Foundation; either
//    version 2 of the License, or (at your option) any later version.
//
//    This library is distributed in the hope that it will be useful,
//    but WITHOUT ANY WARRANTY; without even the implied warranty of
//    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
//    Library General Public License for more details.
//
//    You should have received a copy of the GNU Library General Public
//    License along with this library; if not, write to the
//    Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
//    Boston, MA  02110-1301, USA.
//

#include "ImeModule.h"
#include <string>
#include <algorithm>
#include <memory>
#include <ObjBase.h>
#include <msctf.h>
#include <Shlwapi.h>
#include <ShlObj.h>
#include <assert.h>
#include <VersionHelpers.h>  // Provided by Windows SDK >= 8.1

#include "Window.h"
#include "TextService.h"
#include "DisplayAttributeProvider.h"

using namespace std;

namespace Ime {

// these values are not defined in older TSF SDK (windows xp)
#ifndef TF_IPP_CAPS_IMMERSIVESUPPORT
// for Windows 8
// GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT {13A016DF-560B-46CD-947A-4C3AF1E0E35D}
static const GUID GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT =
{ 0x13A016DF, 0x560B, 0x46CD, { 0x94, 0x7A, 0x4C, 0x3A, 0xF1, 0xE0, 0xE3, 0x5D } };
// GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT {25504FB4-7BAB-4BC1-9C69-CF81890F0EF5}
static const GUID GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT =
{ 0x25504FB4, 0x7BAB, 0x4BC1, { 0x9C, 0x69, 0xCF, 0x81, 0x89, 0x0F, 0x0E, 0xF5 } };
#endif

// display attribute GUIDs

// {05814A20-00B3-4B73-A3D0-2C521EFA8BE5}
static const GUID g_inputDisplayAttributeGuid = 
{ 0x5814a20, 0xb3, 0x4b73, { 0xa3, 0xd0, 0x2c, 0x52, 0x1e, 0xfa, 0x8b, 0xe5 } };


// {E1270AA5-A6B1-4112-9AC7-F5E476C3BD63}
// static const GUID g_convertedDisplayAttributeGuid = 
// { 0xe1270aa5, 0xa6b1, 0x4112, { 0x9a, 0xc7, 0xf5, 0xe4, 0x76, 0xc3, 0xbd, 0x63 } };

// refCountMutex needs to be static because it may be accessed after Release() calls the destructor.
std::mutex ImeModule::refCountMutex_;

ImeModule::ImeModule(HMODULE module, const CLSID& textServiceClsid):
    hInstance_(HINSTANCE(module)),
    textServiceClsid_(textServiceClsid) {

    Window::registerClass(hInstance_);

    // regiser default display attributes
    inputAttrib_ = ComPtr<DisplayAttributeInfo>::make(g_inputDisplayAttributeGuid);
    inputAttrib_->setTextSysColor(COLOR_WINDOWTEXT);
    inputAttrib_->setBackgroundSysColor(COLOR_WINDOW);
    inputAttrib_->setLineStyle(TF_LS_DOT);
    inputAttrib_->setLineSysColor(COLOR_WINDOWTEXT);
    displayAttrInfos_.push_back(inputAttrib_);
    // convertedAttrib_ = new DisplayAttributeInfo(g_convertedDisplayAttributeGuid);
    // displayAttrInfos_.push_back(convertedAttrib_);

    registerDisplayAttributeInfos();
}

ImeModule::~ImeModule(void) {
}

// Dll entry points implementations
HRESULT ImeModule::canUnloadNow() {
    // we own the last reference
    return refCount() <= 1 ? S_OK : S_FALSE;
}

HRESULT ImeModule::getClassObject(REFCLSID rclsid, REFIID riid, void **ppvObj) {
    if (IsEqualIID(riid, IID_IClassFactory) || IsEqualIID(riid, IID_IUnknown)) {
        // increase reference count
        AddRef();
        *ppvObj = (IClassFactory*)this; // our own object implements IClassFactory
        return NOERROR;
    }
    else {
        *ppvObj = NULL;
    }
    return CLASS_E_CLASSNOTAVAILABLE;
}

HRESULT ImeModule::registerLangProfiles(LangProfileInfo* langs, int langsCount) {
    // register the language profile
    ComPtr<ITfInputProcessorProfiles> inputProcessProfiles;
    if (CoCreateInstance(CLSID_TF_InputProcessorProfiles, NULL, CLSCTX_INPROC_SERVER,
        IID_ITfInputProcessorProfiles, (void**)&inputProcessProfiles) != S_OK) {
        return E_FAIL;
    }
    if (inputProcessProfiles->Register(textServiceClsid_) != S_OK) {
        return E_FAIL;
    }
    for(int i = 0; i < langsCount; ++i) {
        LangProfileInfo& lang = langs[i];
        LCID lcid = LocaleNameToLCID(lang.locale.c_str(), 0);
        if (lcid == 0 && !lang.fallbackLocale.empty()) { // the conversion fails
            // The new RFC4646 locale names are not well-supported in Windows 7/Vista, so
            // here we provide a fallback locale which uses the deprecated RFC 1766 format instead.
            lcid = LocaleNameToLCID(lang.fallbackLocale.c_str(), 0);
        }
        if (lcid != 0) {
            LANGID langId = LANGIDFROMLCID(lcid);
            // Remove any stale profile first so re-registering picks up
            // updated display names from ime.json without a full uninstall.
            inputProcessProfiles->RemoveLanguageProfile(textServiceClsid_, langId, lang.profileGuid);
            if (inputProcessProfiles->AddLanguageProfile(textServiceClsid_, langId, lang.profileGuid,
                lang.name.c_str(), lang.name.length(), lang.iconFile.empty() ? NULL : lang.iconFile.c_str(),
                lang.iconFile.length(), lang.iconIndex) != S_OK) {
                return E_FAIL;
            }
        }
        else {
            return E_FAIL;
        }
    }

    // Per-user language-list enablement is owned by the installer transaction
    // for its explicit TargetUserSid. Native COM/profile registration must not
    // enumerate other users or seed the Default User hive.
    return S_OK;
}

HRESULT ImeModule::registerServer(wchar_t* imeName, LangProfileInfo* langs, int count,
    bool ownsSharedTsfRegistration) {
    // write info of our COM text service component to the registry
    // path: HKEY_CLASS_ROOT\\CLSID\\{xxxx-xxxx-xxxx-xx....}
    // This reguires Administrator permimssion to write to the registery
    // regsvr32 should be run with Administrator
    // For 64 bit dll, it seems that we need to write the key to
    // a different path to make it coexist with 32 bit version:
    // HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Classes\CLSID\{xxx-xxx-...}
    // Reference: http://stackoverflow.com/questions/1105031/can-my-32-bit-and-64-bit-com-components-co-reside-on-the-same-machine

    HRESULT result = S_OK;

    // get path of our module
    wchar_t modulePath[MAX_PATH];
    DWORD modulePathLen = GetModuleFileNameW(hInstance_, modulePath, MAX_PATH);
    if(modulePathLen == 0 || modulePathLen >= MAX_PATH) {
        return E_FAIL;
    }

    // Never register through HKEY_CLASSES_ROOT: it is a merged HKLM/HKCU view,
    // so a per-user shadow can redirect writes away from machine ownership.
    // Process architecture still selects the corresponding COM registry view.
    wstring regPath = L"SOFTWARE\\Classes\\CLSID\\";
    LPOLESTR clsidStr = NULL;
    if(StringFromCLSID(textServiceClsid_, &clsidStr) != ERROR_SUCCESS)
        return E_FAIL;
    regPath += clsidStr;
    CoTaskMemFree(clsidStr);

    HKEY hkey = NULL;
    if(::RegCreateKeyExW(HKEY_LOCAL_MACHINE, regPath.c_str(), 0, NULL, REG_OPTION_NON_VOLATILE, KEY_WRITE, NULL, &hkey, NULL) == ERROR_SUCCESS) {
        // write name of our IME
        if(::RegSetValueExW(hkey, NULL, 0, REG_SZ, (BYTE*)imeName,
            sizeof(wchar_t) * (wcslen(imeName) + 1)) != ERROR_SUCCESS) {
            result = E_FAIL;
        }

        HKEY inProcServer32Key;
        if(::RegCreateKeyExW(hkey, L"InprocServer32", 0, NULL, REG_OPTION_NON_VOLATILE, KEY_WRITE, NULL, &inProcServer32Key, NULL) == ERROR_SUCCESS) {
            // store the path of our dll module in the registry
            if(::RegSetValueExW(inProcServer32Key, NULL, 0, REG_SZ, (BYTE*)modulePath,
                (modulePathLen + 1) * sizeof(wchar_t)) != ERROR_SUCCESS) {
                result = E_FAIL;
            }
            // write threading model
            wchar_t apartmentStr[] = L"Apartment";
            if(::RegSetValueExW(inProcServer32Key, L"ThreadingModel", 0, REG_SZ,
                (BYTE*)apartmentStr, 10 * sizeof(wchar_t)) != ERROR_SUCCESS) {
                result = E_FAIL;
            }
            ::RegCloseKey(inProcServer32Key);
        }
        else
            result = E_FAIL;
        ::RegCloseKey(hkey);
    }
    else
        result = E_FAIL;

    // register language profiles
    if(result == S_OK && ownsSharedTsfRegistration) {
        result = registerLangProfiles(langs, count);
    }

    // register category
    if(result == S_OK && ownsSharedTsfRegistration) {
        ITfCategoryMgr *categoryMgr = NULL;
        if(CoCreateInstance(CLSID_TF_CategoryMgr, NULL, CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr, (void**)&categoryMgr) == S_OK) {
            if(categoryMgr->RegisterCategory(textServiceClsid_, GUID_TFCAT_TIP_KEYBOARD, textServiceClsid_) != S_OK) {
                result = E_FAIL;
            }

            // register ourself as a display attribute provider
            // so later we can set change the look and feels of composition string.
            if(categoryMgr->RegisterCategory(textServiceClsid_, GUID_TFCAT_DISPLAYATTRIBUTEPROVIDER, textServiceClsid_) != S_OK) {
                result = E_FAIL;
            }

            // enable UI less mode
            if(categoryMgr->RegisterCategory(textServiceClsid_, GUID_TFCAT_TIPCAP_INPUTMODECOMPARTMENT, textServiceClsid_) != S_OK ||
                categoryMgr->RegisterCategory(textServiceClsid_, GUID_TFCAT_TIPCAP_UIELEMENTENABLED, textServiceClsid_) != S_OK) {
                result  = E_FAIL;
            }

            if(::IsWindows8OrGreater()) {
                // for Windows 8 store app support
                // TODO: according to a exhaustive Google search, I found that
                // TF_IPP_CAPS_IMMERSIVESUPPORT is required to make the IME work with Windows 8.
                // http://social.msdn.microsoft.com/Forums/windowsapps/en-US/4c422cf1-ceb4-413b-8a7c-6881946a4c63/how-to-set-a-flag-indicating-tsf-components-compatibility
                // Quote from the page: "To indicate that your IME is compatible with Windows Store apps, call RegisterCategory with GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT."

                // declare supporting immersive mode
                if(categoryMgr->RegisterCategory(textServiceClsid_, GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT, textServiceClsid_) != S_OK) {
                    result = E_FAIL;
                }

                // declare compatibility with Windows 8 system tray
                if(categoryMgr->RegisterCategory(textServiceClsid_, GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT, textServiceClsid_) != S_OK) {
                    result = E_FAIL;
                }
            }

            categoryMgr->Release();
        }
        else {
            result = E_FAIL;
        }
    }
    return result;
}

HRESULT ImeModule::unregisterServer(bool ownsSharedTsfRegistration) {
    HRESULT result = S_OK;

    // HKLM\SOFTWARE\Microsoft\CTF\TIP is shared across WOW64 views. Only the
    // native x64/ARM64 DLL owns Profile/categories; the x86 DLL removes only its
    // redirected COM registration. Remove categories before the profile, as in
    // the Microsoft TSF registration sample, so category cleanup still has its
    // registered item to address.
    if(ownsSharedTsfRegistration) {
        ITfCategoryMgr *categoryMgr = NULL;
        if(CoCreateInstance(CLSID_TF_CategoryMgr, NULL, CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr, (void**)&categoryMgr) == S_OK) {
            if(categoryMgr->UnregisterCategory(textServiceClsid_, GUID_TFCAT_TIP_KEYBOARD, textServiceClsid_) != S_OK) {
                result = E_FAIL;
            }
            if(categoryMgr->UnregisterCategory(textServiceClsid_, GUID_TFCAT_DISPLAYATTRIBUTEPROVIDER, textServiceClsid_) != S_OK) {
                result = E_FAIL;
            }
            if(categoryMgr->UnregisterCategory(textServiceClsid_, GUID_TFCAT_TIPCAP_INPUTMODECOMPARTMENT, textServiceClsid_) != S_OK) {
                result = E_FAIL;
            }
            if(categoryMgr->UnregisterCategory(textServiceClsid_, GUID_TFCAT_TIPCAP_UIELEMENTENABLED, textServiceClsid_) != S_OK) {
                result = E_FAIL;
            }
            if(::IsWindows8OrGreater()) {
                if(categoryMgr->UnregisterCategory(textServiceClsid_, GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT, textServiceClsid_) != S_OK) {
                    result = E_FAIL;
                }
                if(categoryMgr->UnregisterCategory(textServiceClsid_, GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT, textServiceClsid_) != S_OK) {
                    result = E_FAIL;
                }
            }
            categoryMgr->Release();
        }
        else {
            result = E_FAIL;
        }
        ITfInputProcessorProfiles *inputProcessProfiles = NULL;
        if(CoCreateInstance(CLSID_TF_InputProcessorProfiles, NULL, CLSCTX_INPROC_SERVER,
            IID_ITfInputProcessorProfiles, (void**)&inputProcessProfiles) == S_OK) {
            if(inputProcessProfiles->Unregister(textServiceClsid_) != S_OK) {
                result = E_FAIL;
            }
            inputProcessProfiles->Release();
        }
        else {
            result = E_FAIL;
        }
    }

    // delete the registry key
    // Delete only the machine COM registration written by registerServer().
    // A user-level shadow is foreign state and is rejected by installer guards.
    wstring regPath = L"SOFTWARE\\Classes\\CLSID\\";
    LPOLESTR clsidStr = NULL;
    if(StringFromCLSID(textServiceClsid_, &clsidStr) == ERROR_SUCCESS) {
        regPath += clsidStr;
        CoTaskMemFree(clsidStr);
        const LSTATUS deleteResult = ::SHDeleteKey(HKEY_LOCAL_MACHINE, regPath.c_str());
        if(deleteResult != ERROR_SUCCESS && deleteResult != ERROR_FILE_NOT_FOUND &&
            deleteResult != ERROR_PATH_NOT_FOUND) {
            result = E_FAIL;
        }
    }
    else {
        result = E_FAIL;
    }

    return result;
}


// display attributes stuff
bool ImeModule::registerDisplayAttributeInfos() {

    // register display attributes
    ComPtr<ITfCategoryMgr> categoryMgr;
    if(::CoCreateInstance(CLSID_TF_CategoryMgr, NULL, CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr, (void**)&categoryMgr) == S_OK) {
        TfGuidAtom atom;
        categoryMgr->RegisterGUID(g_inputDisplayAttributeGuid, &atom);
        inputAttrib_->setAtom(atom);
        // categoryMgr->RegisterGUID(g_convertedDisplayAttributeGuid, &atom);
        // convertedAttrib_->setAtom(atom);
        return true;
    }
    return false;
}


// virtual
bool ImeModule::onConfigure(HWND hwndParent, LANGID langid, REFGUID rguidProfile) {
    return true;
}


// COM related stuff

// IUnknown
STDMETHODIMP_(ULONG) ImeModule::AddRef(void) {
    // In the examples of MS TSF, a critical section is used to protect the ref count
    // of the Dll but the document didn't explain the reason. Since in our design
    // the life-cycle of the ImeModule object and the Dll are tied together,
    // we protect the ref count of ImeModule with a mutex.
    std::lock_guard <std::mutex> lock{refCountMutex_};
    return ComObject::AddRef();
}

STDMETHODIMP_(ULONG) ImeModule::Release(void) {
    // In the examples of MS TSF, a critical section is used to protect the ref count
    // of the Dll but the document didn't explain the reason. Since in our design
    // the life-cycle of the ImeModule object and the Dll are tied together,
    // we protect the ref count of ImeModule with a mutex.
    std::lock_guard <std::mutex> lock{ refCountMutex_ };
    return ComObject::Release();
}

// IClassFactory
STDMETHODIMP ImeModule::CreateInstance(IUnknown *pUnkOuter, REFIID riid, void **ppvObj) {
    *ppvObj = NULL;
    if(::IsEqualIID(riid, IID_ITfDisplayAttributeProvider)) {
        auto provider = ComPtr<DisplayAttributeProvider>::make(this);
        if(provider) {
            provider->QueryInterface(riid, ppvObj);
        }
    }
    else if(::IsEqualIID(riid, IID_ITfFnConfigure)) {
        // ourselves implement this interface.
        this->QueryInterface(riid, ppvObj);
    }
    else {
        TextService* service = createTextService();
        if(service) {
            service->QueryInterface(riid, ppvObj);
            service->Release();
        }
    }
    return *ppvObj ? S_OK : E_NOINTERFACE;
}

STDMETHODIMP ImeModule::LockServer(BOOL fLock) {
    if (fLock) {
        AddRef();
    }
    else {
        Release();
    }
    return S_OK;
}

// ITfFnConfigure
STDMETHODIMP ImeModule::Show(HWND hwndParent, LANGID langid, REFGUID rguidProfile) {
    return onConfigure(hwndParent, langid, rguidProfile) ? S_OK : E_FAIL;
}

// ITfFunction
STDMETHODIMP ImeModule::GetDisplayName(BSTR *pbstrName) {
    *pbstrName = ::SysAllocString(L"Configuration");
    return S_OK;
}

} // namespace Ime
