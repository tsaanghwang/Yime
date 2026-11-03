#define NOMINMAX
#include <windows.h>
#include <winternl.h>
#include <bcrypt.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
#include <array>
#include <algorithm>

namespace fs = std::filesystem;
namespace {
constexpr DWORD kWaitMs = 30000;

struct Handle {
    HANDLE value = INVALID_HANDLE_VALUE;
    explicit Handle(HANDLE v = INVALID_HANDLE_VALUE) : value(v) {}
    ~Handle() { if (value != INVALID_HANDLE_VALUE && value != nullptr) CloseHandle(value); }
    Handle(const Handle&) = delete;
    Handle& operator=(const Handle&) = delete;
    Handle(Handle&& other) noexcept : value(other.value) { other.value = INVALID_HANDLE_VALUE; }
    Handle& operator=(Handle&& other) noexcept {
        if (this != &other) {
            if (valid()) CloseHandle(value);
            value = other.value;
            other.value = INVALID_HANDLE_VALUE;
        }
        return *this;
    }
    bool valid() const { return value != INVALID_HANDLE_VALUE && value != nullptr; }
};

[[noreturn]] void fail(const std::string& what, DWORD error = GetLastError()) {
    throw std::runtime_error(what + " (Win32=" + std::to_string(error) + ")");
}

std::string utf8(const std::wstring& value) {
    if (value.empty()) return {};
    int n = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.c_str(),
                               static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
    if (!n) fail("WideCharToMultiByte");
    std::string result(static_cast<size_t>(n), '\0');
    if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.c_str(),
                            static_cast<int>(value.size()), result.data(), n, nullptr, nullptr)) fail("WideCharToMultiByte");
    return result;
}

std::string quoteJson(const std::string& value) {
    std::string out = "\"";
    for (unsigned char c : value) {
        if (c == '"' || c == '\\') { out += '\\'; out += static_cast<char>(c); }
        else if (c == '\n') out += "\\n";
        else if (c == '\r') out += "\\r";
        else if (c == '\t') out += "\\t";
        else if (c < 32) {
            const char* digits = "0123456789abcdef";
            out += "\\u00"; out += digits[c >> 4]; out += digits[c & 15];
        } else out += static_cast<char>(c);
    }
    return out + '"';
}

std::string hex(const unsigned char* data, size_t size) {
    const char* digits = "0123456789abcdef";
    std::string out;
    out.reserve(size * 2);
    for (size_t i = 0; i < size; ++i) { out += digits[data[i] >> 4]; out += digits[data[i] & 15]; }
    return out;
}

std::string sha256(HANDLE file) {
    if (SetFilePointer(file, 0, nullptr, FILE_BEGIN) == INVALID_SET_FILE_POINTER && GetLastError() != NO_ERROR) fail("seek");
    BCRYPT_ALG_HANDLE alg = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    if (BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0) fail("BCryptOpenAlgorithmProvider", 0);
    DWORD objectSize = 0, length = 0;
    if (BCryptGetProperty(alg, BCRYPT_OBJECT_LENGTH, reinterpret_cast<PUCHAR>(&objectSize), sizeof(objectSize), &length, 0) < 0) fail("BCryptGetProperty", 0);
    std::vector<unsigned char> object(objectSize);
    if (BCryptCreateHash(alg, &hash, object.data(), objectSize, nullptr, 0, 0) < 0) fail("BCryptCreateHash", 0);
    std::array<unsigned char, 65536> buffer{};
    DWORD read = 0;
    BOOL readOk = FALSE;
    while ((readOk = ReadFile(file, buffer.data(), static_cast<DWORD>(buffer.size()), &read, nullptr)) && read) {
        if (BCryptHashData(hash, buffer.data(), read, 0) < 0) fail("BCryptHashData", 0);
    }
    if (!readOk) fail("ReadFile");
    std::array<unsigned char, 32> digest{};
    if (BCryptFinishHash(hash, digest.data(), static_cast<ULONG>(digest.size()), 0) < 0) fail("BCryptFinishHash", 0);
    BCryptDestroyHash(hash);
    BCryptCloseAlgorithmProvider(alg, 0);
    return hex(digest.data(), digest.size());
}

struct Identity {
    std::string volume;
    std::string fileId;
    std::string finalPath;
    std::string hash;
};

