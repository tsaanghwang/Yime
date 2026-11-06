#pragma once
// Evidence paths are resolved through existing directory handles, not lexical
// spelling. This is used only by the explicitly requested native host entry.
#include <windows.h>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <system_error>
#include <utility>
#include <vector>

namespace yime::nativehost {
namespace pathdetail {
namespace fs = std::filesystem;

[[noreturn]] inline void Win32Failure(const char* stage, DWORD error = GetLastError()) {
    throw std::system_error(static_cast<int>(error ? error : ERROR_GEN_FAILURE),
                            std::system_category(), stage);
}

inline bool EqualOrdinal(const std::wstring& a, const std::wstring& b) {
    return CompareStringOrdinal(a.data(), static_cast<int>(a.size()), b.data(),
                                static_cast<int>(b.size()), TRUE) == CSTR_EQUAL;
}

inline std::wstring WithoutTrailingSeparator(std::wstring path) {
    while (!path.empty() && path.back() == L'\\') path.pop_back();
    return path;
}

// Both arguments must already be normalized final directory paths from the
// same namespace (volume GUIDs). Never call this with user-supplied spellings.
inline bool WithinFinalDirectory(const fs::path& child, const fs::path& root) {
    const auto a = WithoutTrailingSeparator(child.wstring());
    const auto b = WithoutTrailingSeparator(root.wstring());
    if (a.empty() || b.empty()) throw std::runtime_error("empty final directory path");
    return EqualOrdinal(a, b) || (a.size() > b.size() && a[b.size()] == L'\\' &&
        EqualOrdinal(a.substr(0, b.size()), b));
}

// The resolver is injectable only for offline contract tests. The real boundary
// below always uses DirectoryHandle and GetFinalPathNameByHandleW.
template<class ResolveDirectory>
fs::path ResolveEvidenceOutput(const fs::path& installedRoot, const fs::path& requested,
                               ResolveDirectory&& resolve) {
    const auto leaf = requested.filename().wstring();
    if (!requested.is_absolute() || leaf.empty() || leaf == L"." || leaf == L".." ||
        leaf.back() == L'.' || leaf.back() == L' ' ||
        leaf.find_first_of(L"<>:\"/\\|?*") != std::wstring::npos)
        throw std::runtime_error("evidence output must have a new ordinary directory name");
    for (const auto c : leaf) if (c < 32) throw std::runtime_error("invalid evidence directory name");
    const auto root = resolve(installedRoot);
    const auto parent = resolve(requested.parent_path());
    if (WithinFinalDirectory(parent, root))
        throw std::runtime_error("output must be outside installed root");
    return parent / leaf;
}

class DirectoryHandle {
    HANDLE value_ = INVALID_HANDLE_VALUE;
public:
    explicit DirectoryHandle(const fs::path& path) {
        value_ = CreateFileW(path.c_str(), FILE_READ_ATTRIBUTES,
            FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
            FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
        if (value_ == INVALID_HANDLE_VALUE) Win32Failure("open evidence boundary directory");
        BY_HANDLE_FILE_INFORMATION info{};
        if (!GetFileInformationByHandle(value_, &info)) {
            const DWORD error = GetLastError(); CloseHandle(value_); value_ = INVALID_HANDLE_VALUE;
            Win32Failure("read evidence boundary directory", error);
        }
        if (!(info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ||
            (info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)) {
            CloseHandle(value_); value_ = INVALID_HANDLE_VALUE;
            throw std::runtime_error("evidence boundary requires an unlinked directory");
        }
    }
    ~DirectoryHandle() { if (value_ != INVALID_HANDLE_VALUE) CloseHandle(value_); }
    DirectoryHandle(DirectoryHandle&& other) noexcept : value_(other.value_) { other.value_ = INVALID_HANDLE_VALUE; }
    DirectoryHandle& operator=(DirectoryHandle&& other) noexcept { std::swap(value_, other.value_); return *this; }
    DirectoryHandle(const DirectoryHandle&) = delete;
    DirectoryHandle& operator=(const DirectoryHandle&) = delete;

    fs::path FinalPath() const {
        constexpr DWORD flags = FILE_NAME_NORMALIZED | VOLUME_NAME_GUID;
        const DWORD size = GetFinalPathNameByHandleW(value_, nullptr, 0, flags);
        if (!size) Win32Failure("size final evidence directory path");
        if (size >= 32768) throw std::runtime_error("final evidence directory path too long");
        std::vector<wchar_t> path(static_cast<size_t>(size) + 1);
        const DWORD count = GetFinalPathNameByHandleW(value_, path.data(), static_cast<DWORD>(path.size()), flags);
        if (!count) Win32Failure("resolve final evidence directory path");
        if (count >= path.size()) throw std::runtime_error("final evidence directory path changed");
        const std::wstring result(path.data(), count);
        if (result.rfind(L"\\\\?\\Volume{", 0) != 0)
            throw std::runtime_error("evidence directory requires a local volume identity");
        return result;
    }
};
} // namespace pathdetail

// Retain directory handles without FILE_SHARE_DELETE until all evidence has
// been written. Call VerifyCreated immediately after creating OutputPath and
// before the first evidence write. No file or directory is created here.
class EvidenceDirectoryBoundary {
    std::vector<pathdetail::DirectoryHandle> directories_;
    std::filesystem::path root_, parent_, output_;
    bool verificationAttempted_ = false;
public:
    EvidenceDirectoryBoundary(const std::filesystem::path& installedRoot,
                              const std::filesystem::path& requestedOutput) {
        directories_.reserve(3);
        auto resolve = [&](const std::filesystem::path& path) {
            directories_.emplace_back(path);
            return directories_.back().FinalPath();
        };
        output_ = pathdetail::ResolveEvidenceOutput(installedRoot, requestedOutput, resolve);
        root_ = directories_[0].FinalPath();
        parent_ = directories_[1].FinalPath();
        if (pathdetail::WithinFinalDirectory(parent_, root_))
            throw std::runtime_error("evidence boundary changed during resolution");
        if (std::filesystem::exists(output_)) throw std::runtime_error("evidence output already exists");
    }
    const std::filesystem::path& OutputPath() const noexcept { return output_; }
    void VerifyCreated() {
        if (verificationAttempted_) throw std::runtime_error("evidence directory verification is one-shot");
        verificationAttempted_ = true;
        directories_.emplace_back(output_);
        const auto actual = directories_.back().FinalPath();
        const auto currentRoot = directories_[0].FinalPath();
        const auto currentParent = directories_[1].FinalPath();
        if (!pathdetail::EqualOrdinal(actual.wstring(), output_.wstring()) ||
            !pathdetail::EqualOrdinal(currentRoot.wstring(), root_.wstring()) ||
            !pathdetail::EqualOrdinal(currentParent.wstring(), parent_.wstring()) ||
            pathdetail::WithinFinalDirectory(actual, currentRoot))
            throw std::runtime_error("evidence boundary changed before first write");
    }
};
} // namespace yime::nativehost
