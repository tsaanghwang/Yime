// Pure report regression: does not instantiate TSF or read/write the registry.
#include "ActivationFailureTrace.h"
#include <sstream>
#include <iostream>
#include <stdexcept>
using nlohmann::json;
using namespace yime::stage1;
namespace {
void check(bool value,const char* reason){if(!value)throw std::runtime_error(reason);}
struct FailedBuffer : std::streambuf {
    int_type overflow(int_type) override {throw std::runtime_error("diagnostic sink unavailable");}
};
}
int main(){
    try{
        json report={{"stage","activate-own-profile-forprocess"},{"code",0x80070057u},
            {"privatePath","must-not-appear"},{"cleanupVerified",false}};
        std::stringstream trace;
        WriteFailureTrace(report,FailurePhase::Operation,trace);
        // Reproduce the prior failure mask: cleanup replaces the top-level stage.
        report["stage"]="existing-tip-identity";report["code"]=0x80004005u;
        WriteFailureTrace(report,FailurePhase::Cleanup,trace);
        std::string first,second,extra;
        check(bool(std::getline(trace,first)) && bool(std::getline(trace,second)) && !std::getline(trace,extra),"exactly two phase records");
        auto operation=json::parse(first),cleanup=json::parse(second);
        check(operation.size()==4 && cleanup.size()==4,"only bounded diagnostic fields");
        check(operation.at("schema")=="18u-activation-failure-v1" && cleanup.at("schema")==operation.at("schema"),"diagnostic schema");
        check(operation.at("phase")=="operation" && operation.at("stage")=="activate-own-profile-forprocess" && operation.at("code")==0x80070057u,"original error lost");
        check(cleanup.at("phase")=="cleanup" && cleanup.at("stage")=="existing-tip-identity" && cleanup.at("code")==0x80004005u,"cleanup error lost");
        check(trace.str().find("must-not-appear")==std::string::npos,"private report data leaked");
        std::stringstream success;json passed={{"stage","completed"},{"code",0}};
        WriteFailureTrace(passed,FailurePhase::Operation,success);
        WriteFailureTrace(passed,FailurePhase::Cleanup,success);
        check(success.str().empty(),"success marker stream changed");
        std::stringstream cleanupOnly;
        WriteFailureTrace(passed,FailurePhase::Operation,cleanupOnly);
        WriteFailureTrace(report,FailurePhase::Cleanup,cleanupOnly);
        check(json::parse(cleanupOnly.str()).at("phase")=="cleanup","cleanup-only failure missing");
        FailedBuffer buffer;std::ostream unavailable(&buffer);
        unavailable.exceptions(std::ios::badbit|std::ios::failbit);
        WriteFailureTrace(report,FailurePhase::Operation,unavailable);
        check(unavailable.bad(),"diagnostic output failure was not exercised");
        std::cout<<"PASS: original failure retained, cleanup-only failure, privacy, success silent, broken logging cannot stop cleanup\n";
        return 0;
    }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}
}
