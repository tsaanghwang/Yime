#include <windows.h>

#include <stdexcept>
#include <string>

namespace registry_query_test {

struct OpenObservation {
    unsigned calls = 0;
    HKEY root = nullptr;
    std::wstring path;
    DWORD options = 0;
    REGSAM access = 0;
    bool injectStatus = false;
    LSTATUS status = ERROR_SUCCESS;
};

OpenObservation opened;

// Keep real isolated registry reads for lifecycle tests, while observing the
// requested hive/view and making otherwise environment-dependent errors exact.
LSTATUS WINAPI openKey(HKEY root, LPCWSTR path, DWORD options, REGSAM access, PHKEY key) {
    ++opened.calls;
    opened.root = root;
    opened.path = path ? path : L"";
    opened.options = options;
    opened.access = access;
    if (opened.injectStatus) {
        *key = nullptr;
        return opened.status;
    }
    return RegOpenKeyExW(root, path, options, access, key);
}

}  // namespace registry_query_test

#define RegOpenKeyExW registry_query_test::openKey
#define wmain RegistrationToolEntryForTests
#include "../RegistrationTool.cpp"
#undef wmain
#undef RegOpenKeyExW

namespace {

void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

struct IsolatedRegistry {
    HKEY root = nullptr;
    bool redirected = false;
    std::wstring path = L"Software\\YimeRegistrationQueryTests\\" + std::to_wstring(GetCurrentProcessId());

    ~IsolatedRegistry() {
        if (redirected) RegOverridePredefKey(HKEY_LOCAL_MACHINE, nullptr);
        if (root) {
            RegCloseKey(root);
            RegDeleteTreeW(HKEY_CURRENT_USER, path.c_str());
        }
    }

    void initialize() {
        HKEY created = nullptr;
        DWORD disposition = 0;
        require(RegCreateKeyExW(HKEY_CURRENT_USER, path.c_str(), 0, nullptr, 0,
                                KEY_ALL_ACCESS, nullptr, &created, &disposition) == ERROR_SUCCESS,
                "create isolated registry");
        if (disposition != REG_CREATED_NEW_KEY) {
            RegCloseKey(created);
            throw std::runtime_error("test registry already exists");
        }
        root = created;
        require(RegOverridePredefKey(HKEY_LOCAL_MACHINE, root) == ERROR_SUCCESS,
                "redirect machine hive in this process only");
        redirected = true;
    }
};

std::wstring exactProfilePath() {
    return L"SOFTWARE\\Microsoft\\CTF\\TIP\\" + guidText(CLSID_YimeTextServiceExperiment) +
        L"\\LanguageProfile\\0x00000804\\" + guidText(GUID_YimeTextServiceExperimentProfile);
}

void expectQueryContract(const std::string& scenario) {
    const auto& opened = registry_query_test::opened;
    // Both architecture test binaries must request their view explicitly;
    // process-local overrides alone cannot verify WOW64 view selection.
#if defined(_WIN64)
    constexpr REGSAM expectedView = KEY_WOW64_64KEY;
#else
    constexpr REGSAM expectedView = KEY_WOW64_32KEY;
#endif
    require(registryView() == expectedView, scenario + ": registry view selector");
    require(opened.calls == 1, scenario + ": one persisted profile query");
    // A user-profile residue in HKCU must not stand in for machine registration.
    require(opened.root == HKEY_LOCAL_MACHINE, scenario + ": machine hive only");
    require(opened.path == exactProfilePath(), scenario + ": exact product/language/profile identity");
    require(opened.options == 0, scenario + ": registry open options");
    require(opened.access == (KEY_READ | expectedView), scenario + ": explicit read-only architecture view");
}

void expectProfile(bool expected, const std::string& scenario) {
    registry_query_test::opened = {};
    bool exists = !expected;
    require(profileRegistrationExists(&exists) == S_OK, scenario + ": profile query HRESULT");
    require(exists == expected, scenario + ": profile existence");
    expectQueryContract(scenario);
}

void expectRegistryError(LSTATUS status, HRESULT expected, const std::string& scenario) {
    registry_query_test::opened = {};
    registry_query_test::opened.injectStatus = true;
    registry_query_test::opened.status = status;
    bool exists = true;
    require(profileRegistrationExists(&exists) == expected, scenario + ": query HRESULT");
    require(!exists, scenario + ": output reset to absent");
    expectQueryContract(scenario);
    registry_query_test::opened = {};
}

void createProfileKey(const std::wstring& path) {
    HKEY key = nullptr;
    require(RegCreateKeyExW(HKEY_LOCAL_MACHINE, path.c_str(), 0, nullptr, 0,
                            KEY_ALL_ACCESS | registryView(), nullptr, &key, nullptr) == ERROR_SUCCESS,
            "create profile fixture");
    const DWORD disabled = 0;
    const LSTATUS status = RegSetValueExW(key, L"Enable", 0, REG_DWORD,
                                         reinterpret_cast<const BYTE*>(&disabled), sizeof(disabled));
    RegCloseKey(key);
    require(status == ERROR_SUCCESS, "disable profile fixture");
}

}  // namespace

int wmain() {
    try {
        IsolatedRegistry registry;
        registry.initialize();
        registry_query_test::opened = {};
        require(profileRegistrationExists(nullptr) == E_POINTER, "null output rejected");
        require(registry_query_test::opened.calls == 0, "null output must not open registry");
        expectProfile(false, "empty registration");

        const std::wstring service = L"SOFTWARE\\Microsoft\\CTF\\TIP\\" +
            guidText(CLSID_YimeTextServiceExperiment) + L"\\LanguageProfile\\";
        const std::wstring profile = guidText(GUID_YimeTextServiceExperimentProfile);
        createProfileKey(service + L"0x00000409\\" + profile);
        createProfileKey(service + L"0x00000804\\{00000000-0000-0000-0000-000000000000}");
        createProfileKey(L"SOFTWARE\\Microsoft\\CTF\\TIP\\{00000000-0000-0000-0000-000000000000}"
                         L"\\LanguageProfile\\0x00000804\\" + profile);
        expectProfile(false, "neighboring CLSID/language/profile excluded");

        const std::wstring exact = exactProfilePath();
        createProfileKey(exact);
        expectProfile(true, "new profile detected before enablement");
        require(RegDeleteTreeW(HKEY_LOCAL_MACHINE, exact.c_str()) == ERROR_SUCCESS, "remove profile fixture");
        expectProfile(false, "removed profile immediately absent");
        createProfileKey(exact);
        expectProfile(true, "recreated profile immediately present");

        expectRegistryError(ERROR_FILE_NOT_FOUND, S_OK, "missing registry key");
        expectRegistryError(ERROR_PATH_NOT_FOUND, S_OK, "missing registry path");
        expectRegistryError(ERROR_ACCESS_DENIED, HRESULT_FROM_WIN32(ERROR_ACCESS_DENIED), "access denied propagates");
        expectRegistryError(ERROR_INVALID_HANDLE, HRESULT_FROM_WIN32(ERROR_INVALID_HANDLE), "other registry errors propagate");
        std::cout << "PASS: architecture_bits=" << sizeof(void*) * 8
                  << "; exact machine profile; disabled/new profile; neighboring identities; "
                     "immediate removal/recreation; null output; explicit WOW64 view; registry error propagation\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << "\n";
        return 1;
    }
}
