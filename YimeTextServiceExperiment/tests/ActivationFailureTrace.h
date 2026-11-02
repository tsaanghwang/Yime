#pragma once
#include <nlohmann/json.hpp>
#include <ostream>

namespace yime::stage1 {
enum class FailurePhase { Operation, Cleanup };

// Call before cleanup can overwrite the terminal report. Both phase records
// use source-defined stage labels and numeric codes only, never paths, tokens,
// host text, the encrypted journal, or the rest of the report.
inline void WriteFailureTrace(const nlohmann::json& report,FailurePhase phase,std::ostream& output) noexcept {
    try {
        if(report.at("stage")=="completed")return;
        output<<nlohmann::json{{"schema","18u-activation-failure-v1"},
            {"phase",phase==FailurePhase::Operation?"operation":"cleanup"},
            {"stage",report.at("stage")},{"code",report.at("code")}}.dump()<<std::endl;
    } catch(...) {
        // Logging/allocation failure must never prevent the cleanup path.
    }
}
}
