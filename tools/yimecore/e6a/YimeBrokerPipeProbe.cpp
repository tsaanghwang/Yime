#include <windows.h>

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#include <nlohmann/json.hpp>

using json = nlohmann::json;
using Clock = std::chrono::steady_clock;

namespace {

struct Handle {
    HANDLE value = INVALID_HANDLE_VALUE;
    ~Handle() {
        if (value != INVALID_HANDLE_VALUE) CloseHandle(value);
    }
    Handle() = default;
    Handle(const Handle&) = delete;
    Handle& operator=(const Handle&) = delete;
    Handle(Handle&& other) noexcept : value(other.value) { other.value = INVALID_HANDLE_VALUE; }
    Handle& operator=(Handle&& other) noexcept {
        if (this != &other) {
            if (value != INVALID_HANDLE_VALUE) CloseHandle(value);
            value = other.value;
            other.value = INVALID_HANDLE_VALUE;
        }
        return *this;
    }
};

struct Options {
    std::wstring pipe;
    std::wstring output;
    std::wstring sessionFile;
    std::wstring releaseFile;
    std::string scenario = "replay";
    std::string code = "2jru";
    std::string expectedText;
    int iterations = 1000;
    int connectTimeoutMs = 5000;
    std::string stolenSession;
};

std::string utf8(const std::wstring& value) {
    if (value.empty()) return {};
    const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
                                         static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
    if (size <= 0) throw std::runtime_error("invalid UTF-16 argument");
    std::string result(static_cast<size_t>(size), '\0');
    if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()),
                            result.data(), size, nullptr, nullptr) != size) {
        throw std::runtime_error("could not convert UTF-16 argument");
    }
    return result;
}

int parseInt(const std::wstring& value, const wchar_t* name) {
    size_t used = 0;
    int result = std::stoi(value, &used);
    if (used != value.size() || result < 1) throw std::runtime_error(utf8(name) + " must be positive");
    return result;
}

Options parseOptions(int argc, wchar_t** argv) {
    Options options;
    for (int index = 1; index < argc; ++index) {
        const std::wstring name = argv[index];
        if (index + 1 >= argc) throw std::runtime_error("missing value for " + utf8(name));
        const std::wstring value = argv[++index];
        if (name == L"--pipe") options.pipe = value;
        else if (name == L"--output") options.output = value;
        else if (name == L"--scenario") options.scenario = utf8(value);
        else if (name == L"--code") options.code = utf8(value);
        else if (name == L"--expected-text") options.expectedText = utf8(value);
        else if (name == L"--iterations") options.iterations = parseInt(value, L"iterations");
        else if (name == L"--connect-timeout-ms") options.connectTimeoutMs = parseInt(value, L"connect timeout");
        else if (name == L"--session-file") options.sessionFile = value;
        else if (name == L"--release-file") options.releaseFile = value;
        else if (name == L"--stolen-session") options.stolenSession = utf8(value);
        else throw std::runtime_error("unknown argument " + utf8(name));
    }
    if (options.pipe.empty() || options.output.empty()) throw std::runtime_error("--pipe and --output are required");
    if (options.scenario == "owner" && (options.sessionFile.empty() || options.releaseFile.empty())) {
        throw std::runtime_error("owner requires --session-file and --release-file");
    }
    if (options.scenario == "intruder" && options.stolenSession.empty()) {
        throw std::runtime_error("intruder requires --stolen-session");
    }
    return options;
}

std::string windowsError(const char* operation) {
    return std::string(operation) + " failed with Windows error " + std::to_string(GetLastError());
}

