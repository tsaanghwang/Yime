// Isolated filesystem and injected-resolver checks only. This executable never
// initializes COM/TSF, reads installation/registration state, or loads a TIP.
// It requires a fresh, explicitly supplied scratch directory and retains it.
#include "TouchFrontendNativeHostPaths.h"
#include <iostream>

namespace {
namespace fs = std::filesystem;
using yime::nativehost::EvidenceDirectoryBoundary;
namespace detail = yime::nativehost::pathdetail;

void check(bool value, const char* message) {
    if (!value) throw std::runtime_error(message);
}
template<class Action>
void rejects(Action&& action, const char* expected) {
    try { action(); }
    catch (const std::exception& error) {
        check(std::string(error.what()).find(expected) != std::string::npos,
              "rejection must preserve the expected failure stage");
        return;
    }
    throw std::runtime_error("expected evidence boundary rejection");
}

void injectedResolverCases() {
    // Deterministic alias regression, even where NTFS short names are disabled.
    const fs::path canonicalRoot = LR"(\\?\Volume{11111111-1111-1111-1111-111111111111}\Installed Product)";
    const fs::path canonicalOutside = LR"(\\?\Volume{11111111-1111-1111-1111-111111111111}\Evidence)";
    const fs::path inputRoot = LR"(C:\Installed Product)";
    unsigned calls = 0;
    auto alias = [&](const fs::path& input) -> fs::path {
        ++calls;
        if (input == inputRoot || input == fs::path(LR"(C:\INSTAL~1)")) return canonicalRoot;
        if (input == fs::path(LR"(C:\INSTAL~1\nested)")) return canonicalRoot / L"nested";
        if (input == fs::path(LR"(C:\Evidence)")) return canonicalOutside;
        throw std::runtime_error("unexpected resolver input");
    };
    rejects([&] { detail::ResolveEvidenceOutput(inputRoot, LR"(C:\INSTAL~1\run)", alias); }, "outside installed root");
    check(calls == 2, "alias must be resolved before containment is decided");
    rejects([&] { detail::ResolveEvidenceOutput(inputRoot, LR"(C:\INSTAL~1\nested\run)", alias); }, "outside installed root");
    const auto outside = detail::ResolveEvidenceOutput(inputRoot, LR"(C:\Evidence\run)", alias);
    check(outside == canonicalOutside / L"run", "write path must use resolved parent spelling");
    check(detail::WithinFinalDirectory(canonicalRoot / L"nested", canonicalRoot), "descendant is inside");
    check(!detail::WithinFinalDirectory(fs::path(canonicalRoot.wstring() + L"-sibling"), canonicalRoot),
          "same prefix with different component is outside");
    check(detail::WithinFinalDirectory(fs::path(canonicalRoot.wstring() + L"\\"), canonicalRoot),
          "trailing separator must not bypass equal root");
    auto failure = [](const fs::path&) -> fs::path { throw std::runtime_error("injected canonical resolution failure"); };
    rejects([&] { detail::ResolveEvidenceOutput(inputRoot, LR"(C:\Evidence\run)", failure); }, "injected canonical resolution failure");
    auto parentFailure = [&](const fs::path& input) -> fs::path {
        if (input == inputRoot) return canonicalRoot;
        throw std::runtime_error("injected parent resolution failure");
    };
    rejects([&] { detail::ResolveEvidenceOutput(inputRoot, LR"(C:\Evidence\run)", parentFailure); }, "injected parent resolution failure");
    rejects([&] { detail::ResolveEvidenceOutput(inputRoot, LR"(C:\Evidence\..)", alias); }, "ordinary directory name");
    rejects([&] { detail::ResolveEvidenceOutput(inputRoot, LR"(C:\Evidence\run.)", alias); }, "ordinary directory name");
    rejects([&] { detail::ResolveEvidenceOutput(inputRoot, LR"(C:\Evidence\run:stream)", alias); }, "ordinary directory name");
    std::cout << "PASS injected alias, normalization failure, component boundary and leaf contracts\n";
}

std::wstring shortPath(const fs::path& path) {
    const DWORD size = GetShortPathNameW(path.c_str(), nullptr, 0);
    if (!size) detail::Win32Failure("query isolated short-path size");
    std::vector<wchar_t> buffer(static_cast<size_t>(size) + 1);
    const DWORD count = GetShortPathNameW(path.c_str(), buffer.data(), static_cast<DWORD>(buffer.size()));
    if (!count) detail::Win32Failure("query isolated short path");
    check(count < buffer.size(), "short-path size changed");
    return std::wstring(buffer.data(), count);
}

void filesystemCases(const fs::path& scratch) {
    check(scratch.is_absolute() && !fs::exists(scratch) && fs::is_directory(scratch.parent_path()),
          "supply a fresh absolute scratch directory with an existing parent");
    check(fs::create_directory(scratch), "create isolated scratch once");
    const auto installed = scratch / L"Installed Product With Long Name";
    const auto outside = scratch / L"Evidence Outside Product";
    const auto sibling = scratch / L"Installed Product With Long Name-Sibling";
    check(fs::create_directory(installed) && fs::create_directory(outside) && fs::create_directory(sibling),
          "create isolated fixture directories");
    check(fs::create_directory(installed / L"nested"), "create isolated nested directory");

    rejects([&] { EvidenceDirectoryBoundary b(installed, installed / L"new-run"); }, "outside installed root");
    rejects([&] { EvidenceDirectoryBoundary b(installed, installed / L"nested" / L"new-run"); }, "outside installed root");
    check(!fs::exists(installed / L"new-run") && !fs::exists(installed / L"nested" / L"new-run"),
          "rejected paths must not create evidence directories");
    rejects([&] { EvidenceDirectoryBoundary b(installed, scratch / L"missing-parent" / L"run"); }, "open evidence boundary directory");
    {
        EvidenceDirectoryBoundary boundary(installed, outside / L"not-created");
        rejects([&] { boundary.VerifyCreated(); }, "open evidence boundary directory");
        rejects([&] { boundary.VerifyCreated(); }, "one-shot");
        check(!fs::exists(outside / L"not-created"), "failed verification must not create output");
    }
    {
        EvidenceDirectoryBoundary boundary(installed, outside / L"new-run");
        check(fs::create_directory(boundary.OutputPath()), "create canonical outside evidence directory");
        boundary.VerifyCreated();
        check(fs::is_directory(outside / L"new-run"), "canonical output refers to requested outside directory");
        rejects([&] { boundary.VerifyCreated(); }, "one-shot");
    }
    rejects([&] { EvidenceDirectoryBoundary b(installed, outside / L"new-run"); }, "already exists");
    {
        EvidenceDirectoryBoundary boundary(installed, sibling / L"new-run");
        check(fs::create_directory(boundary.OutputPath()), "prefix sibling is allowed");
        boundary.VerifyCreated();
    }
    std::cout << "PASS real directory-handle resolution, outside creation, containment and failure paths\n";

    const fs::path alias = shortPath(installed);
    if (detail::EqualOrdinal(alias.wstring(), installed.wstring())) {
        std::cout << "NOT_AVAILABLE actual 8.3 alias: filesystem returned the long spelling; injected alias regression passed\n";
    } else {
        rejects([&] { EvidenceDirectoryBoundary b(installed, alias / L"alias-run"); }, "outside installed root");
        rejects([&] { EvidenceDirectoryBoundary b(alias, installed / L"reverse-alias-run"); }, "outside installed root");
        check(!fs::exists(installed / L"alias-run") && !fs::exists(installed / L"reverse-alias-run"),
              "actual alias rejection must not create output");
        std::cout << "PASS actual 8.3 alias in output parent and installed root\n";
    }
    std::cout << "Scratch retained; no recursive cleanup and no TSF/COM/profile operations\n";
}
} // namespace

int wmain(int argc, wchar_t** argv) {
    try {
        check(argc == 2, "usage: PathTests <fresh-absolute-scratch-directory>");
        injectedResolverCases();
        filesystemCases(fs::path(argv[1]));
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL " << error.what() << "\nScratch retained; do not automatically retry\n";
        return 1;
    }
}
