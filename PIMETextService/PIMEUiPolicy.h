#ifndef PIME_UI_POLICY_H
#define PIME_UI_POLICY_H

#include <windows.h>

namespace PIME {

constexpr int kDefaultCandidateFontSize = 12;
constexpr int kMinimumCandidateFontSize = 6;
constexpr int kMaximumCandidateFontSize = 72;

inline int normalizeCandidateFontSize(int requested) {
	if (requested < kMinimumCandidateFontSize) {
		return kMinimumCandidateFontSize;
	}
	if (requested > kMaximumCandidateFontSize) {
		return kMaximumCandidateFontSize;
	}
	return requested;
}

inline BOOL shouldShowOwnedCandidateWindow(bool registeredWithUiElementManager,
	BOOL hostRequestsOwnedWindow) {
	return registeredWithUiElementManager ? hostRequestsOwnedWindow : TRUE;
}

inline POINT popupAnchorInWorkArea(const RECT& selectionRect, SIZE popupSize,
	const RECT& workArea) {
	POINT point = { selectionRect.left, selectionRect.bottom };
	const LONG width = popupSize.cx > 0 ? popupSize.cx : 0;
	const LONG height = popupSize.cy > 0 ? popupSize.cy : 0;
	if (point.x + width > workArea.right) {
		point.x = workArea.right - width;
	}
	if (point.y + height > workArea.bottom) {
		point.y = selectionRect.top - height;
	}
	point.x = point.x < workArea.left ? workArea.left : point.x;
	point.y = point.y < workArea.top ? workArea.top : point.y;
	return point;
}

} // namespace PIME

#endif
