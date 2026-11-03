#pragma once
#include <msctf.h>
#include <memory>

// Owned and polled exclusively on the activated TIP thread. No COM object is
// used by an IPC worker, and no incoming window message carries a command.
class TouchFrontendEndpoint final {
public:
    TouchFrontendEndpoint(ITfThreadMgr* manager, TfClientId client);
    ~TouchFrontendEndpoint();
    void Invalidate() noexcept;
private:
    struct Impl;
    std::shared_ptr<Impl> impl_;
};