Handle openRead(const fs::path& path, bool directory = false) {
    DWORD flags = FILE_FLAG_OPEN_REPARSE_POINT | (directory ? FILE_FLAG_BACKUP_SEMANTICS : 0);
    Handle h(CreateFileW(path.c_str(), GENERIC_READ | (directory ? FILE_TRAVERSE : 0),
                         FILE_SHARE_READ, nullptr, OPEN_EXISTING, flags, nullptr));
    if (!h.valid()) fail("CreateFileW " + utf8(path.wstring()));
    FILE_ATTRIBUTE_TAG_INFO tag{};
    if (!GetFileInformationByHandleEx(h.value, FileAttributeTagInfo, &tag, sizeof(tag))) fail("FileAttributeTagInfo");
    if (tag.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) fail("reparse point rejected", ERROR_REPARSE_TAG_INVALID);
    return h;
}

// NtCreateFile atomically returns the newly created directory object. Win32
// CreateDirectoryW followed by CreateFileW leaves a replacement window.
Handle createHeldDirectory(const fs::path& output) {
    Handle validatedParent = openRead(output.parent_path(), true);
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    if (!ntdll) fail("GetModuleHandleW ntdll");
    auto ntCreateFile = reinterpret_cast<decltype(&NtCreateFile)>(GetProcAddress(ntdll, "NtCreateFile"));
    if (!ntCreateFile) fail("GetProcAddress NtCreateFile");
    // RootDirectory is documented as a directory handle from an earlier
    // NtCreateFile call. Reopen and compare identity while both handles live.
    const std::wstring parentPath = L"\\??\\" + output.parent_path().wstring();
    if (parentPath.size() * sizeof(wchar_t) > USHRT_MAX) fail("parent path too long", 0);
    UNICODE_STRING parentName{};
    parentName.Length = static_cast<USHORT>(parentPath.size() * sizeof(wchar_t));
    parentName.MaximumLength = parentName.Length;
    parentName.Buffer = const_cast<PWSTR>(parentPath.c_str());
    OBJECT_ATTRIBUTES parentAttributes{};
    InitializeObjectAttributes(&parentAttributes, &parentName, OBJ_CASE_INSENSITIVE, nullptr, nullptr);
    IO_STATUS_BLOCK parentIo{};
    HANDLE parentRaw = INVALID_HANDLE_VALUE;
    const NTSTATUS parentStatus = ntCreateFile(&parentRaw, FILE_TRAVERSE | FILE_READ_ATTRIBUTES | SYNCHRONIZE,
                                              &parentAttributes, &parentIo, nullptr, FILE_ATTRIBUTE_NORMAL,
                                              FILE_SHARE_READ, FILE_OPEN,
                                              FILE_DIRECTORY_FILE | FILE_SYNCHRONOUS_IO_NONALERT, nullptr, 0);
    if (parentStatus < 0) {
        std::ostringstream message;
        message << "NtCreateFile parent failed (NTSTATUS=0x" << std::hex
                << static_cast<ULONG>(parentStatus) << ")";
        throw std::runtime_error(message.str());
    }
    Handle parent(parentRaw);
    FILE_ID_INFO validatedId{}, ntId{};
    if (!GetFileInformationByHandleEx(validatedParent.value, FileIdInfo, &validatedId, sizeof(validatedId)) ||
        !GetFileInformationByHandleEx(parent.value, FileIdInfo, &ntId, sizeof(ntId))) fail("parent FileIdInfo");
    if (validatedId.VolumeSerialNumber != ntId.VolumeSerialNumber ||
        !std::equal(std::begin(validatedId.FileId.Identifier), std::end(validatedId.FileId.Identifier),
                    std::begin(ntId.FileId.Identifier))) fail("parent identity changed", 0);
    const std::wstring leaf = output.filename().wstring();
    if (leaf.empty() || leaf.find(L'\\') != std::wstring::npos || leaf.find(L'/') != std::wstring::npos ||
        leaf.size() * sizeof(wchar_t) > USHRT_MAX) fail("invalid output leaf", 0);
    UNICODE_STRING name{};
    name.Length = static_cast<USHORT>(leaf.size() * sizeof(wchar_t));
    name.MaximumLength = name.Length;
    name.Buffer = const_cast<PWSTR>(leaf.c_str());
    OBJECT_ATTRIBUTES attributes{};
    InitializeObjectAttributes(&attributes, &name, OBJ_CASE_INSENSITIVE, parent.value, nullptr);
    IO_STATUS_BLOCK io{};
    HANDLE raw = INVALID_HANDLE_VALUE;
    // FILE_DIRECTORY_FILE permits FILE_SYNCHRONOUS_IO_NONALERT in the published
    // NtCreateFile contract. FILE_OPEN_REPARSE_POINT is not in that list.
    // FILE_CREATE refuses an existing leaf; link/filter behavior remains a VM check.
    const NTSTATUS status = ntCreateFile(&raw, FILE_LIST_DIRECTORY | FILE_READ_ATTRIBUTES | SYNCHRONIZE,
                                        &attributes, &io, nullptr, FILE_ATTRIBUTE_DIRECTORY, FILE_SHARE_READ,
                                        FILE_CREATE, FILE_DIRECTORY_FILE | FILE_SYNCHRONOUS_IO_NONALERT,
                                        nullptr, 0);
    if (status < 0) {
        std::ostringstream message;
        message << "NtCreateFile new output directory failed (NTSTATUS=0x" << std::hex
                << static_cast<ULONG>(status) << ")";
        throw std::runtime_error(message.str());
    }
    Handle created(raw);
    if (!created.valid() || io.Information != FILE_CREATED) fail("output directory was not newly created", 0);
    return created;
}

