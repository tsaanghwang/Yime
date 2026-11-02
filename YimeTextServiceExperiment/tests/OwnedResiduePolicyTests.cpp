#include "OwnedResiduePolicy.h"
#include "ActivationDiagnostics.h"
#include <iostream>
#include <map>
#include <functional>
#include <set>
using namespace yime::stage1;
void need(bool b){if(!b)throw std::runtime_error("test assertion");}
struct Fake {
 std::map<std::string,ResidueObservation> state;
 std::vector<std::string> deleted;
 int owners=0,reads=0;bool owner=true;
 std::function<void(Fake&,const std::string&)> beforeRead;
 std::function<void(Fake&,const std::string&)> beforeErase;
 std::set<std::string> hasChildren;
 bool deletedUnexpectedValue=false;
 std::string denyDelete,recreate;
 void checkOwner(){++owners;if(!owner)throw std::runtime_error("owner mismatch");}
 ResidueObservation observe(const std::string& id){++reads;if(beforeRead)beforeRead(*this,id);return state.at(id);}
 void eraseOne(const std::string& id){
  // This hook is AFTER the policy's final observe, not inside observe.
  if(beforeErase)beforeErase(*this,id);
  if(id==denyDelete)throw std::runtime_error("access denied");
  if(hasChildren.count(id))throw std::runtime_error("nonrecursive delete refuses children");
  // A nonrecursive key deletion can still delete values added in the gap.
  if(state[id].shape==ResidueShape::Unexpected)deletedUnexpectedValue=true;
  deleted.push_back(id);state[id]={id==recreate?ResidueShape::Empty:ResidueShape::Absent,99};
 }
 void record(const std::string&,const char*){}
};
template<class F>void rejects(F fn){bool thrown=false;try{fn();}catch(const std::exception&){thrown=true;}need(thrown);}
int main(){try{
 const std::vector<ResidueTarget> targets={{"profile",true,true,true},{"container",true,true,false}};
 auto make=[](){Fake f;f.state={{"profile",{ResidueShape::DisabledOnly,1}},{"container",{ResidueShape::Empty,2}}};return f;};
 {auto f=make();CleanNewResidue(4,targets,f);need(f.deleted==std::vector<std::string>({"profile","container"}));}
 for(unsigned version:{0u,2u,3u}){auto f=make();rejects([&]{CleanNewResidue(version,targets,f);});need(f.deleted.empty()&&f.reads==0);}
 {auto f=make();auto t=targets;t[1].absentBefore=false;rejects([&]{CleanNewResidue(4,t,f);});need(f.deleted.empty());}
 {auto f=make();auto t=targets;t[0].attemptRecorded=false;rejects([&]{CleanNewResidue(4,t,f);});need(f.deleted.empty());}
 {auto f=make();f.owner=false;rejects([&]{CleanNewResidue(4,targets,f);});need(f.deleted.empty());}
 {auto f=make();f.state["profile"].shape=ResidueShape::Unexpected;rejects([&]{CleanNewResidue(4,targets,f);});need(f.deleted.empty());}
 {auto f=make();f.state["container"].shape=ResidueShape::DisabledOnly;rejects([&]{CleanNewResidue(4,targets,f);});need(f.deleted.size()==1);}
 {auto f=make();f.beforeRead=[](Fake& b,const std::string& id){if(b.reads==2)++b.state[id].revision;};rejects([&]{CleanNewResidue(4,targets,f);});need(f.deleted.empty());}
 {auto f=make();f.beforeRead=[](Fake& b,const std::string&){if(b.reads==2)throw std::runtime_error("query denied");};rejects([&]{CleanNewResidue(4,targets,f);});need(f.deleted.empty());}
 {auto f=make();f.denyDelete="container";rejects([&]{CleanNewResidue(4,targets,f);});need(f.deleted==std::vector<std::string>({"profile"}));need(f.state["profile"].shape==ResidueShape::Absent);}
 {auto f=make();f.recreate="profile";rejects([&]{CleanNewResidue(4,targets,f);});need(f.deleted.size()==1);}
 // Final-window new subkey: API refusal must stop before the next target.
 {auto f=make();f.beforeErase=[](Fake& b,const std::string& id){b.hasChildren.insert(id);};
  rejects([&]{CleanNewResidue(4,targets,f);});need(f.deleted.empty()&&f.reads==2);}
 // Final-window access failure after a prior deletion is partial, not rollback.
 {auto f=make();f.beforeErase=[](Fake& b,const std::string& id){if(id=="container")b.denyDelete=id;};
  rejects([&]{CleanNewResidue(4,targets,f);});need(f.deleted==std::vector<std::string>({"profile"}));}
 // Limitation characterization: values inserted after the final observation
 // can be deleted without detection. Never label this a race-free guarantee.
 {auto f=make();f.beforeErase=[](Fake& b,const std::string& id){if(id=="profile")b.state[id]={ResidueShape::Unexpected,88};};
  CleanNewResidue(4,targets,f);need(f.deletedUnexpectedValue&&f.deleted.size()==2);}
 {auto f=make();f.state["profile"].shape=ResidueShape::Absent;CleanNewResidue(4,targets,f);need(f.deleted==std::vector<std::string>({"container"}));}
 // Shared 32/64 view aliases are accepted only when the second observation
 // proves absence; an error or a replacement is not treated as absence.
 {auto f=make();f.beforeRead=[](Fake& b,const std::string& id){if(id=="container"&&!b.deleted.empty())b.state[id]={ResidueShape::Absent,0};};CleanNewResidue(4,targets,f);need(f.deleted.size()==1);}
 {Diagnostics d;d.phase="registration";d.record("activation",0x80004005);d.record("later",5);d.phase="cleanup";d.record("disable",0);d.record("absence",0x80004005);need(d.primaryFailure.stage=="activation"&&d.cleanupFailures.size()==1&&d.results.size()==4);}
 std::cout<<"policy/fault and final-window limitation tests passed; in-memory only, no registry or activation calls\n";return 0;
 }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}
