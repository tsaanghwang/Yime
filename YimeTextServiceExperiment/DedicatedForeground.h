#pragma once
#include <windows.h>

// The foreground top-level window anchors the target, but its focused child
// may belong to a different UI thread. Only that child's thread owns the TSF
// context. Keep both identities so changing controls cannot reuse a lease.
struct DedicatedForeground {
    HWND window = nullptr;
    DWORD thread = 0, process = 0;
    HWND focus = nullptr, root = nullptr;
    DWORD windowProcess = 0;
};
using DedicatedForegroundQuery = DedicatedForeground(*)() noexcept;

// Internal Win32 query seam for isolated tests; never exposed over IPC/COM.
struct DedicatedForegroundAPI {
    decltype(&GetForegroundWindow) foreground = GetForegroundWindow;
    decltype(&GetGUIThreadInfo) gui = GetGUIThreadInfo;
    decltype(&GetWindowThreadProcessId) owner = GetWindowThreadProcessId;
    decltype(&GetAncestor) ancestor = GetAncestor;
};

inline DedicatedForeground QueryDedicatedForeground(const DedicatedForegroundAPI& api) noexcept {
    DedicatedForeground result;
    result.window = api.foreground();
    GUITHREADINFO gui{sizeof(gui)};
    if (!result.window || !api.gui(0, &gui) || !gui.hwndFocus) return {};
    result.focus = gui.hwndFocus;
    result.thread = api.owner(result.focus, &result.process);
    result.root = api.ancestor(result.focus, GA_ROOT);
    if (!api.owner(result.window, &result.windowProcess) ||
        api.foreground() != result.window) return {};
    return result;
}
inline DedicatedForeground QueryDedicatedForeground() noexcept {
    return QueryDedicatedForeground(DedicatedForegroundAPI{});
}
inline bool OwnsDedicatedForeground(const DedicatedForeground& value, DWORD process, DWORD thread) noexcept {
    return process && thread && value.window && value.focus && value.root == value.window &&
        value.thread == thread && value.process == process && value.windowProcess == process;
}