Identity identify(HANDLE h, bool directory = false) {
    FILE_ID_INFO id{};
    if (!GetFileInformationByHandleEx(h, FileIdInfo, &id, sizeof(id))) fail("FileIdInfo");
    DWORD length = GetFinalPathNameByHandleW(h, nullptr, 0, FILE_NAME_NORMALIZED);
    if (!length) fail("GetFinalPathNameByHandleW length");
    std::wstring path(length + 1, L'\0');
    DWORD used = GetFinalPathNameByHandleW(h, path.data(), static_cast<DWORD>(path.size()), FILE_NAME_NORMALIZED);
    if (!used || used >= path.size()) fail("GetFinalPathNameByHandleW");
    path.resize(used);
    std::array<unsigned char, 8> volume{};
    for (size_t i = 0; i < volume.size(); ++i) volume[i] = static_cast<unsigned char>(id.VolumeSerialNumber >> (8 * i));
    Identity result{hex(volume.data(), volume.size()), hex(id.FileId.Identifier, sizeof(id.FileId.Identifier)), utf8(path), {}};
    if (!directory) result.hash = sha256(h);
    return result;
}

Identity identifyPath(const fs::path& path, bool directory = false) {
    Handle h = openRead(path, directory);
    return identify(h.value, directory);
}

void record(std::ofstream& log, const std::string& label, const Identity& id) {
    log << "{\"event\":" << quoteJson(label) << ",\"volume\":" << quoteJson(id.volume)
        << ",\"file_id\":" << quoteJson(id.fileId) << ",\"final_path\":" << quoteJson(id.finalPath)
        << ",\"sha256\":" << quoteJson(id.hash) << "}\n";
    log.flush();
    if (!log) fail("write identity log", 0);
}

bool nativeArm64(HANDLE process) {
    USHORT processMachine = 0, nativeMachine = 0;
    if (!IsWow64Process2(process, &processMachine, &nativeMachine)) fail("IsWow64Process2");
    return processMachine == IMAGE_FILE_MACHINE_UNKNOWN && nativeMachine == IMAGE_FILE_MACHINE_ARM64;
}

void requireArm64Pe(const fs::path& path) {
    Handle h = openRead(path);
    IMAGE_DOS_HEADER dos{};
    DWORD n = 0;
    if (!ReadFile(h.value, &dos, sizeof(dos), &n, nullptr) || n != sizeof(dos) || dos.e_magic != IMAGE_DOS_SIGNATURE) fail("DOS header", 0);
    LARGE_INTEGER offset{}; offset.QuadPart = dos.e_lfanew;
    if (dos.e_lfanew < static_cast<LONG>(sizeof(dos)) || !SetFilePointerEx(h.value, offset, nullptr, FILE_BEGIN)) fail("PE offset", 0);
    DWORD signature = 0;
    IMAGE_FILE_HEADER coff{};
    if (!ReadFile(h.value, &signature, sizeof(signature), &n, nullptr) || n != sizeof(signature) || signature != IMAGE_NT_SIGNATURE ||
        !ReadFile(h.value, &coff, sizeof(coff), &n, nullptr) || n != sizeof(coff) || coff.Machine != IMAGE_FILE_MACHINE_ARM64)
        fail("native ARM64 PE required", 0);
}

