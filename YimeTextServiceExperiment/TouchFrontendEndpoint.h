#pragma once
#include <msctf.h>
#include <memory>

// Owned and polled exclusively on the activated TIP thread. No COM object is
// used by an IPC worker, and no incoming window message carries a command.
class TouchFrontendEndpoint final {
public:
    TouchFrontendEndpoint(ITfThreadMgr* manager, TfClientId client,
        REFCLSID clsid, REFGUID profile, bool keyFocused);
    ~TouchFrontendEndpoint();
    void Invalidate() noexcept;
    void SetKeyFocus(bool focused) noexcept;
    void SetThreadFocus(bool focused) noexcept;
#ifdef YIME_TOUCH_FRONTEND_MEMORY_TEST
public: // The memory-only test translation unit exercises the real dispatcher.
#else
private:
#endif
    struct Impl;
    std::shared_ptr<Impl> impl_;
};
