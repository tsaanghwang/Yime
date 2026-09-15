#include <windows.h>
#include <msctf.h>

#include <iomanip>
#include <iostream>
#include <filesystem>
#include <string>
#include <string_view>

#include "YimeTextServiceIds.h"
#include "ProductIdentity.h"

namespace {

constexpr LANGID kLanguageId = MAKELANGID(LANG_CHINESE, SUBLANG_CHINESE_SIMPLIFIED);
constexpr wchar_t kProfileName[] = YIME_PRODUCT_NAME;
constexpr const GUID* kTipCategories[] = {
    &GUID_TFCAT_TIP_KEYBOARD,
    &GUID_TFCAT_TIPCAP_UIELEMENTENABLED,
    &GUID_TFCAT_TIPCAP_INPUTMODECOMPARTMENT,
    &GUID_YimeTipcapImmersiveSupport,
    &GUID_YimeTipcapSystraySupport,
};

std::wstring guidText(REFGUID guid) {
    wchar_t value[39]{};
    return StringFromGUID2(guid, value, static_cast<int>(std::size(value))) > 0 ? value : L"";
}

REGSAM registryView() {
    return sizeof(void*) == 8 ? KEY_WOW64_64KEY : KEY_WOW64_32KEY;
}

std::wstring comRegistryPath() {
    return L"SOFTWARE\\Classes\\CLSID\\" + guidText(CLSID_YimeTextServiceExperiment) + L"\\InprocServer32";
}

bool isElevated() {
    HANDLE token = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return false;
    TOKEN_ELEVATION elevation{};
    DWORD returned = 0;
    const bool elevated = GetTokenInformation(token, TokenElevation, &elevation, sizeof(elevation), &returned) &&
                          elevation.TokenIsElevated != 0;
    CloseHandle(token);
    return elevated;
}

bool comRegistrationExists() {
    HKEY key = nullptr;
    const LSTATUS status = RegOpenKeyExW(HKEY_LOCAL_MACHINE, comRegistryPath().c_str(), 0,
                                         KEY_READ | registryView(), &key);
    if (key) RegCloseKey(key);
    return status == ERROR_SUCCESS;
}

HRESULT profileRegistrationExists(bool* exists) {
    if (!exists) return E_POINTER;
    *exists = false;
    ITfInputProcessorProfileMgr* profiles = nullptr;
    HRESULT result = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                                      __uuidof(ITfInputProcessorProfileMgr), reinterpret_cast<void**>(&profiles));
    if (FAILED(result)) return result;
    IEnumTfInputProcessorProfiles* values = nullptr;
    result = profiles->EnumProfiles(kLanguageId, &values);
    profiles->Release();
    if (FAILED(result)) return result;
    TF_INPUTPROCESSORPROFILE value{};
    ULONG fetched = 0;
    while (values->Next(1, &value, &fetched) == S_OK && fetched == 1) {
        if (value.dwProfileType == TF_PROFILETYPE_INPUTPROCESSOR &&
            IsEqualGUID(value.clsid, CLSID_YimeTextServiceExperiment) &&
            IsEqualGUID(value.guidProfile, GUID_YimeTextServiceExperimentProfile)) {
            *exists = true;
            break;
        }
    }
    values->Release();
    return S_OK;
}

HRESULT categoryRegistrationCount(unsigned* count) {
    if (!count) return E_POINTER;
    *count = 0;
    ITfCategoryMgr* categories = nullptr;
    HRESULT result = CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER,
                                      __uuidof(ITfCategoryMgr), reinterpret_cast<void**>(&categories));
    if (FAILED(result)) return result;
    for (const GUID* category : kTipCategories) {
        IEnumGUID* values = nullptr;
        result = categories->EnumItemsInCategory(*category, &values);
        if (FAILED(result)) break;
        GUID value{};
        ULONG fetched = 0;
        while (values->Next(1, &value, &fetched) == S_OK && fetched == 1) {
            if (IsEqualGUID(value, CLSID_YimeTextServiceExperiment)) {
                ++*count;
                break;
            }
        }
        values->Release();
    }
    categories->Release();
    return result;
}