void requireLocalNtfs(const fs::path& path) {
    if (!path.is_absolute() || path.root_name().wstring().size() != 2 || path.root_name().wstring()[1] != L':' ||
        path.wstring().find(L"..") != std::wstring::npos) fail("absolute local path without traversal required", 0);
    if (GetDriveTypeW(path.root_path().c_str()) != DRIVE_FIXED) fail("fixed local drive required", 0);
    wchar_t filesystem[64]{};
    if (!GetVolumeInformationW(path.root_path().c_str(), nullptr, 0, nullptr, nullptr, nullptr, filesystem, 64)) fail("GetVolumeInformationW");
    if (_wcsicmp(filesystem, L"NTFS") != 0) fail("NTFS required", 0);
    fs::path walk = path.root_path();
    for (const auto& component : path.relative_path()) {
        walk /= component;
        DWORD attrs = GetFileAttributesW(walk.c_str());
        if (attrs == INVALID_FILE_ATTRIBUTES) {
            if (GetLastError() == ERROR_FILE_NOT_FOUND || GetLastError() == ERROR_PATH_NOT_FOUND) break;
            fail("GetFileAttributesW");
        }
        if (attrs & FILE_ATTRIBUTE_REPARSE_POINT) fail("reparse ancestor rejected", ERROR_REPARSE_TAG_INVALID);
    }
}

std::wstring quoted(const fs::path& path) { return L"\"" + path.wstring() + L"\""; }

struct ChildResult { DWORD code; std::string stdoutText; std::string stderrText; };

// Every launched process is suspended until it is inside this private job.
// The job owns only this invocation's child and its ordinary descendants.
struct OwnedProcess {
    Handle job;
    Handle process;
    Handle thread;
    DWORD pid = 0;
    bool assigned = false;
    bool settled = false;

    OwnedProcess(const fs::path& exe, std::vector<wchar_t>& command,
                 STARTUPINFOW& startup, const fs::path& workDir) {
        job = Handle(CreateJobObjectW(nullptr, nullptr));
        if (!job.valid()) fail("CreateJobObjectW");
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
        limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        if (!SetInformationJobObject(job.value, JobObjectExtendedLimitInformation, &limits, sizeof(limits)))
            fail("SetInformationJobObject");
        PROCESS_INFORMATION pi{};
        if (!CreateProcessW(exe.c_str(), command.data(), nullptr, nullptr, TRUE,
                            CREATE_NO_WINDOW | CREATE_SUSPENDED, nullptr, workDir.c_str(), &startup, &pi))
            fail("CreateProcessW");
        process = Handle(pi.hProcess); thread = Handle(pi.hThread); pid = pi.dwProcessId;
        if (!AssignProcessToJobObject(job.value, process.value)) {
            const DWORD error = GetLastError();
            const std::string status = stop();
            throw std::runtime_error("AssignProcessToJobObject failed (Win32=" + std::to_string(error) + "); " + status);
        }
        assigned = true;
        if (ResumeThread(thread.value) == static_cast<DWORD>(-1)) {
            const DWORD error = GetLastError();
            const std::string status = stop();
            throw std::runtime_error("ResumeThread failed (Win32=" + std::to_string(error) + "); " + status);
        }
    }

    std::string stop() noexcept {
        if (settled || !process.valid()) return "already stopped";
        BOOL terminated = assigned ? TerminateJobObject(job.value, ERROR_TIMEOUT)
                                   : TerminateProcess(process.value, ERROR_TIMEOUT);
        const DWORD terminationError = terminated ? 0 : GetLastError();
        const DWORD rootWait = WaitForSingleObject(process.value, kWaitMs);
        bool empty = !assigned;
        if (assigned) {
            const ULONGLONG deadline = GetTickCount64() + kWaitMs;
            do {
                JOBOBJECT_BASIC_ACCOUNTING_INFORMATION count{};
                if (!QueryInformationJobObject(job.value, JobObjectBasicAccountingInformation,
                                               &count, sizeof(count), nullptr)) break;
                if (count.ActiveProcesses == 0) { empty = true; break; }
                Sleep(10);
            } while (GetTickCount64() < deadline);
        }
        settled = rootWait == WAIT_OBJECT_0 && empty;
        return std::string(settled ? "terminated and reaped" : "STOP UNCONFIRMED") +
               " (termination Win32=" + std::to_string(terminationError) +
               ", root_wait=" + std::to_string(rootWait) + ", job_empty=" +
               (empty ? "true" : "false") + ", pid=" + std::to_string(pid) + ")";
    }

