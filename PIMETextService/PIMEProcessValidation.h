#pragma once

#include <cwchar>
#include <string>

namespace PIME {

inline bool isExpectedLauncherExecutablePath(const std::wstring& imagePath) {
	const std::wstring::size_type separator = imagePath.find_last_of(L"\\/");
	const wchar_t* fileName = imagePath.c_str() +
		(separator == std::wstring::npos ? 0 : separator + 1);
	return _wcsicmp(fileName, L"PIMELauncher.exe") == 0;
}

} // namespace PIME
