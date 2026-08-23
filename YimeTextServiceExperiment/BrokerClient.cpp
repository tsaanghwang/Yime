#include "BrokerClient.h"

#include <algorithm>
#include <chrono>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

namespace yime::experiment {
namespace {

std::string windowsError(const char* operation) {
    return std::string(operation) + " failed with Windows error " + std::to_string(GetLastError());
}

}  // namespace

BrokerClient::~BrokerClient() { Close(); }

bool BrokerClient::Connect(const std::wstring& pipeName, DWORD timeoutMs, const std::string& mode,
                           std::string* error) {
    Close();
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeoutMs);
    for (;;) {
        pipe_ = CreateFileW(pipeName.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
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

bool BrokerClient::PreviousPage(BrokerUpdate* update, std::string* error) {
    return ApplyEvent(5, {}, update, error);
}

bool BrokerClient::NextPage(BrokerUpdate* update, std::string* error) {
    return ApplyEvent(4, {}, update, error);
}

bool BrokerClient::ApplyEvent(unsigned operation, const std::string& code,
                              BrokerUpdate* update, std::string* error) {
    if (!IsConnected()) {
        if (error) *error = "Broker session is not connected";
        return false;
    }
    const uint64_t sequence = ++sequence_;
    json event = {{"operation", operation}};
    if (!code.empty()) event["code"] = code;
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
    size_t offset = 0;
    while (offset < frame.size()) {
        DWORD written = 0;
        if (!WriteFile(pipe_, frame.data() + offset, static_cast<DWORD>(frame.size() - offset), &written, nullptr) || written == 0) {
            if (error) *error = windowsError("WriteFile");
            return false;
        }
        offset += written;
    }
    response->clear();
    for (;;) {
        char buffer[4096];
        DWORD read = 0;
        if (!ReadFile(pipe_, buffer, sizeof(buffer), &read, nullptr) || read == 0) {
            if (error) *error = windowsError("ReadFile");
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
                if (state.contains("candidates")) {
                    for (const auto& candidate : state["candidates"]) {
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
                        update->candidates.push_back(std::move(parsed));
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