    DWORD waitExit(const char* label, DWORD timeoutMs = kWaitMs) {
        const DWORD wait = WaitForSingleObject(process.value, timeoutMs);
        if (wait != WAIT_OBJECT_0) {
            const std::string status = stop();
            throw std::runtime_error(std::string(label) + " wait=" + std::to_string(wait) + "; " + status);
        }
        JOBOBJECT_BASIC_ACCOUNTING_INFORMATION count{};
        if (!QueryInformationJobObject(job.value, JobObjectBasicAccountingInformation,
                                       &count, sizeof(count), nullptr) || count.ActiveProcesses != 0) {
            const std::string status = stop();
            throw std::runtime_error(std::string(label) + " descendant/query state unexpected; " + status);
        }
        settled = true;
        DWORD code = 0;
        if (!GetExitCodeProcess(process.value, &code)) fail("GetExitCodeProcess");
        return code;
    }

    ~OwnedProcess() {
        if (!settled && process.valid()) std::cerr << "STOP-CLEANUP: " << stop() << "\n";
    }
};

std::string readBytes(const fs::path& path) {
    std::ifstream input(path, std::ios::binary);
    if (!input) fail("read child log", 0);
    return std::string(std::istreambuf_iterator<char>(input), {});
}

ChildResult child(const fs::path& exe, const std::wstring& arguments, const fs::path& output,
                  const std::string& label, std::ofstream& log, DWORD timeoutMs = kWaitMs) {
    requireArm64Pe(exe);
    SECURITY_ATTRIBUTES sa{sizeof(sa), nullptr, TRUE};
    fs::path outPath = output / fs::path(label + ".stdout.bin");
    fs::path errPath = output / fs::path(label + ".stderr.bin");
    Handle out(CreateFileW(outPath.c_str(), GENERIC_WRITE, FILE_SHARE_READ, &sa, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr));
    Handle err(CreateFileW(errPath.c_str(), GENERIC_WRITE, FILE_SHARE_READ, &sa, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr));
    if (!out.valid() || !err.valid()) fail("create child log");
    STARTUPINFOW startup{}; startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES; startup.hStdOutput = out.value; startup.hStdError = err.value;
    startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    std::wstring command = quoted(exe) + L" " + arguments;
    std::vector<wchar_t> commandBuffer(command.begin(), command.end()); commandBuffer.push_back(L'\0');
    OwnedProcess childProcess(exe, commandBuffer, startup, output);
    if (!nativeArm64(childProcess.process.value)) fail("child process is not native ARM64", 0);
    std::wstring actualPath(32768, L'\0');
    DWORD actualLength = static_cast<DWORD>(actualPath.size());
    if (!QueryFullProcessImageNameW(childProcess.process.value, 0, actualPath.data(), &actualLength)) fail("QueryFullProcessImageNameW");
    actualPath.resize(actualLength);
    log << "{\"event\":" << quoteJson(label + "-process") << ",\"native_arm64\":true,\"exe\":"
        << quoteJson(utf8(exe.wstring())) << ",\"actual_exe\":" << quoteJson(utf8(actualPath))
        << ",\"pid\":" << childProcess.pid << "}\n"; log.flush();
    const DWORD code = childProcess.waitExit("child", timeoutMs);
    out = Handle(); err = Handle();
    std::ofstream exitFile(output / fs::path(label + ".exit.txt"), std::ios::binary);
    exitFile << code << "\n"; exitFile.close();
    if (!exitFile) fail("write child exit", 0);
    ChildResult result{code, readBytes(outPath), readBytes(errPath)};
    log << "{\"event\":" << quoteJson(label + "-exit") << ",\"code\":" << code
        << ",\"stdout\":" << quoteJson(outPath.filename().string()) << ",\"stderr\":"
        << quoteJson(errPath.filename().string()) << "}\n"; log.flush();
    return result;
}

void writeText(const fs::path& path, const std::string& bytes) {
    std::ofstream out(path, std::ios::binary | std::ios::trunc);
    out.write(bytes.data(), static_cast<std::streamsize>(bytes.size())); out.close();
    if (!out) fail("write synthetic fixture", 0);
}

