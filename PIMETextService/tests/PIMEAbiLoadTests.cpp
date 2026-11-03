#include <windows.h>
#include <iostream>

int wmain(int argc, wchar_t** argv) {
    if (argc != 2) return 2;
    USHORT process = 0, native = 0;
    using QueryMachine = BOOL (WINAPI*)(HANDLE, USHORT*, USHORT*);
    const auto query = reinterpret_cast<QueryMachine>(GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "IsWow64Process2"));
    if (!query || !query(GetCurrentProcess(), &process, &native)) return 3;
    HMODULE module = LoadLibraryExW(argv[1], nullptr,
        LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!module) {
        std::wcerr << L"LoadLibrary failed: " << GetLastError() << L"\n";
        return 4;
    }
    bool valid = true;
    for (const char* name : {"DllGetClassObject", "DllCanUnloadNow", "DllRegisterServer", "DllUnregisterServer"}) {
        if (!GetProcAddress(module, name)) valid = false;
    }
    FreeLibrary(module);
    std::wcout << L"PIME ABI load: native=" << native << L" process=" << process
               << L" exports=" << valid << L" registration=false\n";
    return valid ? 0 : 5;
}