HRESULT registerComServer(const wchar_t* dllPath) {
    if (!dllPath || !*dllPath) return E_INVALIDARG;
    wchar_t fullPath[MAX_PATH]{};
    const DWORD length = GetFullPathNameW(dllPath, static_cast<DWORD>(std::size(fullPath)), fullPath, nullptr);
    if (!length || length >= std::size(fullPath)) return HRESULT_FROM_WIN32(GetLastError());
    if (GetFileAttributesW(fullPath) == INVALID_FILE_ATTRIBUTES) return HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND);

    HKEY key = nullptr;
    const LSTATUS created = RegCreateKeyExW(HKEY_LOCAL_MACHINE, comRegistryPath().c_str(), 0, nullptr,
                                            REG_OPTION_NON_VOLATILE, KEY_WRITE | registryView(), nullptr, &key, nullptr);
    if (created != ERROR_SUCCESS) return HRESULT_FROM_WIN32(created);
    const DWORD pathBytes = static_cast<DWORD>((wcslen(fullPath) + 1) * sizeof(wchar_t));
    LSTATUS status = RegSetValueExW(key, nullptr, 0, REG_SZ,
                                    reinterpret_cast<const BYTE*>(fullPath), pathBytes);
    constexpr wchar_t threadingModel[] = L"Apartment";
    if (status == ERROR_SUCCESS) {
        status = RegSetValueExW(key, L"ThreadingModel", 0, REG_SZ,
                                reinterpret_cast<const BYTE*>(threadingModel), sizeof(threadingModel));
    }
    RegCloseKey(key);
    return status == ERROR_SUCCESS ? S_OK : HRESULT_FROM_WIN32(status);
}

HRESULT unregisterComServer() {
    HKEY parent = nullptr;
    const LSTATUS opened = RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Classes\\CLSID", 0,
                                         KEY_READ | KEY_WRITE | registryView(), &parent);
    if (opened == ERROR_FILE_NOT_FOUND) return S_OK;
    if (opened != ERROR_SUCCESS) return HRESULT_FROM_WIN32(opened);
    const std::wstring clsid = guidText(CLSID_YimeTextServiceExperiment);
    const LSTATUS removed = RegDeleteTreeW(parent, clsid.c_str());
    RegCloseKey(parent);
    return removed == ERROR_SUCCESS || removed == ERROR_FILE_NOT_FOUND ? S_OK : HRESULT_FROM_WIN32(removed);
}

HRESULT registerProfileAndCategories(const wchar_t* dllPath) {
    if (!dllPath || !*dllPath) return E_INVALIDARG;
    const std::filesystem::path profileIcon =
        std::filesystem::absolute(dllPath).parent_path().parent_path() / L"profile-icon.ico";
    if (!std::filesystem::is_regular_file(profileIcon)) {
        return HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND);
    }
    ITfInputProcessorProfileMgr* profiles = nullptr;
    HRESULT result = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                                      __uuidof(ITfInputProcessorProfileMgr), reinterpret_cast<void**>(&profiles));
    if (FAILED(result)) return result;
    profiles->UnregisterProfile(CLSID_YimeTextServiceExperiment, kLanguageId,
                                GUID_YimeTextServiceExperimentProfile, 0);
    result = profiles->RegisterProfile(
        CLSID_YimeTextServiceExperiment, kLanguageId, GUID_YimeTextServiceExperimentProfile,
        kProfileName, static_cast<ULONG>(std::size(kProfileName) - 1), profileIcon.c_str(),
        static_cast<ULONG>(profileIcon.native().size()), 0,
        nullptr, 0, TRUE, 0);
    profiles->Release();
    if (FAILED(result)) return result;

    ITfCategoryMgr* categories = nullptr;
    result = CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER,
                              __uuidof(ITfCategoryMgr), reinterpret_cast<void**>(&categories));
    if (FAILED(result)) return result;
    for (const GUID* category : kTipCategories) {
        result = categories->RegisterCategory(CLSID_YimeTextServiceExperiment, *category,
                                              CLSID_YimeTextServiceExperiment);
        if (FAILED(result)) break;
    }
    categories->Release();
    return result;
}

