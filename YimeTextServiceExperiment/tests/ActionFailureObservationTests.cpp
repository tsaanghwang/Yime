#include "ActionFailureObservation.h"
#include <iostream>
#include <stdexcept>
#include <string>
using namespace yimeactionfailure;
void check(bool value){if(!value)throw std::runtime_error("action failure observation test");}
std::string render(const Evidence& evidence){std::string out;Emit(evidence,[&](const std::string& value){out=value;});return out;}
int main(){
 Evidence e;e.hresult=0x80004004u;e.response=Response::Object;e.ok={Type::Boolean,false,{}};
 e.outcome={Type::String,false,"failed"};e.localEditOutcome={Type::String,false,"unknown"};e.retryAllowed={Type::Boolean,false,{}};
 check(std::string(Outcome("not-attempted"))=="not-attempted");check(std::string(Outcome("not-applied"))=="not-applied");
 const auto normal=render(e);check(normal.find("\"hresult\":2147500036")!=std::string::npos);
 check(normal.find("\"abortSource\":\"route\"")!=std::string::npos);check(normal.find("\"value\":\"failed\"")!=std::string::npos);
 e.wmQuit=true;check(render(e).find("\"abortSource\":\"wm-quit\"")!=std::string::npos);
 const std::string privateText="PRIVATE-CANDIDATES-TEXT\"\\\nTOKEN";
 e.wmQuit=false;e.outcome={Type::String,false,privateText};e.localEditOutcome={Type::Object,false,privateText};
 e.ok={Type::String,false,privateText};e.retryAllowed={Type::Array,false,privateText};
 const auto filtered=render(e);check(filtered.find("PRIVATE")==std::string::npos);check(filtered.find("unrecognized")!=std::string::npos);
 check(filtered.find("\"type\":\"object\",\"value\":null")!=std::string::npos);
 e.response=Response::Malformed;e.ok={};e.outcome={};e.localEditOutcome={};e.retryAllowed={};
 check(render(e).find("\"response\":\"malformed\"")!=std::string::npos);
 e.response=Response::NonObject;check(render(e).find("non-object")!=std::string::npos);
 e.response=Response::Missing;check(render(e).find("\"response\":\"missing\"")!=std::string::npos);
 // A production serializer/sink exception must leave the original gate failure intact.
 struct FirstFailure{uint32_t hr;const char* stage;};bool caught=false;
 try {Emit(e,[](const std::string&){throw std::runtime_error("sink failed");});throw FirstFailure{e.hresult,"engine input"};}
 catch(const FirstFailure& first){caught=true;check(first.hr==0x80004004u);check(std::string(first.stage)=="engine input");}
 check(caught);
 for(Type type:{Type::Missing,Type::Null,Type::Boolean,Type::String,Type::Number,Type::Array,Type::Object}){
  e.outcome={type,true,privateText};check(render(e).find("PRIVATE")==std::string::npos);
 }
 std::cout<<"ActionFailureObservation: safe enums/types, malformed/missing, WM_QUIT and sink-failure checks passed\n";
}
