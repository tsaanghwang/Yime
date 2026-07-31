#include "gtest/gtest.h"

#include <windows.h>

#include "BorrowedFont.h"

namespace {

HFONT makeTestFont(int height) {
    LOGFONTW font = {};
    font.lfHeight = height;
    font.lfWeight = FW_NORMAL;
    return ::CreateFontIndirectW(&font);
}

bool isLiveFont(HFONT font) {
    LOGFONTW details = {};
    return ::GetObjectW(font, sizeof(details), &details) == sizeof(details);
}

} // namespace

TEST(BorrowedFontTest, RepeatedAssignmentNeverDeletesSharedHandles) {
    HFONT first = makeTestFont(-18);
    HFONT shared = makeTestFont(-24);
    ASSERT_NE(first, nullptr);
    ASSERT_NE(shared, nullptr);

    HFONT slot = first;
    Ime::assignBorrowedFont(slot, shared);
    EXPECT_EQ(slot, shared);
    EXPECT_TRUE(isLiveFont(first));
    EXPECT_TRUE(isLiveFont(shared));

    // Each quick-forget notification reapplies the same TextService-owned font.
    // Repeating the operation must not invalidate the candidate window handle.
    Ime::assignBorrowedFont(slot, shared);
    EXPECT_EQ(slot, shared);
    EXPECT_TRUE(isLiveFont(shared));

    EXPECT_TRUE(::DeleteObject(first));
    EXPECT_TRUE(::DeleteObject(shared));
}
