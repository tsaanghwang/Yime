#include <windows.h>
#include <msctf.h>
#include <VersionHelpers.h>

#include <iostream>
#include <string>

namespace {

constexpr LANGID kLanguageId = MAKELANGID(LANG_CHINESE, SUBLANG_CHINESE_SIMPLIFIED);
constexpr wchar_t kProfileName[] = L"音元";
#if defined(_M_ARM64)
constexpr wchar_t kArchitecture[] = L"arm64";
#elif defined(_M_X64)
constexpr wchar_t kArchitecture[] = L"x64";
#elif defined(_M_IX86)
constexpr wchar_t kArchitecture[] = L"x86";
#else
#error Unsupported PIMERegistrationStatus architecture
#endif

// Rime/PIME text service {35f67e9d-a54d-4177-9697-8b0ab71a9e04}.
const GUID kTextServiceClsid =
{ 0x35f67e9d, 0xa54d, 0x4177, { 0x96, 0x97, 0x8b, 0x0a, 0xb7, 0x1a, 0x9e, 0x04 } };

// Yime profile {3f6b5a12-8d44-4e71-9a2e-6b4f9c1d2a30}.
const GUID kProfileGuid =
{ 0x3f6b5a12, 0x8d44, 0x4e71, { 0x9a, 0x2e, 0x6b, 0x4f, 0x9c, 0x1d, 0x2a, 0x30 } };

// These two Windows 8+ TSF categories are absent from some older SDK headers.
const GUID kTipcapImmersiveSupport =
{ 0x13a016df, 0x560b, 0x46cd, { 0x94, 0x7a, 0x4c, 0x3a, 0xf1, 0xe0, 0xe3, 0x5d } };
const GUID kTipcapSystraySupport =
{ 0x25504fb4, 0x7bab, 0x4bc1, { 0x9c, 0x69, 0xcf, 0x81, 0x89, 0x0f, 0x0e, 0xf5 } };

const GUID* const kCategories[] = {
    &GUID_TFCAT_TIP_KEYBOARD,
    &GUID_TFCAT_DISPLAYATTRIBUTEPROVIDER,
    &GUID_TFCAT_TIPCAP_INPUTMODECOMPARTMENT,
    &GUID_TFCAT_TIPCAP_UIELEMENTENABLED,
    &kTipcapImmersiveSupport,  // GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT
    &kTipcapSystraySupport,   // GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT
};

constexpr unsigned kCategoryCapacity = sizeof(kCategories) / sizeof(kCategories[0]);

unsigned expectedCategoryCount() {
    // Keep this threshold identical to ImeModule's registration branches:
    // Vista/Windows 7 own the four base categories; Windows 8+ owns all six.
    return IsWindows8OrGreater() ? kCategoryCapacity : 4;
}

struct ProfileRegistrationState {
    unsigned serviceProfileCount = 0;
    unsigned exactProfileCount = 0;
};

struct CategoryRegistrationState {
    unsigned totalCount = 0;
    unsigned expectedCount = 0;
    bool exactSet = false;
};

HRESULT profileRegistrationState(ProfileRegistrationState* state) {
    if (!state) return E_POINTER;
    *state = {};

    ITfInputProcessorProfileMgr* profiles = nullptr;
    HRESULT result = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                                      __uuidof(ITfInputProcessorProfileMgr),
                                      reinterpret_cast<void**>(&profiles));
    if (FAILED(result)) return result;

    // langid=0 enumerates every profile. Limiting this query to the current
    // language list could miss an orphan profile registered for another LANGID.
    IEnumTfInputProcessorProfiles* values = nullptr;
    result = profiles->EnumProfiles(0, &values);
    profiles->Release();
    if (FAILED(result)) return result;
    if (!values) return E_UNEXPECTED;
    for (;;) {
        TF_INPUTPROCESSORPROFILE value{};
        ULONG fetched = 0;
        const HRESULT next = values->Next(1, &value, &fetched);
        if (next == S_FALSE) {
            result = fetched == 0 ? S_OK : E_UNEXPECTED;
            break;
        }
        if (FAILED(next)) {
            result = next;
            break;
        }
        if (next != S_OK || fetched != 1) {
            result = E_UNEXPECTED;
            break;
        }
        if (IsEqualGUID(value.clsid, kTextServiceClsid)) {
            ++state->serviceProfileCount;
            if (value.dwProfileType == TF_PROFILETYPE_INPUTPROCESSOR &&
                value.langid == kLanguageId && IsEqualGUID(value.guidProfile, kProfileGuid)) {
                ++state->exactProfileCount;
            }
        }
    }
    values->Release();
    return result;
}

