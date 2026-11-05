#pragma once
#include <cstdint>
#include <string_view>
#include <utility>
#include <nlohmann/json.hpp>

namespace yime::installeddiag {
// Pure response decoration: it neither queries TSF nor changes retry/session
// state. Only code-owned labels and the actual HRESULT enter the diagnostic.
inline nlohmann::json CompletionResult(std::string_view raw, uint32_t hresult) {
    using json = nlohmann::json;
    auto result = json::parse(raw, nullptr, false);
    const bool valid = result.is_object() && result.contains("ok") && result["ok"].is_boolean();
    const bool failed = (hresult & 0x80000000u) != 0;
    if (!valid) {
        result = {{"ok", false}, {"error", "TIP operation failed or completion unknown"}, {"retryAllowed", false}};
    }
    if (failed) result["ok"] = false;
    // Never trust or retain a diagnostic supplied inside the response body.
    result.erase("diagnostic");
    if (!result["ok"].get<bool>()) {
        json diagnostic = {{"stage", "tip-completion"},
            {"reason", !valid ? "invalid-response" : failed ? "operation-failed" : "completion-rejected"}};
        // S_OK/S_FALSE are not evidence of a failed edit's HRESULT. In
        // particular an ok:false response must not manufacture a failure code.
        if (failed) diagnostic["hresult"] = hresult;
        result["diagnostic"] = std::move(diagnostic);
    }
    return result;
}
}
