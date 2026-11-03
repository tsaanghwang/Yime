#define WIDEN_IMPL(value) L##value
#define WIDEN(value) WIDEN_IMPL(value)
#define STRINGIFY_IMPL(value) #value
#define STRINGIFY(value) STRINGIFY_IMPL(value)

#include <windows.h>

extern "C" __declspec(dllexport) const wchar_t* SyntheticMarker() {
    return WIDEN(STRINGIFY(SYNTHETIC_MARKER));
}

BOOL WINAPI DllMain(HINSTANCE, DWORD, LPVOID) {
    return TRUE;
}
