#include "BrokerClient.h"

#include <algorithm>
#include <chrono>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

namespace yime::experiment {
namespace {

using RequestDeadline = std::chrono::steady_clock::time_point;

std::string windowsError(const char* operation) {
    return std::string(operation) + " failed with Windows error " + std::to_string(GetLastError());
}

DWORD remainingMilliseconds(RequestDeadline deadline) {
    const auto now = std::chrono::steady_clock::now();
    if (now >= deadline) return 0;
    const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - now);
    return static_cast<DWORD>(std::max<int64_t>(1, remaining.count()));
}

bool finishOverlapped(HANDLE pipe, OVERLAPPED* overlapped, BOOL started,
                      const char* operation, RequestDeadline deadline,
                      DWORD* transferred, std::string* error) {
    if (!started) {
        const DWORD code = GetLastError();
        if (code != ERROR_IO_PENDING) {
            if (error) *error = windowsError(operation);
            return false;
        }
        const DWORD waitResult = WaitForSingleObject(overlapped->hEvent, remainingMilliseconds(deadline));
        if (waitResult == WAIT_TIMEOUT) {
            CancelIoEx(pipe, overlapped);
            WaitForSingleObject(overlapped->hEvent, INFINITE);
            DWORD ignored = 0;
            GetOverlappedResult(pipe, overlapped, &ignored, FALSE);
            if (error) *error = std::string("Broker ") + operation + " timeout";
            return false;
        }
        if (waitResult != WAIT_OBJECT_0) {
            const DWORD waitError = GetLastError();
            CancelIoEx(pipe, overlapped);
            WaitForSingleObject(overlapped->hEvent, INFINITE);
            DWORD ignored = 0;
            GetOverlappedResult(pipe, overlapped, &ignored, FALSE);
            if (error) {
                *error = std::string("WaitForSingleObject failed with Windows error ") +
                         std::to_string(waitError);
            }
            return false;
        }
    }
    if (!GetOverlappedResult(pipe, overlapped, transferred, FALSE)) {
        if (error) *error = windowsError(operation);
        return false;
    }
    return true;
}

bool writeWithDeadline(HANDLE pipe, const char* data, DWORD size,
                       RequestDeadline deadline, DWORD* transferred,
                       std::string* error) {
    HANDLE event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!event) {
        if (error) *error = windowsError("CreateEventW");
        return false;
    }
    OVERLAPPED overlapped{};
    overlapped.hEvent = event;
    DWORD immediate = 0;
    const BOOL started = WriteFile(pipe, data, size, &immediate, &overlapped);
    const bool finished = finishOverlapped(pipe, &overlapped, started, "WriteFile",
                                           deadline, transferred, error);
    CloseHandle(event);
    return finished;
}

bool readWithDeadline(HANDLE pipe, char* data, DWORD size,
                      RequestDeadline deadline, DWORD* transferred,
                      std::string* error) {
    HANDLE event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!event) {
        if (error) *error = windowsError("CreateEventW");
        return false;
    }
    OVERLAPPED overlapped{};
    overlapped.hEvent = event;
    DWORD immediate = 0;
    const BOOL started = ReadFile(pipe, data, size, &immediate, &overlapped);
    const bool finished = finishOverlapped(pipe, &overlapped, started, "ReadFile",
                                           deadline, transferred, error);
    CloseHandle(event);
    return finished;
}

}  // namespace

bool IsBrokerPipeTransportAlive(HANDLE pipe) noexcept {
    if (pipe == INVALID_HANDLE_VALUE) return false;
    DWORD available = 0;
    return PeekNamedPipe(pipe, nullptr, 0, nullptr, &available, nullptr) != FALSE;
}

DWORD BrokerPipeClientOpenFlags() noexcept {
    return FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION;
}

BrokerClient::~BrokerClient() { Close(); }

bool BrokerClient::IsConnected() const noexcept {
    return !sessionId_.empty() && IsBrokerPipeTransportAlive(pipe_);
}