HRESULT unregisterProfileAndCategories() {
    HRESULT firstFailure = S_OK;
    ITfCategoryMgr* categories = nullptr;
    HRESULT result = CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER,
                                      __uuidof(ITfCategoryMgr), reinterpret_cast<void**>(&categories));
    if (SUCCEEDED(result)) {
        for (const GUID* category : kTipCategories) {
            result = categories->UnregisterCategory(CLSID_YimeTextServiceExperiment, *category,
                                                    CLSID_YimeTextServiceExperiment);
            if (FAILED(result) && SUCCEEDED(firstFailure)) firstFailure = result;
        }
        categories->Release();
    } else {
        firstFailure = result;
    }
    ITfInputProcessorProfileMgr* profiles = nullptr;
    result = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                              __uuidof(ITfInputProcessorProfileMgr), reinterpret_cast<void**>(&profiles));
    if (SUCCEEDED(result)) {
        result = profiles->UnregisterProfile(CLSID_YimeTextServiceExperiment, kLanguageId,
                                             GUID_YimeTextServiceExperimentProfile, 0);
        if (FAILED(result) && SUCCEEDED(firstFailure)) firstFailure = result;
        profiles->Release();
    } else if (SUCCEEDED(firstFailure)) {
        firstFailure = result;
    }
    return firstFailure;
}

HRESULT unregisterAll() {
    const HRESULT profileResult = unregisterProfileAndCategories();
    const HRESULT comResult = unregisterComServer();
    return FAILED(profileResult) ? profileResult : comResult;
}

HRESULT registerAll(const wchar_t* dllPath) {
    bool profileExists = false;
    unsigned categoryCount = 0;
    HRESULT result = profileRegistrationExists(&profileExists);
    if (SUCCEEDED(result)) result = categoryRegistrationCount(&categoryCount);
    if (FAILED(result)) return result;
    if (comRegistrationExists() || profileExists || categoryCount != 0) {
        return HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS);
    }
    result = registerComServer(dllPath);
    if (SUCCEEDED(result)) result = registerProfileAndCategories(dllPath);
    if (FAILED(result)) unregisterAll();
    return result;
}

HRESULT repointComServer(const wchar_t* dllPath) {
    bool profileExists = false;
    unsigned categoryCount = 0;
    HRESULT result = profileRegistrationExists(&profileExists);
    if (SUCCEEDED(result)) result = categoryRegistrationCount(&categoryCount);
    if (FAILED(result)) return result;
    if (!profileExists || categoryCount != std::size(kTipCategories)) {
        return HRESULT_FROM_WIN32(ERROR_NOT_FOUND);
    }
    return registerComServer(dllPath);
}

void writeStatus() {
    bool profileExists = false;
    const HRESULT profileStatus = profileRegistrationExists(&profileExists);
    unsigned categoryCount = 0;
    const HRESULT categoryStatus = categoryRegistrationCount(&categoryCount);
    std::wcout << L"tool_version=yime-text-service-registration-v2\n"
               << L"architecture_bits=" << sizeof(void*) * 8 << L"\n"
               << L"elevated=" << (isElevated() ? L"true" : L"false") << L"\n"
               << L"clsid=" << guidText(CLSID_YimeTextServiceExperiment) << L"\n"
               << L"profile_guid=" << guidText(GUID_YimeTextServiceExperimentProfile) << L"\n"
               << L"language_bar_guid=" << guidText(GUID_YimeTextServiceExperimentLangBar) << L"\n"
               << L"com_only_registration_supported=true\n"
               << L"profile_icon_registration_supported=true\n"
               << L"taskbar_category_registration_supported=true\n"
               << L"com_registered_current_view=" << (comRegistrationExists() ? L"true" : L"false") << L"\n"
               << L"profile_registered=" << (profileExists ? L"true" : L"false") << L"\n"
               << L"categories_registered_count=" << categoryCount << L"\n"
               << L"profile_query_hresult=0x" << std::hex << std::uppercase << static_cast<unsigned long>(profileStatus)
               << L"\ncategory_query_hresult=0x" << static_cast<unsigned long>(categoryStatus)
               << std::dec << L"\n"
               << L"mutation_performed=false\n";
}