HRESULT profileDescriptionMatches(bool* matches) {
    if (!matches) return E_POINTER;
    *matches = false;
    ITfInputProcessorProfiles* profiles = nullptr;
    HRESULT result = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                                      IID_ITfInputProcessorProfiles,
                                      reinterpret_cast<void**>(&profiles));
    if (FAILED(result)) return result;
    BSTR description = nullptr;
    result = profiles->GetLanguageProfileDescription(kTextServiceClsid, kLanguageId,
                                                      kProfileGuid, &description);
    profiles->Release();
    if (SUCCEEDED(result) && description) {
        *matches = std::wstring(description, SysStringLen(description)) == kProfileName;
    }
    if (description) SysFreeString(description);
    return result;
}

HRESULT profileIsEnabled(bool* enabled) {
    if (!enabled) return E_POINTER;
    *enabled = false;
    ITfInputProcessorProfiles* profiles = nullptr;
    HRESULT result = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                                      IID_ITfInputProcessorProfiles,
                                      reinterpret_cast<void**>(&profiles));
    if (FAILED(result)) return result;
    BOOL value = FALSE;
    result = profiles->IsEnabledLanguageProfile(kTextServiceClsid, kLanguageId,
                                                kProfileGuid, &value);
    profiles->Release();
    if (SUCCEEDED(result)) *enabled = value != FALSE;
    return result;
}

HRESULT categoryRegistrationState(CategoryRegistrationState* state) {
    if (!state) return E_POINTER;
    *state = {};
    ITfCategoryMgr* categories = nullptr;
    HRESULT result = CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER,
                                      __uuidof(ITfCategoryMgr),
                                      reinterpret_cast<void**>(&categories));
    if (FAILED(result)) return result;

    IEnumGUID* values = nullptr;
    result = categories->EnumCategoriesInItem(kTextServiceClsid, &values);
    categories->Release();
    if (FAILED(result)) return result;
    if (!values) return E_UNEXPECTED;

    const unsigned expectedCategoryTotal = expectedCategoryCount();
    bool expectedSeen[kCategoryCapacity] = {};
    for (;;) {
        GUID value{};
        ULONG fetched = 0;
        const HRESULT next = values->Next(1, &value, &fetched);
        if (next == S_FALSE) {
            result = fetched == 0 ? S_OK : E_UNEXPECTED;
            break;
        }
        if (FAILED(next)) {
            result = next;
            break;
        }
        if (next != S_OK || fetched != 1) {
            result = E_UNEXPECTED;
            break;
        }
        ++state->totalCount;
        for (unsigned index = 0; index < expectedCategoryTotal; ++index) {
            if (IsEqualGUID(value, *kCategories[index])) {
                if (expectedSeen[index]) {
                    result = E_UNEXPECTED;
                } else {
                    expectedSeen[index] = true;
                    ++state->expectedCount;
                }
                break;
            }
        }
        if (FAILED(result)) break;
    }
    values->Release();
    state->exactSet = SUCCEEDED(result) && state->totalCount == expectedCategoryTotal &&
                      state->expectedCount == expectedCategoryTotal;
    return result;
}