void copyNew(const fs::path& source, const fs::path& target) {
    if (!fs::copy_file(source, target, fs::copy_options::none)) fail("copy synthetic fixture", 0);
}

void swapIn(const fs::path& active, const fs::path& replacement, const fs::path& old) {
    if (!MoveFileExW(active.c_str(), old.c_str(), MOVEFILE_WRITE_THROUGH)) fail("archive active file");
    if (!MoveFileExW(replacement.c_str(), active.c_str(), MOVEFILE_WRITE_THROUGH)) fail("activate replacement");
}

void expect(const ChildResult& result, const std::string& marker, const std::string& label) {
    if (result.code != 0 || result.stdoutText.find(marker) == std::string::npos) fail("unexpected " + label + " marker or exit", 0);
}

void makeScripts(const fs::path& dir) {
    for (const char marker : {'A', 'B'}) {
        const std::string m(1, marker);
        writeText(dir / fs::path("script-" + m + ".ps1"),
                  "$modulePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'active.psm1'))\r\n"
                  "Import-Module -Name $modulePath -Force -ErrorAction Stop\r\n"
                  "Write-Output ('PROCESS_PATH=' + (Get-Process -Id $PID).Path)\r\n"
                  "Write-Output ('SCRIPT_PATH=' + $PSCommandPath)\r\n"
                  "Write-Output ('MODULE_PATH=' + (Get-Module -Name active).Path)\r\n"
                  "Write-Output 'SCRIPT_MARKER=" + m + "'\r\n"
                  "Write-Output ('MODULE_MARKER=' + (Get-SyntheticMarker))\r\n");
        writeText(dir / fs::path("module-" + m + ".psm1"),
                  "function Get-SyntheticMarker { '" + m + "' }\r\nExport-ModuleMember -Function Get-SyntheticMarker\r\n");
    }
}

