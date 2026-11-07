#pragma once

// Phase A: offline plan validation only. No Windows/COM activation lives here.
#include <nlohmann/json.hpp>
#include <cstdint>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>

namespace yime::nativehost {
enum class Scenario { DelayWrite, FailWrite };
inline constexpr const char* PackageVersion = "0.1.0-18u-test.13";
inline constexpr const char* SourceCommit = "ff1a3d9269c0061c0582bb2f707cfc2d8a68a6bb";
inline constexpr const char* OuterHash = "b55b004795261acb3a690a2c6ebaea57f81e31d72c061d14dafd5db8a792df1a";
inline constexpr const char* InnerHash = "51d61513811eb1080f2aba30cd01555c52cab5498307cd4d47e720b01cd12a22";
inline constexpr const char* DescriptorHash = "dbc12369d3ca1de81d3dd96a6fd543794951edc3689a098c0c113c17577d217e";
inline constexpr const char* TipHash = "2ce9ae68566a4a4b2d9a830f6c52f4c051e52dba1373c0ea05c48a4a6c9470f4";
inline constexpr const char* FrontendHash = "f13adbaae8475cf0cae8d54b1e94b4e7cabe8caf63274d20785958a5e76ca3a4";
struct Plan {
    std::string runId, caseId, machine, installedRoot, hostHash, text, textHash;
    Scenario scenario = Scenario::DelayWrite;
    unsigned durationMs = 0, delayMs = 0;
};
inline void planRequire(bool value, const char* error) {
    if (!value) throw std::runtime_error(error);
}
inline bool hexHash(const std::string& s) {
    if (s.size() != 64) return false;
    for (char c : s) if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return false;
    return true;
}
inline bool label(const std::string& s, size_t maximum) {
    if (s.empty() || s.size() > maximum) return false;
    for (unsigned char c : s)
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') || c == '-' || c == '_')) return false;
    return true;
}
inline bool localAbsoluteRoot(const std::string& s) {
    if (s.size() < 4 || !((s[0] >= 'A' && s[0] <= 'Z') || (s[0] >= 'a' && s[0] <= 'z')) ||
        s[1] != ':' || (s[2] != '\\' && s[2] != '/')) return false;
    std::string component;
    for (size_t i = 3; i <= s.size(); ++i) {
        const char c = i == s.size() ? '/' : s[i];
        if (c == '/' || c == '\\') {
            if (component.empty() || component == "." || component == ".." ||
                component.back() == ' ' || component.back() == '.') return false;
            component.clear();
        } else {
            if (static_cast<unsigned char>(c) < 32 || c == ':' || c == '*' || c == '?' ||
                c == '"' || c == '<' || c == '>' || c == '|') return false;
            component += c;
        }
    }
    return true;
}
inline bool syntheticText(const std::string& s) {
    size_t count = 0;
    for (size_t i = 0; i < s.size();) {
        const auto lead = static_cast<unsigned char>(s[i++]);
        uint32_t value = 0, minimum = 0; unsigned tails = 0;
        if (lead < 0x80) value = lead;
        else if (lead >= 0xc2 && lead <= 0xdf) { value = lead & 31; tails = 1; minimum = 0x80; }
        else if (lead >= 0xe0 && lead <= 0xef) { value = lead & 15; tails = 2; minimum = 0x800; }
        else if (lead >= 0xf0 && lead <= 0xf4) { value = lead & 7; tails = 3; minimum = 0x10000; }
        else return false;
        while (tails--) {
            if (i == s.size()) return false;
            const auto c = static_cast<unsigned char>(s[i++]);
            if ((c & 0xc0) != 0x80) return false;
            value = (value << 6) | (c & 63);
        }
        if (value < minimum || value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff) ||
            value < 32 || (value >= 0x7f && value <= 0x9f) || ++count > 128) return false;
    }
    return count != 0;
}
// Preserve the supplied UTF-8 identity; never transliterate or substitute an alias.
inline bool machineName(const std::string& s) {
    if (!syntheticText(s)) return false;
    size_t characters = 0;
    for (unsigned char c : s) {
        if ((c & 0xc0) != 0x80) ++characters;
        if (c < 0x80 && !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') || c == '-' || c == '_')) return false;
    }
    return characters <= 63;
}
inline Plan validatePlan(const nlohmann::json& j, const std::string& requestedCase = {}) {
    static const std::set<std::string> keys = {"schemaVersion", "runId", "caseId", "expectedMachine", "architecture",
        "packageVersion", "sourceCommit", "outerZipSha256", "innerZipSha256", "descriptorSha256", "installedRoot",
        "frontendSha256", "tipSha256", "hostSha256", "expectedText", "expectedTextUtf16Sha256",
        "maxDurationMs", "delayMs", "allowManualRecovery"};
    planRequire(j.is_object() && j.size() == keys.size(), "plan field set");
    for (auto it = j.begin(); it != j.end(); ++it)
        planRequire(keys.count(it.key()) && !it.value().is_null(), "plan unknown/null field");
    auto str = [&](const char* name) -> std::string {
        planRequire(j.contains(name) && j.at(name).is_string(), "plan string field");
        return j.at(name).get<std::string>();
    };
    planRequire(str("schemaVersion") == "yime-18u-native-host-plan-v1", "plan schema");
    planRequire(str("architecture") == "native-x64", "plan architecture");
    planRequire(str("packageVersion") == PackageVersion && str("sourceCommit") == SourceCommit, "plan package/source");
    planRequire(str("outerZipSha256") == OuterHash && str("innerZipSha256") == InnerHash &&
        str("descriptorSha256") == DescriptorHash && str("tipSha256") == TipHash && str("frontendSha256") == FrontendHash,
        "plan fixed test13 identity");
    Plan p; p.runId = str("runId"); p.caseId = str("caseId"); p.machine = str("expectedMachine");
    planRequire(label(p.runId, 64), "plan run label");
    planRequire(machineName(p.machine), "plan machine name");
    planRequire(p.caseId == "D1" || p.caseId == "D2", "phase A case only");
    planRequire(requestedCase.empty() || requestedCase == p.caseId, "plan case mismatch");
    p.scenario = p.caseId == "D1" ? Scenario::DelayWrite : Scenario::FailWrite;
    p.installedRoot = str("installedRoot"); p.hostHash = str("hostSha256");
    p.text = str("expectedText"); p.textHash = str("expectedTextUtf16Sha256");
    planRequire(localAbsoluteRoot(p.installedRoot), "plan local absolute installedRoot");
    planRequire(hexHash(p.hostHash) && hexHash(p.textHash) && syntheticText(p.text), "plan host/text identity");
    auto integer = [&](const char* key, uint64_t low, uint64_t high) {
        const auto& v = j.at(key);
        planRequire(v.is_number_integer() && !v.is_boolean(), "plan integer field");
        planRequire(!(v.is_number_integer() && !v.is_number_unsigned() && v.get<int64_t>() < 0), "plan negative integer");
        const auto n = v.get<uint64_t>(); planRequire(n >= low && n <= high, "plan integer range"); return static_cast<unsigned>(n);
    };
    p.durationMs = integer("maxDurationMs", 10000, 120000);
    p.delayMs = p.scenario == Scenario::DelayWrite ? integer("delayMs", 250, 500) : integer("delayMs", 0, 0);
    planRequire(j.at("allowManualRecovery").is_boolean() && !j.at("allowManualRecovery").get<bool>(), "phase A manual recovery is unobserved");
    return p;
}
inline nlohmann::json parsePlanJson(const std::string& raw) {
    planRequire(!raw.empty() && raw.size() <= 32768, "plan byte limit");
    std::vector<std::set<std::string>> objects;
    auto callback = [&](int, nlohmann::json::parse_event_t event, nlohmann::json& value) {
        if (event == nlohmann::json::parse_event_t::object_start) objects.emplace_back();
        else if (event == nlohmann::json::parse_event_t::key)
            planRequire(!objects.empty() && objects.back().insert(value.get<std::string>()).second, "duplicate JSON key");
        else if (event == nlohmann::json::parse_event_t::object_end) objects.pop_back();
        return true;
    };
    return nlohmann::json::parse(raw, callback);
}
inline Plan parsePlan(const std::string& raw, const std::string& requestedCase = {}) {
    return validatePlan(parsePlanJson(raw), requestedCase);
}
} // namespace yime::nativehost
