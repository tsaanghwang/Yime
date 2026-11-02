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
// Persistent shape, not a transient API cache, authorizes bounded removal.
enum class PersistentKind { Absent, Complete, Partial, ForeignOrUnknown };
inline PersistentKind ClassifyPersistent(bool knownExact, bool anyTip,
    bool machineProfile, unsigned categoryMask, bool completeCom) noexcept {
    constexpr unsigned all = 31;
    if (!knownExact || !completeCom || (categoryMask & ~all)) return PersistentKind::ForeignOrUnknown;
    if (!anyTip) return PersistentKind::Absent;
    return machineProfile && categoryMask == all ? PersistentKind::Complete : PersistentKind::Partial;
}
inline bool ShouldRemoveCategory(unsigned presentMask, unsigned index) noexcept {
    return index < 5 && (presentMask & (1u << index)) != 0;
}
inline bool FinalApiAbsent(bool categoriesKnown, unsigned categories,
                           bool profilesKnown, unsigned profiles) noexcept {
    return categoriesKnown && profilesKnown && categories == 0 && profiles == 0;
}
inline bool ValidProfileShape(bool machine, unsigned subkeys, unsigned values,
    bool typedKnown, bool descriptionMatches, bool iconMatches, unsigned iconIndex, unsigned enable) noexcept {
    if(subkeys || !typedKnown) return false;
    if(values==0) return true;
    if(!machine) return values==1 && enable<=1;
    return values==4 && descriptionMatches && iconMatches && iconIndex==0 && enable<=1;
}
inline bool MayMaintainPersistent(PersistentKind kind,bool foreignApiObservation) noexcept {
    return kind!=PersistentKind::ForeignOrUnknown && !foreignApiObservation;
}
}
