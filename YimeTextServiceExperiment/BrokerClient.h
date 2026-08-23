#pragma once

#include <windows.h>

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace yime::experiment {

struct BrokerCandidate {
    std::string id;
    std::string text;
    std::string code;
    std::string yinyuan;
    std::string standardPinyin;
};

struct BrokerUpdate {
    std::string rawInput;
    std::vector<BrokerCandidate> candidates;
    std::string commit;
    size_t selectedCandidateIndex = 0;
    int pageNumber = 0;
    bool hasPreviousPage = false;
    bool hasNextPage = false;
};

class BrokerClient {
public:
    BrokerClient() = default;
    ~BrokerClient();
    BrokerClient(const BrokerClient&) = delete;
    BrokerClient& operator=(const BrokerClient&) = delete;

    bool Connect(const std::wstring& pipeName, DWORD timeoutMs, const std::string& mode,
                 std::string* error);
    bool ApplyCode(char code, BrokerUpdate* update, std::string* error);
    bool Backspace(BrokerUpdate* update, std::string* error);
    bool PreviousPage(BrokerUpdate* update, std::string* error);
    bool NextPage(BrokerUpdate* update, std::string* error);
    bool SelectCandidate(const std::string& candidateId, const std::string& mutationId,
                         BrokerUpdate* update, std::string* error);
    void Close() noexcept;
    bool IsConnected() const noexcept { return pipe_ != INVALID_HANDLE_VALUE && !sessionId_.empty(); }

private:
    bool ApplyEvent(unsigned operation, const std::string& code, BrokerUpdate* update, std::string* error);
    bool Exchange(const std::string& request, std::string* response, std::string* error);
    bool ParseUpdate(const std::string& response, uint64_t sequence, BrokerUpdate* update, std::string* error);
    void Disconnect() noexcept;

    HANDLE pipe_ = INVALID_HANDLE_VALUE;
    std::string sessionId_;
    uint64_t sequence_ = 0;
};

}  // namespace yime::experiment
