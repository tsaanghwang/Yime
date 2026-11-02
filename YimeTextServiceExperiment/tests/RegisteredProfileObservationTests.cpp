#include "RegisteredProfileObservation.h"
#include <iostream>
#include <new>
#include <stdexcept>
#include <string>
using namespace yime::profile_observation;
void check(bool ok){if(!ok)throw std::runtime_error("assertion");}
int main(){
 const Profile expected{1,0x0804,{1,2,3,{4,5,6,7,8,9,10,11}},{12,13,14,{15,16,17,18,19,20,21,22}}};
 unsigned emitted=0;bool matchedRead=false;const auto matched=Observe(0,expected,[&]{matchedRead=true;return expected;});check(matchedRead&&matched.actual.has_value());
 Require(matched,[&](const auto&,const auto&){++emitted;});check(emitted==0);
 for(unsigned field=0;field<4;++field){
  auto actual=expected;if(field==0)++actual.type;if(field==1)++actual.language;if(field==2)++actual.clsid.data1;if(field==3)++actual.profile.data1;
  bool threw=false;try{Require({0,expected,actual},[&](const auto& o,const auto&){++emitted;check(o.actual.has_value());});}
  catch(const Failure& f){threw=true;check(std::string(f.stage)=="registered profile mismatch"&&std::string(f.kind)=="assertion"&&f.code==0);}check(threw);
 }
 for(std::uint32_t code:{1U,2U,0x80070057U,0x80004005U}){
  bool actualRead=false;const auto observation=Observe(code,expected,[&]() -> Profile {actualRead=true;throw std::runtime_error("invalid actual buffer read");});
  check(!actualRead&&!observation.actual);const auto primary=Decide(observation);check(primary.has_value());
  bool threw=false;try{Require(observation,[&](const auto& o,const auto&){++emitted;check(!o.actual);throw std::runtime_error("diagnostic allocation or sink failure");});}
  catch(const Failure& f){threw=true;check(f.code==code&&std::string(f.kind)=="hresult"&&std::string(f.stage)==primary->stage);}check(threw);
  if(code==1)check(std::string(primary->stage)=="registered active profile unavailable");
  if(code&0x80000000U)check(std::string(primary->stage)=="registered active profile");
 }
 bool mismatch=false;try{Require({0,expected,std::nullopt},[](const auto&,const auto&){throw 7;});}
 catch(const Failure& f){mismatch=true;check(std::string(f.stage)=="registered profile mismatch"&&f.code==0);}check(mismatch);
 struct GateFailure {const char* stage;const char* kind;unsigned long code;};
 const Observation failed{0x80070057U,expected,std::nullopt};const auto reason=*Decide(failed);
 const GateFailure original{reason.stage,reason.kind,reason.code};bool nativeTypePreserved=false;
 try{Reject(failed,reason,original,[](const auto&,const auto&){throw std::bad_alloc();});}
 catch(const GateFailure& result){nativeTypePreserved=true;check(result.stage==original.stage&&result.kind==original.kind&&result.code==original.code);}
 check(nativeTypePreserved);
 check(emitted==8);std::cout<<"profile observation: exact match, four-field mismatch, S_FALSE, positive incomplete, FAILED, throwing sink passed (offline only)\n";
}
