#pragma once

// Optional, bounded diagnostic observations only. No document text, request
// strings, paths, protocol changes, file writes, or extra TSF calls belong here.
#include <windows.h>

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <memory>
#include <utility>

namespace yime::touchdiag {

inline constexpr wchar_t kEnvironment[] = L"YIME_TOUCH_FRONTEND_EDIT_DIAGNOSTICS";
inline constexpr std::uint64_t kMaxBytes = 1024ULL * 1024ULL;
inline constexpr std::size_t kMaxRecordBytes = 1536;

enum class Stage {
    Begin, Eligibility, ThreadFocus, ActiveProfile, Foreground, Document, Context,
    Status, Lease, RequestEditSession, Callback, GetSelection, IsEmpty, Clone,
    ProbeShift, ProbeText, StepShift, Collapse, ExtendRange, SetText, SetSelection,
    Complete, Reply, Timeout, Disconnect
};

enum class Action {
    None, Insert, Backspace, Delete, ArrowLeft, ArrowRight, Home, End, SelectAll,
    Enter, Tab
};

inline const char* Name(Stage stage) noexcept {
    switch (stage) {
    case Stage::Begin: return "Begin";
    case Stage::Eligibility: return "Eligibility";
    case Stage::ThreadFocus: return "ThreadFocus";
    case Stage::ActiveProfile: return "ActiveProfile";
    case Stage::Foreground: return "Foreground";
    case Stage::Document: return "Document";
    case Stage::Context: return "Context";
    case Stage::Status: return "Status";
    case Stage::Lease: return "Lease";
    case Stage::RequestEditSession: return "RequestEditSession";
    case Stage::Callback: return "Callback";
    case Stage::GetSelection: return "GetSelection";
    case Stage::IsEmpty: return "IsEmpty";
    case Stage::Clone: return "Clone";
    case Stage::ProbeShift: return "ProbeShift";
    case Stage::ProbeText: return "ProbeText";
    case Stage::StepShift: return "StepShift";
    case Stage::Collapse: return "Collapse";
    case Stage::ExtendRange: return "ExtendRange";
    case Stage::SetText: return "SetText";
    case Stage::SetSelection: return "SetSelection";
    case Stage::Complete: return "Complete";
    case Stage::Reply: return "Reply";
    case Stage::Timeout: return "Timeout";
    case Stage::Disconnect: return "Disconnect";
    }
    return "Unknown";
}

inline const char* Name(Action action) noexcept {
    switch (action) {
    case Action::None: return "None";
    case Action::Insert: return "Insert";
    case Action::Backspace: return "Backspace";
    case Action::Delete: return "Delete";
    case Action::ArrowLeft: return "ArrowLeft";
    case Action::ArrowRight: return "ArrowRight";
    case Action::Home: return "Home";
    case Action::End: return "End";
    case Action::SelectAll: return "SelectAll";
    case Action::Enter: return "Enter";
    case Action::Tab: return "Tab";
    }
    return "Unknown";
}

struct Record {
    Stage stage;
    HRESULT hr = S_OK;
    bool hrKnown = false;
    std::int64_t requested = 0, actual = 0, count = 0;
    std::uint64_t flags = 0;
    int value = -1, value2 = -1;
};

// Shared by all request recorders for one endpoint. Reservation happens before
// calling the sink, so throwing or discarded writes cannot defeat the bound.
struct Budget {
    std::atomic<std::uint64_t> usedBytes{0};

    bool reserve(std::size_t bytes) noexcept {
        auto current = usedBytes.load(std::memory_order_relaxed);
        for (;;) {
            if (current > kMaxBytes || bytes > kMaxBytes - current) return false;
            if (usedBytes.compare_exchange_weak(current, current + bytes,
                    std::memory_order_relaxed, std::memory_order_relaxed)) return true;
        }
    }
};

using Sink = void (*)(const char*, std::size_t);

struct LastErrorScope {
    DWORD value = GetLastError();
    ~LastErrorScope() noexcept { SetLastError(value); }
};

inline void DebugOutput(const char* bytes, std::size_t size) noexcept {
    if (!bytes || !size || size >= kMaxRecordBytes) return;
    const LastErrorScope preserveError;
    char line[kMaxRecordBytes];
    std::memcpy(line, bytes, size);
    line[size] = '\0';
    // The debugger channel is independent of the host's stdout and frontend v2.
    // There is one bounded output call and no fallback, flush, file, or replay.
    OutputDebugStringA(line);
}

inline bool EnabledFromEnvironment() noexcept {
    const LastErrorScope preserveError;
    wchar_t value[2]{};
    const DWORD length = GetEnvironmentVariableW(kEnvironment, value, 2);
    return length == 1 && value[0] == L'1';
}

class Recorder {
public:
    using Sink = yime::touchdiag::Sink;

    explicit Recorder(std::shared_ptr<Budget> budget = {},
                      std::uint64_t instance = 0) noexcept
        : instanceId(instance), budget_(std::move(budget)) {}

    bool enabled = false;
    Sink sink = DebugOutput;
    std::uint64_t instanceId = 0, sequence = 0, generation = 0;
    Action action = Action::None;
    bool extend = false;

    static bool EnabledFromEnvironment() noexcept {
        return yime::touchdiag::EnabledFromEnvironment();
    }

    void emit(Record record) noexcept {
        if (!enabled || !sink) return;
        const LastErrorScope preserveError;
        char line[kMaxRecordBytes];
        const int size = std::snprintf(line, sizeof(line),
            "{\"schema\":\"18u-touch-frontend-edit-diagnostic-v1\","
            "\"tickMs\":%llu,\"process\":%lu,\"thread\":%lu,"
            "\"instanceId\":%llu,\"sequence\":%llu,\"generation\":%llu,"
            "\"action\":\"%s\",\"extend\":%s,\"stage\":\"%s\","
            "\"hr\":%u,\"hrKnown\":%s,\"requested\":%lld,\"actual\":%lld,"
            "\"count\":%lld,\"flags\":%llu,\"value\":%d,\"value2\":%d}\n",
            static_cast<unsigned long long>(GetTickCount64()),
            static_cast<unsigned long>(GetCurrentProcessId()),
            static_cast<unsigned long>(GetCurrentThreadId()),
            static_cast<unsigned long long>(instanceId),
            static_cast<unsigned long long>(sequence),
            static_cast<unsigned long long>(generation), Name(action),
            extend ? "true" : "false", Name(record.stage),
            static_cast<unsigned>(static_cast<std::uint32_t>(record.hr)),
            record.hrKnown ? "true" : "false",
            static_cast<long long>(record.requested),
            static_cast<long long>(record.actual),
            static_cast<long long>(record.count),
            static_cast<unsigned long long>(record.flags), record.value, record.value2);
        if (size <= 0 || static_cast<std::size_t>(size) >= sizeof(line)) return;
        const auto bytes = static_cast<std::size_t>(size);
        if (budget_) {
            if (!budget_->reserve(bytes)) return;
        } else {
            if (localBytes_ > kMaxBytes || bytes > kMaxBytes - localBytes_) return;
            localBytes_ += bytes;
        }
        try { sink(line, bytes); } catch (...) {}
    }

private:
    std::shared_ptr<Budget> budget_;
    std::uint64_t localBytes_ = 0;
};

}  // namespace yime::touchdiag