void writeResult(std::wstring_view operation, HRESULT result) {
    std::wcout << L"operation=" << operation << L"\n"
               << L"hresult=0x" << std::hex << std::uppercase << static_cast<unsigned long>(result) << std::dec << L"\n"
               << L"succeeded=" << (SUCCEEDED(result) ? L"true" : L"false") << L"\n";
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    const HRESULT initialized = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(initialized) && initialized != RPC_E_CHANGED_MODE) {
        writeResult(L"initialize", initialized);
        return 2;
    }
    const bool uninitialize = SUCCEEDED(initialized);
    int exitCode = 0;
    if (argc == 2 && std::wstring_view(argv[1]) == L"status") {
        writeStatus();
    } else if (argc == 2 && std::wstring_view(argv[1]) == L"verify-absent") {
        bool profileExists = false;
        const HRESULT queried = profileRegistrationExists(&profileExists);
        unsigned categoryCount = 0;
        const HRESULT categoriesQueried = categoryRegistrationCount(&categoryCount);
        writeStatus();
        exitCode = FAILED(queried) || FAILED(categoriesQueried) ? 2 :
                   (comRegistrationExists() || profileExists || categoryCount != 0 ? 4 : 0);
    } else if (argc == 3 && std::wstring_view(argv[1]) == L"register") {
        if (!isElevated()) {
            std::wcout << L"operation=register\nblocked=requires_elevated_token\nmutation_performed=false\n";
            exitCode = 3;
        } else {
            const HRESULT result = registerAll(argv[2]);
            writeResult(L"register", result);
            exitCode = SUCCEEDED(result) ? 0 : 5;
        }
    } else if (argc == 3 && std::wstring_view(argv[1]) == L"repoint") {
        if (!isElevated()) {
            std::wcout << L"operation=repoint\nblocked=requires_elevated_token\nmutation_performed=false\n";
            exitCode = 3;
        } else {
            const HRESULT result = repointComServer(argv[2]);
            writeResult(L"repoint", result);
            exitCode = SUCCEEDED(result) ? 0 : 7;
        }
    } else if (argc == 3 && std::wstring_view(argv[1]) == L"register-com") {
        if (!isElevated()) {
            std::wcout << L"operation=register-com\nblocked=requires_elevated_token\nmutation_performed=false\n";
            exitCode = 3;
        } else {
            const HRESULT result = registerComServer(argv[2]);
            writeResult(L"register-com", result);
            exitCode = SUCCEEDED(result) ? 0 : 8;
        }
    } else if (argc == 2 && std::wstring_view(argv[1]) == L"unregister") {
        if (!isElevated()) {
            std::wcout << L"operation=unregister\nblocked=requires_elevated_token\nmutation_performed=false\n";
            exitCode = 3;
        } else {
            const HRESULT result = unregisterAll();
            writeResult(L"unregister", result);
            exitCode = SUCCEEDED(result) ? 0 : 6;
        }
    } else {
        std::wcerr << L"usage: YimeTextServiceRegistration status|verify-absent|register <dll>|register-com <dll>|repoint <dll>|unregister\n";
        exitCode = 2;
    }
    if (uninitialize) CoUninitialize();
    return exitCode;
}
