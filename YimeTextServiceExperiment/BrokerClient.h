#pragma once

#include <windows.h>

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace yime::experiment {

struct BrokerSegment {
    int start = 0;
    int end = 0;
    std::string text;
    std::string code;
};

struct BrokerCandidate {
    std::string id;
    std::string text;
    std::string code;
    std::string yinyuan;
    std::string standardPinyin;
    std::vector<BrokerSegment> segments;
};

struct BrokerUpdate {
    std::string rawInput;
    std::vector<BrokerCandidate> candidates;
    std::string commit;
    size_t selectedCandidateIndex = 0;
    int pageNumber = 0;
    bool hasPreviousPage = false;
    bool hasNextPage = false;
    bool hasSentence = false;
    BrokerCandidate sentence;
    int activeSegmentStart = -1;
    int activeSegmentEnd = -1;
};

bool IsBrokerPipeTransportAlive(HANDLE pipe) noexcept;
DWORD BrokerPipeClientOpenFlags() noexcept;
DWORD BrokerConnectRetryDelay(DWORD errorCode, DWORD remainingMs) noexcept;

class BrokerClient {
public:
    BrokerClient() = default;
    ~BrokerClient();
    BrokerClient(const BrokerClient&) = delete;
    BrokerClient& operator=(const BrokerClient&) = delete;

    bool Connect(const std::wstring& pipeName, DWORD timeoutMs, const std::string& mode,
                 int candidateLimit,
                 std::string* error);
    bool ApplyCode(char code, BrokerUpdate* update, std::string* error);
    bool Backspace(BrokerUpdate* update, std::string* error);
	bool Clear(BrokerUpdate* update, std::string* error);
    bool PreviousPage(BrokerUpdate* update, std::string* error);
    bool NextPage(BrokerUpdate* update, std::string* error);
    bool FocusSegment(const std::string& candidateId, int start, int end,
                      BrokerUpdate* update, std::string* error);
    bool ExpandSegment(const std::string& candidateId, int start, int end,
                       BrokerUpdate* update, std::string* error);
    bool SelectCandidate(const std::string& candidateId, const std::string& mutationId,
                         BrokerUpdate* update, std::string* error);
    bool ForgetCandidate(const std::string& candidateId, BrokerUpdate* update,
                         std::string* error);
    void Close() noexcept;
    bool IsConnected() const noexcept;

private:
    bool ApplyEvent(unsigned operation, const std::string& code, BrokerUpdate* update,
                    std::string* error, const std::string& candidateId = {},
                    int segmentStart = 0, int segmentEnd = 0);
    bool Exchange(const std::string& request, std::string* response, std::string* error);
    bool ParseUpdate(const std::string& response, uint64_t sequence, BrokerUpdate* update, std::string* error);
    void Disconnect() noexcept;

    HANDLE pipe_ = INVALID_HANDLE_VALUE;
    std::string sessionId_;
    uint64_t sequence_ = 0;
    DWORD ioTimeoutMs_ = 2000;
};

}  // namespace yime::experiment