bool BrokerClient::Connect(const std::wstring& pipeName, DWORD timeoutMs, const std::string& mode,
                           int candidateLimit, std::string* error) {
    Close();
    ioTimeoutMs_ = std::max<DWORD>(timeoutMs, 1);
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeoutMs);
    for (;;) {
        pipe_ = CreateFileW(pipeName.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                            OPEN_EXISTING, BrokerPipeClientOpenFlags(), nullptr);
        if (pipe_ != INVALID_HANDLE_VALUE) break;
        const DWORD code = GetLastError();
        if (code != ERROR_PIPE_BUSY && code != ERROR_FILE_NOT_FOUND) {
            if (error) *error = windowsError("CreateFileW");
            return false;
        }
        if (std::chrono::steady_clock::now() >= deadline) {
            if (error) *error = "named pipe connect timeout";
            return false;
        }
        WaitNamedPipeW(pipeName.c_str(), 50);
    }
    sequence_ = 1;
    std::string response;
    json request{{"version", 1}, {"sequence", sequence_}, {"operation", "open"}};
    if (!mode.empty()) request["mode"] = mode;
    if (candidateLimit >= 5 && candidateLimit <= 9) request["candidate_limit"] = candidateLimit;
    if (!Exchange(request.dump(), &response, error)) {
        Disconnect();
        return false;
    }
    BrokerUpdate update;
    if (!ParseUpdate(response, sequence_, &update, error)) {
        Disconnect();
        return false;
    }
    try {
        sessionId_ = json::parse(response).at("session_id").get<std::string>();
    } catch (const std::exception& exception) {
        if (error) *error = exception.what();
        Disconnect();
        return false;
    }
    return true;
}

bool BrokerClient::ApplyCode(char code, BrokerUpdate* update, std::string* error) {
    return ApplyEvent(1, std::string(1, code), update, error);
}

bool BrokerClient::Backspace(BrokerUpdate* update, std::string* error) {
    return ApplyEvent(2, {}, update, error);
}

bool BrokerClient::Clear(BrokerUpdate* update, std::string* error) {
	return ApplyEvent(3, {}, update, error);
}

bool BrokerClient::PreviousPage(BrokerUpdate* update, std::string* error) {
    return ApplyEvent(5, {}, update, error);
}

bool BrokerClient::NextPage(BrokerUpdate* update, std::string* error) {
    return ApplyEvent(4, {}, update, error);
}

bool BrokerClient::FocusSegment(const std::string& candidateId, int start, int end,
                                BrokerUpdate* update, std::string* error) {
    return ApplyEvent(6, {}, update, error, candidateId, start, end);
}

bool BrokerClient::ExpandSegment(const std::string& candidateId, int start, int end,
                                 BrokerUpdate* update, std::string* error) {
    return ApplyEvent(7, {}, update, error, candidateId, start, end);
}

bool BrokerClient::ApplyEvent(unsigned operation, const std::string& code,
                              BrokerUpdate* update, std::string* error,
                              const std::string& candidateId, int segmentStart,
                              int segmentEnd) {
    if (!IsConnected()) {
        if (error) *error = "Broker session is not connected";
        return false;
    }
    const uint64_t sequence = ++sequence_;
    json event = {{"operation", operation}};
    if (!code.empty()) event["code"] = code;
    if (!candidateId.empty()) event["candidate_id"] = candidateId;
    if (segmentEnd > segmentStart) {
        event["segment_start"] = segmentStart;
        event["segment_end"] = segmentEnd;
    }
    const json request = {{"version", 1}, {"sequence", sequence}, {"session_id", sessionId_},
                          {"operation", "apply"}, {"event", std::move(event)}};
    std::string response;
    if (!Exchange(request.dump(), &response, error) || !ParseUpdate(response, sequence, update, error)) {
        Disconnect();
        return false;
    }
    return true;
}

bool BrokerClient::SelectCandidate(const std::string& candidateId, const std::string& mutationId,
                                   BrokerUpdate* update, std::string* error) {
    if (!IsConnected()) {
        if (error) *error = "Broker session is not connected";
        return false;
    }
    const uint64_t sequence = ++sequence_;
    const json request = {{"version", 1}, {"sequence", sequence}, {"session_id", sessionId_},
                          {"operation", "select"}, {"candidate_id", candidateId}, {"mutation_id", mutationId}};
    std::string response;
    if (!Exchange(request.dump(), &response, error) || !ParseUpdate(response, sequence, update, error)) {
        Disconnect();
        return false;
    }
    return true;
}

bool BrokerClient::ForgetCandidate(const std::string& candidateId, BrokerUpdate* update,
                                   std::string* error) {
    if (!IsConnected()) {
        if (error) *error = "Broker session is not connected";
        return false;
    }
    const uint64_t sequence = ++sequence_;
    const json request = {{"version", 1}, {"sequence", sequence}, {"session_id", sessionId_},
                          {"operation", "forget"}, {"candidate_id", candidateId}};
    std::string response;
    if (!Exchange(request.dump(), &response, error) || !ParseUpdate(response, sequence, update, error)) {
        Disconnect();
        return false;
    }
    return true;
}

