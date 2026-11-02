#include "ActivationDiagnostics.h"
#include <stdexcept>
#include <iostream>
using namespace yime::stage1;
namespace {
struct Failure {const char* stage;std::uint32_t code;};
void need(bool ok){if(!ok)throw std::runtime_error("diagnostics assertion");}
constexpr std::uint32_t error=0x80004005u;
void check(Diagnostics& d,const char* stage,std::uint32_t code){d.record(stage,code);if(code)throw Failure{stage,code};}
}
int main(){try{
 // Use the very same boundary template as inspectLocal/wmain; callbacks model
 // summary overwrites without changing first-failure evidence.
 for(bool ordinary:{false,true}){
  Diagnostics d;std::string summary;
  auto report=[&](const char* s,std::uint32_t){summary=s;};
  need(!CaptureStage<Failure>(d,"preflight-query-exception",error,[&]{
   if(ordinary)throw std::runtime_error("query failed");
   throw Failure{"owner-token-bound",5};
  },report));
  const auto first=d.primaryFailure;
  need(d.hasPrimaryFailure&&first.phase=="preflight");
  need(first.stage==(ordinary?"preflight-query-exception":"owner-token-bound"));
  need(first.code==(ordinary?error:5));
  CaptureStage<Failure>(d,"unexpected",error,[&]{check(d,"registration-preconditions-not-proven",error);},report);
  d.phase="cleanup";
  CaptureStage<Failure>(d,"cleanup-exception",error,[&]{check(d,"existing-tip-identity",error);},report);
  need(d.primaryFailure.stage==first.stage&&d.primaryFailure.code==first.code);
  need(d.results.size()==3&&d.cleanupFailures.size()==1&&summary=="existing-tip-identity");
 }
 {Diagnostics d;auto ignore=[](const char*,std::uint32_t){};
  for(int i=0;i<2;++i)CaptureStage<Failure>(d,"unknown",error,[&]{check(d,"same-call",5);},ignore);
  need(d.results.size()==2); // no double count at catch, no cross-call collapse
 }
 {Diagnostics d;auto ignore=[](const char*,std::uint32_t){};
  CaptureStage<Failure>(d,"unknown",error,[&]{
   CaptureStage<Failure>(d,"unknown",error,[]{throw Failure{"nested",7};},[](const char*,std::uint32_t){throw Failure{"nested",7};});
  },ignore);need(d.results.size()==1&&d.primaryFailure.code==7);
 }
 {Diagnostics d;bool called=false;need(CaptureStage<Failure>(d,"unknown",error,[]{},[&](const char*,std::uint32_t){called=true;}));need(!called&&!d.hasPrimaryFailure&&d.results.empty());}
 {Diagnostics d;d.phase="cleanup";
  CaptureStage<Failure>(d,"cleanup-exception",error,[]{throw std::runtime_error("cleanup failed");},[](const char*,std::uint32_t){});
  need(!d.hasPrimaryFailure&&d.cleanupFailures.size()==1&&d.cleanupFailures[0].stage=="cleanup-exception"&&d.cleanupFailures[0].code==error);
 }
 std::cout<<"diagnostic boundary fault tests passed; no OS calls\n";return 0;
 }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}