void runCase(const std::wstring& name, const fs::path& pwsh, const fs::path& output,
             const fs::path& binaryDir, std::ofstream& log) {
    if (name == L"directory-contract") return; // VM-only API smoke check; no child or fixture.
    if (name == L"timeout-child") {
        child(binaryDir / L"YimeSyntheticToolA.exe", L"--stall", output, "timeout-child", log, 200);
        fail("fault injection did not time out", 0);
    }
    if (name == L"share" || name == L"replace" || name == L"timeout-actor") {
        const fs::path active = output / L"active.txt", replacement = output / L"replacement.txt", old = output / L"archived.txt";
        writeText(active, "synthetic-identical-bytes\n");
        writeText(replacement, "synthetic-identical-bytes\n");
        Handle held = openRead(active);
        const Identity before = identify(held.value); record(log, "held-file", before);
        const std::wstring readyName = L"Local\\YimeProbeReady-" + std::to_wstring(GetCurrentProcessId());
        const std::wstring goName = L"Local\\YimeProbeGo-" + std::to_wstring(GetCurrentProcessId());
        Handle ready(CreateEventW(nullptr, TRUE, FALSE, readyName.c_str()));
        if (!ready.valid() || GetLastError() == ERROR_ALREADY_EXISTS) fail("create ready event");
        Handle go(CreateEventW(nullptr, TRUE, FALSE, goName.c_str()));
        if (!go.valid() || GetLastError() == ERROR_ALREADY_EXISTS) fail("create go event");
        // The actor waits on go; the parent must signal only after it observes ready.
        const fs::path actor = binaryDir / L"YimeSyntheticToolA.exe";
        requireArm64Pe(actor);
        SECURITY_ATTRIBUTES sa{sizeof(sa), nullptr, TRUE};
        const fs::path outPath = output / L"actor.stdout.bin", errPath = output / L"actor.stderr.bin";
        Handle out(CreateFileW(outPath.c_str(), GENERIC_WRITE, FILE_SHARE_READ, &sa, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr));
        Handle err(CreateFileW(errPath.c_str(), GENERIC_WRITE, FILE_SHARE_READ, &sa, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr));
        if (!out.valid() || !err.valid()) fail("create actor logs");
        STARTUPINFOW startup{}; startup.cb = sizeof(startup); startup.dwFlags = STARTF_USESTDHANDLES;
        startup.hStdOutput = out.value; startup.hStdError = err.value; startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
        const std::wstring actorMode = name == L"timeout-actor" ? L"--actor-stall" : L"--actor";
        std::wstring command = quoted(actor) + L" " + actorMode + L" " + quoted(active) + L" \"" + readyName + L"\" \"" + goName + L"\" " + quoted(old);
        std::vector<wchar_t> buffer(command.begin(), command.end()); buffer.push_back(L'\0');
        OwnedProcess actorProcess(actor, buffer, startup, output);
        if (!nativeArm64(actorProcess.process.value)) fail("actor process is not native ARM64", 0);
        log << "{\"event\":\"actor-process\",\"native_arm64\":true,\"pid\":"
            << actorProcess.pid << "}\n"; log.flush();
        if (WaitForSingleObject(ready.value, kWaitMs) != WAIT_OBJECT_0) fail("actor ready timeout");
        if (name != L"timeout-actor" && !SetEvent(go.value)) fail("signal actor");
        const DWORD code = actorProcess.waitExit("actor", name == L"timeout-actor" ? 200 : kWaitMs);
        if (name == L"timeout-actor") fail("actor fault injection did not time out", 0);
        out = Handle(); err = Handle();
        writeText(output / L"actor.exit.txt", std::to_string(code) + "\n");
        const std::string actorOutput = readBytes(outPath);
        log << "{\"event\":\"actor-result\",\"native_arm64\":true,\"exit\":" << code
            << ",\"raw\":" << quoteJson(actorOutput) << "}\n"; log.flush();
        if (code != 0 || actorOutput.find("WRITE_ERROR=32") == std::string::npos ||
            actorOutput.find("DELETE_ERROR=32") == std::string::npos ||
            actorOutput.find("RENAME_ERROR=0") != std::string::npos) fail("share conflict mismatch", 0);
        record(log, "held-after-attempt", identify(held.value));
        if (name == L"replace") {
            held = Handle();
            swapIn(active, replacement, old);
            const Identity after = identifyPath(active); record(log, "reopened-after-replace", after);
            if (before.hash != after.hash || (before.volume == after.volume && before.fileId == after.fileId))
                fail("same-byte replacement identity mismatch", 0);
        }
        return;
    }
    if (name == L"script-module") {
        makeScripts(output);
        fs::path script = output / L"active.ps1", module = output / L"active.psm1";
        copyNew(output / L"script-A.ps1", script); copyNew(output / L"module-A.psm1", module);
        const Identity scriptA = identifyPath(script), moduleA = identifyPath(module);
        record(log, "script-A", scriptA); record(log, "module-A", moduleA);
        expect(child(pwsh, L"-NoProfile -NonInteractive -File " + quoted(script), output, "ps-A", log),
               "SCRIPT_MARKER=A", "script A");
        const std::string a = readBytes(output / L"ps-A.stdout.bin");
        if (a.find("MODULE_MARKER=A") == std::string::npos ||
            a.find("SCRIPT_PATH=" + utf8(script.wstring())) == std::string::npos ||
            a.find("MODULE_PATH=" + utf8(module.wstring())) == std::string::npos)
            fail("script/module A marker or reported path", 0);
        copyNew(output / L"script-B.ps1", output / L"next.ps1");
        copyNew(output / L"module-B.psm1", output / L"next.psm1");
        swapIn(script, output / L"next.ps1", output / L"old.ps1");
        swapIn(module, output / L"next.psm1", output / L"old.psm1");
        const Identity scriptB = identifyPath(script), moduleB = identifyPath(module);
        record(log, "script-B", scriptB); record(log, "module-B", moduleB);
        if ((scriptA.volume == scriptB.volume && scriptA.fileId == scriptB.fileId) ||
            (moduleA.volume == moduleB.volume && moduleA.fileId == moduleB.fileId)) fail("script/module file ID did not change", 0);
        expect(child(pwsh, L"-NoProfile -NonInteractive -File " + quoted(script), output, "ps-B", log),
               "SCRIPT_MARKER=B", "script B");
        const std::string b = readBytes(output / L"ps-B.stdout.bin");
        if (b.find("MODULE_MARKER=B") == std::string::npos ||
            b.find("SCRIPT_PATH=" + utf8(script.wstring())) == std::string::npos ||
            b.find("MODULE_PATH=" + utf8(module.wstring())) == std::string::npos)
            fail("script/module B marker or reported path", 0);
        return;
    }
    if (name == L"tool" || name == L"dll") {
        const bool dll = name == L"dll";
        const fs::path active = output / (dll ? L"active.dll" : L"active.exe");
        const fs::path next = output / (dll ? L"next.dll" : L"next.exe");
        const fs::path old = output / (dll ? L"old.dll" : L"old.exe");
        const fs::path sourceA = binaryDir / (dll ? L"YimeSyntheticModuleA.dll" : L"YimeSyntheticToolA.exe");
        const fs::path sourceB = binaryDir / (dll ? L"YimeSyntheticModuleB.dll" : L"YimeSyntheticToolB.exe");
        requireArm64Pe(sourceA); requireArm64Pe(sourceB);
        copyNew(sourceA, active);
        const Identity activeA = identifyPath(active); record(log, "active-A", activeA);
        const fs::path loader = dll ? binaryDir / L"YimeSyntheticToolA.exe" : active;
        expect(child(loader, dll ? L"--load-dll " + quoted(active) : L"", output, "load-A", log),
               dll ? "DLL_MARKER=A" : "TOOL_MARKER=A", "load A");
        copyNew(sourceB, next); swapIn(active, next, old);
        const Identity activeB = identifyPath(active); record(log, "active-B", activeB);
        if (activeA.volume == activeB.volume && activeA.fileId == activeB.fileId) fail("loaded file ID did not change", 0);
        expect(child(loader, dll ? L"--load-dll " + quoted(active) : L"", output, "load-B", log),
               dll ? "DLL_MARKER=B" : "TOOL_MARKER=B", "load B");
        return;
    }
    fail("unknown case", 0);
}
}

