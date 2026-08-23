#pragma once

#include <windows.h>
#include <cwchar>
#include <string>

namespace PIME {

inline bool canFallbackToPipeAclAfterProcessQueryFailure(DWORD) {
	// A pipe server controls its own security descriptor, so inspecting or
	// trusting that descriptor cannot authenticate the server. Fail closed when
	// Windows does not permit process identity verification.
	return false;
}

inline std::wstring normalizedExecutablePath(std::wstring path) {
	for (auto& value : path) {
		if (value == L'/') {
			value = L'\\';
		}
	}
	while (path.size() > 3 && path.back() == L'\\') {
		path.pop_back();
	}
	return path;
}

inline bool isExpectedLauncherExecutablePath(
	const std::wstring& imagePath,
	const std::wstring& expectedPath) {
	if (imagePath.empty() || expectedPath.empty()) {
		return false;
	}
	const auto actual = normalizedExecutablePath(imagePath);
	const auto expected = normalizedExecutablePath(expectedPath);
	return _wcsicmp(actual.c_str(), expected.c_str()) == 0;
}

} // namespace PIME
