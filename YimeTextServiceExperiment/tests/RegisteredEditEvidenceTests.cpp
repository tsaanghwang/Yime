#include "RegisteredEditEvidence.h"
#include <iostream>
#include <stdexcept>
using yime::registered_edit::Evidence;
void check(bool ok){if(!ok)throw std::runtime_error("registered-edit ordering contract failed");}
void throughIssue(Evidence& e){
    check(e.registered(37,37));check(e.attached(true));check(e.connected());check(e.issue());
}
int main(){
    try{
        Evidence good;throughIssue(good);
        check(!good.passed()); // accepted/queued is not Applied
        check(good.completed(true));check(!good.passed());
        check(good.readback(true));check(!good.passed());
        good.revoked(true);check(!good.passed());good.absent(true);check(good.passed());
        for(unsigned fault=0;fault<10;++fault){
            Evidence e;
            if(fault==0){check(!e.registered(37,38));}
            else if(fault==1){check(e.registered(37,37));check(!e.attached(false));}
            else {
                throughIssue(e);
                if(fault==2)check(!e.issue()); // second submission is never permitted
                else if(fault==3)check(!e.completed(false)); // unknown after write
                else if(fault==4)check(!e.readback(true)); // readback cannot replace receipt
                else{
                    check(e.completed(true));
                    if(fault==5)check(!e.readback(false));
                    else {check(e.readback(true));if(fault==6)e.fail();}
                }
            }
            e.revoked(fault!=7);e.absent(fault!=8);
            if(fault==9)check(!e.issue()); // cannot reopen after cleanup
            check(!e.passed());
        }
        Evidence wrongOrder;check(!wrongOrder.connected());
        wrongOrder.revoked(true);wrongOrder.absent(true);check(!wrongOrder.passed());
        std::cout<<"PASS: same-process single edit ordering, ten failure paths, no success before revocation and absence\n";
        return 0;
    }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}
}
