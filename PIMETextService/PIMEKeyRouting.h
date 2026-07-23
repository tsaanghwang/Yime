// Copyright (C) 2026 Yime contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

#ifndef PIME_KEY_ROUTING_H
#define PIME_KEY_ROUTING_H

#include <windows.h>

namespace PIME {

inline bool shouldCandidateWindowHandleKey(UINT keyCode, bool controlDown) {
	if (controlDown && (keyCode == VK_LEFT || keyCode == VK_RIGHT)) {
		return false;
	}

	switch (keyCode) {
	case VK_UP:
	case VK_DOWN:
	case VK_LEFT:
	case VK_RIGHT:
	case VK_RETURN:
	case VK_SPACE:
		return true;
	default:
		return false;
	}
}

} // namespace PIME

#endif
