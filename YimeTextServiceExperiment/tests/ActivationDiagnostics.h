#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace yime::stage1 {
struct StageResult { std::string phase, stage; std::uint32_t code; };
// Ordered results are evidence of completed checks, never evidence that an
// interrupted call did not mutate state. Keep the first failure independently.
struct Diagnostics {
 std::string phase="preflight";
 std::vector<StageResult> results;
 std::vector<StageResult> cleanupFailures;
 StageResult primaryFailure{};
 bool hasPrimaryFailure=false;
 void record(const std::string& stage,std::uint32_t code) {
  StageResult result{phase,stage,code};results.push_back(result);
  if(code) {
   if(phase=="cleanup")cleanupFailures.push_back(result);
   else if(!hasPrimaryFailure){primaryFailure=result;hasPrimaryFailure=true;}
  }
 }
 void captureSince(std::size_t checkpoint,const std::string& stage,std::uint32_t code) {
  // A check may already have recorded this exception. Deduplicate only within
  // this invocation; two separate failed calls must remain two observations.
  for(auto i=checkpoint;i<results.size();++i)
   if(results[i].phase==phase&&results[i].stage==stage&&results[i].code==code)return;
  record(stage,code);
 }
};
// Production observation and operation boundaries share the same catch path
// with offline fault tests. Direct Failure and ordinary exceptions are covered.
template<class Failure,class Action,class OnFailure>
bool CaptureStage(Diagnostics& diagnostics,const char* unknownStage,std::uint32_t unknownCode,
                  Action action,OnFailure onFailure){
 const auto checkpoint=diagnostics.results.size();
 try{action();return true;}
 catch(const Failure& f){
  const auto code=static_cast<std::uint32_t>(f.code);
  diagnostics.captureSince(checkpoint,f.stage,code);onFailure(f.stage,code);
 }catch(...){
  diagnostics.captureSince(checkpoint,unknownStage,unknownCode);onFailure(unknownStage,unknownCode);
 }
 return false;
}
}
