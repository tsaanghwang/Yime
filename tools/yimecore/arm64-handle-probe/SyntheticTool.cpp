#define WIDEN_IMPL(value) L##value
#define WIDEN(value) WIDEN_IMPL(value)
#define STRINGIFY_IMPL(value) #value
#define STRINGIFY(value) STRINGIFY_IMPL(value)

#include <windows.h>
#include <psapi.h>
#include <iostream>
#include <string>
#include <vector>

namespace {
constexpr DWORD kWaitMilliseconds = 30000;

int actor(int argc, wchar_t** argv) {
    if (argc != 6) return 2;
    HANDLE ready = OpenEventW(EVENT_MODIFY_STATE, FALSE, argv[3]);
    HANDLE go = OpenEventW(SYNCHRONIZE, FALSE, argv[4]);
    if (!ready || !go) return 3;
    if (!SetEvent(ready) || WaitForSingleObject(go, kWaitMilliseconds) != WAIT_OBJECT_0) {
        CloseHandle(ready); CloseHandle(go); return 4;
    }
    CloseHandle(ready); CloseHandle(go);
    HANDLE writer = CreateFileW(argv[2], GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    const DWORD writeError = writer == INVALID_HANDLE_VALUE ? GetLastError() : 0;
    if (writer != INVALID_HANDLE_VALUE) CloseHandle(writer);
    HANDLE deleting = CreateFileW(argv[2], DELETE, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                  nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    const DWORD deleteError = deleting == INVALID_HANDLE_VALUE ? GetLastError() : 0;
    if (deleting != INVALID_HANDLE_VALUE) CloseHandle(deleting);
    const BOOL moved = MoveFileExW(argv[2], argv[5], MOVEFILE_WRITE_THROUGH);
    const DWORD renameError = moved ? 0 : GetLastError();
    std::wcout << L"WRITE_ERROR=" << writeError << L"\nDELETE_ERROR=" << deleteError
               << L"\nRENAME_ERROR=" << renameError << L"\n";
    return (writeError == ERROR_SHARING_VIOLATION && deleteError == ERROR_SHARING_VIOLATION &&
            renameError == ERROR_SHARING_VIOLATION) ? 0 : 5;
}

int loadDll(const wchar_t* path) {
    if (!SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_SYSTEM32)) return 9;
    HMODULE module = LoadLibraryExW(path, nullptr,
                                   LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!module) return 6;
    auto marker = reinterpret_cast<const wchar_t* (*)()>(GetProcAddress(module, "SyntheticMarker"));
    if (!marker) { FreeLibrary(module); return 7; }
    std::vector<wchar_t> imagePath(32768);
    std::vector<wchar_t> mappedPath(32768);
    const DWORD imageLength = GetModuleFileNameW(module, imagePath.data(), static_cast<DWORD>(imagePath.size()));
    const DWORD mappedLength = GetMappedFileNameW(GetCurrentProcess(), module, mappedPath.data(),
                                                   static_cast<DWORD>(mappedPath.size()));
    if (!imageLength || imageLength >= static_cast<DWORD>(imagePath.size()) ||
        !mappedLength || mappedLength >= static_cast<DWORD>(mappedPath.size())) {
        FreeLibrary(module); return 8;
    }
    std::wcout << L"TOOL_MARKER=" << WIDEN(STRINGIFY(SYNTHETIC_MARKER)) << L"\nDLL_MARKER=" << marker()
               << L"\nDLL_MODULE_PATH=" << imagePath.data() << L"\nDLL_MAPPED_PATH=" << mappedPath.data() << L"\n";
    FreeLibrary(module);
    return 0;
}
}

int wmain(int argc, wchar_t** argv) {
    if (argc == 1) {
        std::wcout << L"TOOL_MARKER=" << WIDEN(STRINGIFY(SYNTHETIC_MARKER)) << L"\n";
        return 0;
    }
    const std::wstring mode = argv[1];
    if (mode == L"--actor") return actor(argc, argv);
    if (mode == L"--load-dll" && argc == 3) return loadDll(argv[2]);
    return 2;
}
