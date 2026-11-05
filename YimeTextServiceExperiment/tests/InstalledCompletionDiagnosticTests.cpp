#include "../InstalledCompletionDiagnostic.h"
#include <iostream>
#include <stdexcept>
#include <string>

using nlohmann::json;
using yime::installeddiag::CompletionResult;
void require(bool ok, const char* message) { if (!ok) throw std::runtime_error(message); }

int main() {
    const auto success = json{{"ok", true}, {"snapshot", {{"sessionId", "test"}, {"revision", 2}}}};
    require(CompletionResult(success.dump(), 0) == success, "success response changed");
    require(CompletionResult(success.dump(), 1) == success, "S_FALSE response changed");

    auto result = CompletionResult(success.dump(), 0x80004005u);
    require(!result["ok"].get<bool>(), "failed HRESULT must remain failure");
    require(result["snapshot"] == success["snapshot"], "normal response fields changed");
    require(result["diagnostic"] == json{{"stage", "tip-completion"}, {"reason", "operation-failed"}, {"hresult", 2147500037u}}, "HRESULT bits lost");
    result = CompletionResult("{\"ok\":false}", 0xffffffffu);
    require(result["diagnostic"]["hresult"].get<uint32_t>() == 0xffffffffu, "unsigned HRESULT truncated");

    for (uint32_t code : {0u, 1u}) {
        result = CompletionResult("{\"ok\":false,\"retryAllowed\":false}", code);
        require(result["diagnostic"] == json{{"stage", "tip-completion"}, {"reason", "completion-rejected"}}, "fabricated HRESULT on protocol rejection");
        require(result["retryAllowed"] == false, "retry policy changed");
    }
    for (const std::string raw : {"SECRET body candidates code", "null", "[]", "42", "{}", "{\"ok\":\"SECRET\"}"}) {
        result = CompletionResult(raw, 0);
        require(result == json{{"ok", false}, {"error", "TIP operation failed or completion unknown"}, {"retryAllowed", false},
            {"diagnostic", {{"stage", "tip-completion"}, {"reason", "invalid-response"}}}}, "malformed response leaked or accepted");
    }
    result = CompletionResult("SECRET", 0x80070005u);
    require(result["diagnostic"]["hresult"].get<uint32_t>() == 0x80070005u, "malformed response lost HRESULT");
    require(result["diagnostic"]["reason"] == "invalid-response", "malformed response stage lost");

    const std::string secret = "SECRET正文组码候选 C:/private/file\n{injected}";
    json hostile = {{"ok", false}, {"error", secret}, {"diagnostic", {{"stage", secret}, {"reason", secret}, {"hresult", secret}}}};
    result = CompletionResult(hostile.dump(), 0x80004004u);
    require(result["diagnostic"] == json{{"stage", "tip-completion"}, {"reason", "operation-failed"}, {"hresult", 0x80004004u}}, "untrusted diagnostic retained");
    require(result["diagnostic"].dump().find("SECRET") == std::string::npos, "private diagnostic text escaped");
    hostile["ok"] = true;
    result = CompletionResult(hostile.dump(), 0);
    require(!result.contains("diagnostic"), "success retained a stale diagnostic");
    std::cout << "installed completion diagnostics: success, rejection, malformed response, HRESULT and privacy passed\n";
}