int wmain(int argc, wchar_t** argv) {
    fs::path output;
    Handle ownedDirectory;
    std::ofstream log;
    bool createdDirectory = false;
    try {
        if (argc != 7 || std::wstring(argv[1]) != L"--pwsh" ||
            std::wstring(argv[3]) != L"--output" || std::wstring(argv[5]) != L"--case") fail("exact CLI required", 0);
        fs::path pwsh(argv[2]); output = fs::path(argv[4]);
        const std::wstring name(argv[6]);
        if (name != L"share" && name != L"replace" && name != L"script-module" && name != L"tool" && name != L"dll" &&
            name != L"timeout-child" && name != L"timeout-actor" && name != L"directory-contract") fail("unknown case", 0);
        if (!nativeArm64(GetCurrentProcess())) fail("native ARM64 process required", 0);
        requireLocalNtfs(pwsh); requireLocalNtfs(output);
        if (_wcsicmp(pwsh.filename().c_str(), L"pwsh.exe") != 0 || !fs::is_regular_file(pwsh)) fail("fixed pwsh.exe file required", 0);
        if (fs::exists(output) || !fs::is_directory(output.parent_path()) ||
            output.filename().wstring().rfind(L"probe-", 0) != 0) fail("new probe-* output directory required", 0);
        requireArm64Pe(pwsh);
        wchar_t self[32768]{};
        DWORD size = GetModuleFileNameW(nullptr, self, 32768);
        if (!size || size >= 32768) fail("GetModuleFileNameW");
        const fs::path binaryDir = fs::path(self).parent_path();
        requireLocalNtfs(binaryDir);
        for (const wchar_t* file : {L"YimeSyntheticToolA.exe", L"YimeSyntheticToolB.exe",
                                    L"YimeSyntheticModuleA.dll", L"YimeSyntheticModuleB.dll"})
            requireArm64Pe(binaryDir / file);
        ownedDirectory = createHeldDirectory(output);
        createdDirectory = true;
        requireLocalNtfs(output);
        log.open(output / L"events.jsonl", std::ios::binary);
        if (!log) fail("create event log", 0);
        log << "{\"event\":\"probe-process\",\"native_arm64\":true,\"pid\":"
            << GetCurrentProcessId() << "}\n"; log.flush();
        record(log, "output-directory", identify(ownedDirectory.value, true));
        record(log, "pwsh-file", identifyPath(pwsh));
        runCase(name, pwsh, output, binaryDir, log);
        log << "{\"event\":\"case-passed\"}\n"; log.flush();
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "STOP: " << e.what() << "\n";
        if (createdDirectory && ownedDirectory.valid() && log.is_open()) {
            log << "{\"event\":\"case-failed\",\"reason\":" << quoteJson(e.what()) << "}\n";
            log.flush();
        }
        return 1;
    }
}
