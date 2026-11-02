#pragma once
#include <string_view>
namespace yime18ureg {
enum class Operation { Invalid, Status, VerifyAbsent, Register, Unregister, CheckOwned };
inline Operation Parse(int argc, const wchar_t* action) noexcept {
    const std::wstring_view a = action ? action : L"";
    if (argc == 2 && a == L"status") return Operation::Status;
    if (argc == 2 && a == L"verify-absent") return Operation::VerifyAbsent;
    if (argc == 3 && a == L"check-owned") return Operation::CheckOwned;
    if (argc == 3 && a == L"register") return Operation::Register;
    if (argc == 3 && a == L"unregister") return Operation::Unregister;
    return Operation::Invalid;
}
// Uses actual adapter observations; unknown queries never imply absence.
inline bool CanRegister(bool queriesKnown, bool anyCom, bool anyTip, unsigned categories) noexcept {
    return queriesKnown && !anyCom && !anyTip && categories == 0;
}
inline bool CanRemoveCom(bool ownedShape, bool profileRemovalSucceeded,
                         bool categoriesAbsent, bool profilesAbsent) noexcept {
    return ownedShape && profileRemovalSucceeded && categoriesAbsent && profilesAbsent;
}
inline bool RemovableResidue(unsigned subkeys, unsigned values, bool profileLeaf,
                             bool soleEnableDwordZero) noexcept {
    return subkeys == 0 && (values == 0 || (profileLeaf && values == 1 && soleEnableDwordZero));
}
}
