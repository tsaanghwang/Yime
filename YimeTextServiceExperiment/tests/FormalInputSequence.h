#pragma once
#include <nlohmann/json.hpp>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <string>

// The lab protocol accepts one physical key per input event, not a syllable.
// Each acknowledged revision belongs to the next key; failures stop the
// sequence immediately. This helper never selects, retries, or completes edits.
template<class Send>
nlohmann::json FormalInputSequence(const std::string& code, nlohmann::json state, Send send) {
    using json = nlohmann::json;
    if (code.empty() || code.size() > 16) throw std::runtime_error("canonical input bound");
    for (unsigned char key : code)
        if (key < 0x21 || key > 0x7e) throw std::runtime_error("canonical input alphabet");
    for (char key : code) {
        const auto& value = state.at("snapshot").at("revision");
        if (!value.is_number_unsigned()) throw std::runtime_error("input revision type");
        const auto revision = value.get<uint64_t>();
        if (revision == std::numeric_limits<uint64_t>::max()) throw std::runtime_error("input revision bound");
        json next = send(json{{"kind", "input"}, {"code", std::string(1, key)}, {"revision", revision}});
        if (!next.value("ok", false) || next.contains("commit"))
            throw std::runtime_error("input did not remain uncommitted");
        const auto& nextRevision = next.at("snapshot").at("revision");
        if (!nextRevision.is_number_unsigned() || nextRevision.get<uint64_t>() != revision + 1)
            throw std::runtime_error("input revision did not advance once");
        state = std::move(next);
    }
    return state;
}