void BrokerClient::Close() noexcept {
    try {
        if (IsConnected()) {
            const uint64_t sequence = ++sequence_;
            const std::string request = json{{"version", 1}, {"sequence", sequence}, {"session_id", sessionId_}, {"operation", "close"}}.dump();
            std::string ignoredResponse;
            std::string ignoredError;
            Exchange(request, &ignoredResponse, &ignoredError);
        }
    } catch (...) {
        // Destruction and COM deactivation must never terminate the host process.
    }
    Disconnect();
}

void BrokerClient::Disconnect() noexcept {
    sessionId_.clear();
    sequence_ = 0;
    if (pipe_ != INVALID_HANDLE_VALUE) {
        CloseHandle(pipe_);
        pipe_ = INVALID_HANDLE_VALUE;
    }
}

bool BrokerClient::Exchange(const std::string& request, std::string* response, std::string* error) {
    const std::string frame = request + "\n";
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(ioTimeoutMs_);
    size_t offset = 0;
    while (offset < frame.size()) {
        DWORD written = 0;
        if (!writeWithDeadline(pipe_, frame.data() + offset,
                               static_cast<DWORD>(frame.size() - offset),
                               deadline, &written, error) || written == 0) {
            return false;
        }
        offset += written;
    }
    response->clear();
    for (;;) {
        char buffer[4096];
        DWORD read = 0;
        if (!readWithDeadline(pipe_, buffer, sizeof(buffer), deadline, &read, error) || read == 0) {
            return false;
        }
        const char* newline = std::find(buffer, buffer + read, '\n');
        response->append(buffer, static_cast<size_t>(newline - buffer));
        if (response->size() > 256 * 1024) {
            if (error) *error = "Broker response exceeds protocol limit";
            return false;
        }
        if (newline != buffer + read) {
            if (newline + 1 != buffer + read) {
                if (error) *error = "multiple unframed Broker responses";
                return false;
            }
            return true;
        }
    }
}

bool BrokerClient::ParseUpdate(const std::string& responseText, uint64_t sequence, BrokerUpdate* update, std::string* error) {
    try {
        const json response = json::parse(responseText);
        if (response.value("version", 0) != 1 || response.value("sequence", uint64_t{0}) != sequence) {
            throw std::runtime_error("Broker response version or sequence mismatch");
        }
        if (response.contains("error")) throw std::runtime_error(response["error"].value("message", "Broker error"));
        *update = {};
        if (response.contains("result")) {
            const auto& result = response["result"];
            update->commit = result.value("commit", "");
            if (result.contains("state")) {
                const auto& state = result["state"];
                update->rawInput = state.value("raw_input", "");
                update->pageNumber = state.value("page_number", 0);
                update->hasPreviousPage = state.value("has_previous", false);
                update->hasNextPage = state.value("has_next", false);
                if (state.contains("active_segment")) {
                    const auto& active = state["active_segment"];
                    update->activeSegmentStart = active.value("start", -1);
                    update->activeSegmentEnd = active.value("end", -1);
                }
                const auto parseCandidate = [](const json& candidate) {
                        BrokerCandidate parsed{
                            candidate.at("id").get<std::string>(),
                            candidate.at("text").get<std::string>(),
                            candidate.value("code", ""),
                        };
                        if (candidate.contains("annotations")) {
                            const auto& annotations = candidate["annotations"];
                            parsed.yinyuan = annotations.value("yinyuan", "");
                            parsed.standardPinyin = annotations.value("standard_pinyin", "");
                        }
                        if (candidate.contains("segments")) {
                            for (const auto& segment : candidate["segments"]) {
                                parsed.segments.push_back(BrokerSegment{
                                    segment.value("start", 0), segment.value("end", 0),
                                    segment.value("text", ""), segment.value("code", "")});
                            }
                        }
                        return parsed;
                };
                if (state.contains("sentence")) {
                    update->sentence = parseCandidate(state["sentence"]);
                    update->hasSentence = !update->sentence.id.empty();
                }
                if (state.contains("candidates")) {
                    for (const auto& candidate : state["candidates"]) {
                        update->candidates.push_back(parseCandidate(candidate));
                    }
                }
            }
        }
        return true;
    } catch (const std::exception& exception) {
        if (error) *error = exception.what();
        return false;
    }
}

}  // namespace yime::experiment