void writeStatus(HRESULT profileResult, const ProfileRegistrationState& profile,
                 HRESULT descriptionResult, bool descriptionMatches,
                 HRESULT enabledResult, bool profileEnabled,
                 HRESULT categoryResult, const CategoryRegistrationState& categories) {
    std::wcout << L"schema_version=yime-rime-pime-registration-status-v1\n"
               << L"architecture=" << kArchitecture << L"\n"
               << L"architecture_bits=" << sizeof(void*) * 8 << L"\n"
               << L"service_profiles_registered_count=" << profile.serviceProfileCount << L"\n"
               << L"exact_profile_registered_count=" << profile.exactProfileCount << L"\n"
               << L"profile_description_matches=" << (descriptionMatches ? L"true" : L"false") << L"\n"
               << L"profile_enabled_for_current_user=" << (profileEnabled ? L"true" : L"false") << L"\n"
               << L"categories_registered_count=" << categories.totalCount << L"\n"
               << L"expected_categories_registered_count=" << categories.expectedCount << L"\n"
               << L"category_set_exact=" << (categories.exactSet ? L"true" : L"false") << L"\n"
               << L"categories_expected_count=" << expectedCategoryCount() << L"\n"
               << L"profile_query_hresult=0x" << std::hex << std::uppercase
               << static_cast<unsigned long>(profileResult) << L"\n"
               << L"description_query_hresult=0x" << static_cast<unsigned long>(descriptionResult) << L"\n"
               << L"enabled_query_hresult=0x" << static_cast<unsigned long>(enabledResult) << L"\n"
               << L"category_query_hresult=0x" << static_cast<unsigned long>(categoryResult)
               << std::dec << L"\n"
               << L"mutation_performed=false\n";
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    const HRESULT initialized = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(initialized) && initialized != RPC_E_CHANGED_MODE) return 2;
    const bool uninitialize = SUCCEEDED(initialized);

    ProfileRegistrationState profile{};
    const HRESULT profileResult = profileRegistrationState(&profile);
    const bool exactProfileExists = profile.exactProfileCount == 1;
    bool descriptionMatches = false;
    const HRESULT descriptionResult = exactProfileExists ? profileDescriptionMatches(&descriptionMatches) : S_OK;
    bool profileEnabled = false;
    const HRESULT enabledResult = exactProfileExists ? profileIsEnabled(&profileEnabled) : S_OK;
    CategoryRegistrationState categories{};
    const HRESULT categoryResult = categoryRegistrationState(&categories);
    writeStatus(profileResult, profile, descriptionResult, descriptionMatches,
                enabledResult, profileEnabled,
                categoryResult, categories);

    int exitCode = 2;
    const bool registrationQueriesSucceeded = SUCCEEDED(profileResult) &&
                                              SUCCEEDED(descriptionResult) &&
                                              SUCCEEDED(categoryResult);
    const bool queriesSucceeded = registrationQueriesSucceeded && SUCCEEDED(enabledResult);
    const bool profileSetExact = profile.serviceProfileCount == 1 &&
                                 profile.exactProfileCount == 1;
    const bool registered = registrationQueriesSucceeded && profileSetExact &&
                            descriptionMatches && categories.exactSet;
    const bool present = queriesSucceeded && registered &&
                         profileEnabled && categories.exactSet;
    const bool disabled = queriesSucceeded && registered && !profileEnabled;
    const bool absent = queriesSucceeded && profile.serviceProfileCount == 0 &&
                        profile.exactProfileCount == 0 && categories.totalCount == 0;
    if (argc == 2 && std::wstring(argv[1]) == L"verify-registered") {
        exitCode = registered ? 0 : 7;
    } else if (argc == 2 && std::wstring(argv[1]) == L"verify-present") {
        exitCode = present ? 0 : 4;
    } else if (argc == 2 && std::wstring(argv[1]) == L"verify-disabled") {
        exitCode = disabled ? 0 : 6;
    } else if (argc == 2 && std::wstring(argv[1]) == L"verify-absent") {
        exitCode = absent ? 0 : 5;
    } else if (argc == 2 && std::wstring(argv[1]) == L"status") {
        exitCode = queriesSucceeded ? 0 : 3;
    } else {
        std::wcerr << L"usage: PIMERegistrationStatus status|verify-registered|verify-present|verify-disabled|verify-absent\n";
    }

    if (uninitialize) CoUninitialize();
    return exitCode;
}
