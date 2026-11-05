#include "../ProductRegistrationPolicy.h"
#include <stdexcept>
#include <iostream>
void check(bool value) { if (!value) throw std::runtime_error("product registration policy check failed"); }
int main() {
    using namespace yime18ureg;
    check(Parse(2,L"status")==Operation::Status);
    check(Parse(2,L"verify-absent")==Operation::VerifyAbsent);
    check(Parse(3,L"check-owned")==Operation::CheckOwned);
    check(Parse(3,L"register")==Operation::Register);
    check(Parse(3,L"unregister")==Operation::Unregister);
    check(Parse(3,L"unregister-tip")==Operation::UnregisterTip);
    check(Parse(2,L"unregister-tip")==Operation::Invalid);
    check(Parse(2,L"unregister")==Operation::Invalid);
    check(Parse(3,L"repoint")==Operation::Invalid);
    check(Parse(3,L"register-com")==Operation::Invalid);
    check(Parse(1,nullptr)==Operation::Invalid);
    check(CanRegister(true,false,false,0));
    check(!CanRegister(false,false,false,0));
    check(!CanRegister(true,true,false,0));
    check(!CanRegister(true,false,true,0));
    check(!CanRegister(true,false,false,1));
    for(unsigned flags=0;flags<16;++flags)
        check(CanRemoveCom(flags&1,flags&2,flags&4,flags&8)==(flags==15));
    check(RemovableResidue(0,0,false,false));
    check(RemovableResidue(0,1,true,true));
    check(!RemovableResidue(1,0,false,false));
    check(!RemovableResidue(0,1,false,true));
    check(!RemovableResidue(0,1,true,false));
    check(!RemovableResidue(0,2,true,true));
    check(MayMaintainPersistent(PersistentKind::Partial,false));
    check(MayMaintainPersistent(PersistentKind::Complete,false));
    check(!MayMaintainPersistent(PersistentKind::Partial,true));
    check(!MayMaintainPersistent(PersistentKind::Complete,true));
    check(!MayMaintainPersistent(PersistentKind::ForeignOrUnknown,false));
    // API lag is deliberately not an input to persistent ownership classification.
    check(ClassifyPersistent(true,true,true,31,true)==PersistentKind::Complete);
    // Complete requires native machine-view profile plus all five bidirectional pairs.
    for(unsigned paired=0;paired<31;++paired)
        check(ClassifyPersistent(true,true,true,paired,true)==PersistentKind::Partial);
    check(ClassifyPersistent(true,true,false,31,true)==PersistentKind::Partial);
    check(ClassifyPersistent(true,true,false,0,true)==PersistentKind::Partial);
    check(ClassifyPersistent(true,false,false,0,true)==PersistentKind::Absent);
    check(ClassifyPersistent(false,true,true,31,true)==PersistentKind::ForeignOrUnknown);
    check(ClassifyPersistent(true,true,true,32,true)==PersistentKind::ForeignOrUnknown);
    check(ClassifyPersistent(true,true,false,0,false)==PersistentKind::ForeignOrUnknown);
    for(unsigned mask=0;mask<32;++mask) for(unsigned i=0;i<6;++i)
        check(ShouldRemoveCategory(mask,i)==(i<5 && (mask&(1u<<i))!=0));
    check(FinalApiAbsent(true,0,true,0));
    check(!FinalApiAbsent(false,0,true,0));check(!FinalApiAbsent(true,0,false,0));
    check(!FinalApiAbsent(true,5,true,0));check(!FinalApiAbsent(true,0,true,1));
    check(ValidProfileShape(true,0,4,true,true,true,0,1));
    check(ValidProfileShape(true,0,4,true,true,true,0,0)); // disabled machine profile remains owned
    check(ValidProfileShape(false,0,1,true,false,false,0,0)); // observed current user residue
    check(ValidProfileShape(false,0,1,true,false,false,0,1));
    check(ValidProfileShape(true,0,0,true,false,false,0,0));
    check(!ValidProfileShape(true,1,4,true,true,true,0,1));
    check(!ValidProfileShape(true,0,5,true,true,true,0,1));
    check(!ValidProfileShape(true,0,4,false,true,true,0,1));
    check(!ValidProfileShape(true,0,4,true,false,true,0,1));
    check(!ValidProfileShape(true,0,4,true,true,false,0,1));
    check(!ValidProfileShape(true,0,4,true,true,true,1,1));
    check(!ValidProfileShape(false,0,1,true,false,false,0,2));
    std::cout<<"product registration policy: CLI, absence, removal sequencing, bounded residue passed\n";
}
