#include "FormalInputSequence.h"
#include <iostream>
#include <vector>
using json = nlohmann::json;
void check(bool value) { if (!value) throw std::runtime_error("input sequence regression"); }
json snapshot(uint64_t revision) { return {{"ok",true},{"snapshot",{{"revision",revision}}}}; }
int main() { try {
    std::vector<json> requests;
    auto result = FormalInputSequence("ab/", snapshot(7), [&](const json& q) {
        requests.push_back(q);
        check(q.at("kind") == "input" && q.at("code").get<std::string>().size() == 1);
        check(q.at("revision").get<uint64_t>() == 6 + requests.size());
        return snapshot(q.at("revision").get<uint64_t>() + 1);
    });
    check(requests.size() == 3 && requests[0]["code"] == "a" && requests[1]["code"] == "b" && requests[2]["code"] == "/");
    check(result["snapshot"]["revision"] == 10);
    for (int fault = 0; fault < 5; ++fault) {
        unsigned count = 0; bool rejected = false;
        try { FormalInputSequence("abc", snapshot(0), [&](const json& q) {
            ++count; auto next = snapshot(q.at("revision").get<uint64_t>() + 1);
            if (count == 2) {
                if (fault == 0) throw std::runtime_error("original HRESULT failure");
                if (fault == 1) next["ok"] = false;
                if (fault == 2) next["snapshot"]["revision"] = uint64_t{0};
                if (fault == 3) next["commit"] = json::object();
                if (fault == 4) next["snapshot"].erase("revision");
            }
            return next;
        }); } catch (...) { rejected = true; }
        check(rejected && count == 2); // No third key, retry or selection.
    }
    for (const auto& code : {std::string(), std::string(17,'a'), std::string("a\nb")}) {
        unsigned count=0; bool rejected=false;
        try { FormalInputSequence(code,snapshot(0),[&](const json&) {++count;return snapshot(1);}); }
        catch (...) {rejected=true;}
        check(rejected && count==0);
    }
    std::cout << "PASS formal input: one key per event, acknowledged revisions, first failure stops without replay\n";
    return 0;
} catch (const std::exception& e) { std::cerr << e.what() << '\n'; return 1; } }