Handle connectPipe(const Options& options) {
    const auto deadline = Clock::now() + std::chrono::milliseconds(options.connectTimeoutMs);
    for (;;) {
        Handle pipe;
        pipe.value = CreateFileW(options.pipe.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                                 OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (pipe.value != INVALID_HANDLE_VALUE) return pipe;
        const DWORD error = GetLastError();
        if (error != ERROR_PIPE_BUSY && error != ERROR_FILE_NOT_FOUND) throw std::runtime_error(windowsError("CreateFileW"));
        if (Clock::now() >= deadline) throw std::runtime_error("named pipe connect timeout");
        WaitNamedPipeW(options.pipe.c_str(), 50);
    }
}

void writeAll(HANDLE pipe, const std::string& value) {
    size_t offset = 0;
    while (offset < value.size()) {
        DWORD written = 0;
        if (!WriteFile(pipe, value.data() + offset, static_cast<DWORD>(value.size() - offset), &written, nullptr)) {
            throw std::runtime_error(windowsError("WriteFile"));
        }
        if (written == 0) throw std::runtime_error("named pipe write made no progress");
        offset += written;
    }
}

std::string readLine(HANDLE pipe) {
    std::string line;
    line.reserve(4096);
    for (;;) {
        char buffer[4096];
        DWORD read = 0;
        if (!ReadFile(pipe, buffer, sizeof(buffer), &read, nullptr)) throw std::runtime_error(windowsError("ReadFile"));
        if (read == 0) throw std::runtime_error("named pipe closed before response");
        const char* newline = std::find(buffer, buffer + read, '\n');
        line.append(buffer, static_cast<size_t>(newline - buffer));
        if (newline != buffer + read) {
            if (newline + 1 != buffer + read) throw std::runtime_error("multiple responses arrived in one unframed read");
            return line;
        }
        if (line.size() > 256 * 1024) throw std::runtime_error("response exceeds protocol limit");
    }
}

json exchange(HANDLE pipe, const json& request, std::vector<int64_t>& latenciesNs) {
    const std::string frame = request.dump() + "\n";
    const auto started = Clock::now();
    writeAll(pipe, frame);
    const std::string response = readLine(pipe);
    const auto elapsed = std::chrono::duration_cast<std::chrono::nanoseconds>(Clock::now() - started).count();
    latenciesNs.push_back(elapsed);
    return json::parse(response);
}

void requireSuccess(const json& response, uint64_t sequence) {
    if (response.value("version", 0) != 1 || response.value("sequence", uint64_t{0}) != sequence) {
        throw std::runtime_error("protocol response version or sequence mismatch: " + response.dump());
    }
    if (response.contains("error")) throw std::runtime_error("broker returned error: " + response.dump());
}

double percentile(const std::vector<int64_t>& sorted, double fraction) {
    if (sorted.empty()) return 0;
    const size_t index = static_cast<size_t>(fraction * static_cast<double>(sorted.size() - 1));
    return static_cast<double>(sorted[index]) / 1'000'000.0;
}

json metrics(const std::vector<int64_t>& values, const Clock::time_point& started) {
    std::vector<int64_t> sorted = values;
    std::sort(sorted.begin(), sorted.end());
    const double seconds = std::chrono::duration<double>(Clock::now() - started).count();
    return {
        {"request_count", values.size()},
        {"elapsed_seconds", seconds},
        {"requests_per_second", seconds > 0 ? static_cast<double>(values.size()) / seconds : 0},
        {"latency_ms", {{"p50", percentile(sorted, 0.50)}, {"p95", percentile(sorted, 0.95)},
                        {"p99", percentile(sorted, 0.99)}, {"max", percentile(sorted, 1.0)}}}
    };
}

json runReplay(HANDLE pipe, const Options& options) {
    std::vector<int64_t> latencies;
    const auto started = Clock::now();
    uint64_t sequence = 1;
    json response = exchange(pipe, {{"version", 1}, {"sequence", sequence}, {"operation", "open"}}, latencies);
    requireSuccess(response, sequence);
    const std::string session = response.at("session_id").get<std::string>();
    const std::string engineVersion = response.value("engine_version", "");

    json spoofed = exchange(pipe, {{"version", 1}, {"sequence", sequence + 1}, {"session_id", session},
                                   {"operation", "reset"}, {"client_id", "spoofed"}}, latencies);
    if (!spoofed.contains("error") || spoofed["error"].value("code", "") != "invalid_request") {
        throw std::runtime_error("request-supplied identity was not rejected: " + spoofed.dump());
    }

    std::string selectedText;
    for (int iteration = 0; iteration < options.iterations; ++iteration) {
        ++sequence;
        response = exchange(pipe, {{"version", 1}, {"sequence", sequence}, {"session_id", session}, {"operation", "reset"}}, latencies);
        requireSuccess(response, sequence);
        for (const char code : options.code) {
            ++sequence;
            response = exchange(pipe, {{"version", 1}, {"sequence", sequence}, {"session_id", session}, {"operation", "apply"},
                                       {"event", {{"operation", 1}, {"code", std::string(1, code)}}}}, latencies);
            requireSuccess(response, sequence);
        }
        const auto& state = response.at("result").at("state");
        if (state.value("raw_input", "") != options.code || !state.contains("candidates") || state["candidates"].empty()) {
            throw std::runtime_error("candidate state mismatch: " + response.dump());
        }
        const std::string candidate = state["candidates"][0].at("id").get<std::string>();
        selectedText = state["candidates"][0].at("text").get<std::string>();
        ++sequence;
        response = exchange(pipe, {{"version", 1}, {"sequence", sequence}, {"session_id", session}, {"operation", "select"},
                                   {"candidate_id", candidate}, {"mutation_id", "e6a-probe-" + std::to_string(GetCurrentProcessId()) + "-" + std::to_string(iteration)}}, latencies);
        requireSuccess(response, sequence);
        if (response.at("result").value("commit", "") != selectedText) throw std::runtime_error("selected candidate commit mismatch");
    }
    ++sequence;
    response = exchange(pipe, {{"version", 1}, {"sequence", sequence}, {"session_id", session}, {"operation", "close"}}, latencies);
    requireSuccess(response, sequence);
    if (!options.expectedText.empty() && selectedText != options.expectedText) {
        throw std::runtime_error("top candidate mismatch: expected " + options.expectedText + ", got " + selectedText);
    }
    return {{"passed", true}, {"scenario", "replay"}, {"pid", GetCurrentProcessId()},
            {"architecture_bits", sizeof(void*) * 8}, {"engine_version", engineVersion},
            {"selected_text", selectedText}, {"identity_spoof_rejected", true},
            {"metrics", metrics(latencies, started)}};
}

void writeTextFile(const std::wstring& path, const std::string& text) {
    std::ofstream stream(std::filesystem::path(path), std::ios::binary | std::ios::trunc);
    if (!stream) throw std::runtime_error("could not create coordination file");
    stream << text;
    if (!stream) throw std::runtime_error("could not write coordination file");
}

json runOwner(HANDLE pipe, const Options& options) {
    std::vector<int64_t> latencies;
    const auto started = Clock::now();
    json response = exchange(pipe, {{"version", 1}, {"sequence", 1}, {"operation", "open"}}, latencies);
    requireSuccess(response, 1);
    const std::string session = response.at("session_id").get<std::string>();
    writeTextFile(options.sessionFile, session);
    const auto deadline = Clock::now() + std::chrono::seconds(10);
    while (!std::filesystem::exists(options.releaseFile)) {
        if (Clock::now() >= deadline) throw std::runtime_error("owner release timeout");
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    response = exchange(pipe, {{"version", 1}, {"sequence", 2}, {"session_id", session}, {"operation", "close"}}, latencies);
    requireSuccess(response, 2);
    return {{"passed", true}, {"scenario", "owner"}, {"pid", GetCurrentProcessId()},
            {"architecture_bits", sizeof(void*) * 8}, {"session_id", session},
            {"metrics", metrics(latencies, started)}};
}

json runIntruder(HANDLE pipe, const Options& options) {
    std::vector<int64_t> latencies;
    const auto started = Clock::now();
    const json response = exchange(pipe, {{"version", 1}, {"sequence", 2}, {"session_id", options.stolenSession}, {"operation", "reset"}}, latencies);
    const bool rejected = response.contains("error") && response["error"].value("code", "") == "session_not_found";
    if (!rejected) throw std::runtime_error("cross-process session access was not rejected: " + response.dump());
    return {{"passed", true}, {"scenario", "intruder"}, {"pid", GetCurrentProcessId()},
            {"architecture_bits", sizeof(void*) * 8}, {"cross_process_session_rejected", true},
            {"metrics", metrics(latencies, started)}};
}

void writeOutput(const std::wstring& path, const json& value) {
    std::ofstream stream(std::filesystem::path(path), std::ios::binary | std::ios::trunc);
    if (!stream) throw std::runtime_error("could not create output file");
    stream << value.dump(2) << '\n';
    if (!stream) throw std::runtime_error("could not write output file");
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    std::wstring output;
    try {
        const Options options = parseOptions(argc, argv);
        output = options.output;
        Handle pipe = connectPipe(options);
        json result;
        if (options.scenario == "replay") result = runReplay(pipe.value, options);
        else if (options.scenario == "owner") result = runOwner(pipe.value, options);
        else if (options.scenario == "intruder") result = runIntruder(pipe.value, options);
        else throw std::runtime_error("unknown scenario " + options.scenario);
        writeOutput(options.output, result);
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << std::endl;
        if (!output.empty()) {
            try { writeOutput(output, {{"passed", false}, {"error", error.what()}, {"pid", GetCurrentProcessId()},
                                       {"architecture_bits", sizeof(void*) * 8}}); } catch (...) {}
        }
        return 1;
    }
}
