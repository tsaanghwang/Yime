#ifndef IME_BORROWED_FONT_H
#define IME_BORROWED_FONT_H

#include <windows.h>

namespace Ime {

// IME popup windows borrow the font owned by TextService. Replacing that
// handle must never delete either the old or the new font; the owner controls
// their lifetime and may share the same handle with several windows.
inline void assignBorrowedFont(HFONT& current, HFONT replacement) noexcept {
    current = replacement;
}

} // namespace Ime

#endif
