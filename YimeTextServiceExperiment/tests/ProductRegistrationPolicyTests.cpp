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
    std::cout<<"product registration policy: CLI, absence, removal sequencing, bounded residue passed\n";
}
