// Explicit opt-in only. Never run as part of a normal build or registration test.
#include <windows.h>
#include <objbase.h>
#include <iostream>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>
#include "OwnedResidueRegistry.h"
namespace {
namespace reg=yime::stage1::registry;
using yime::stage1::ResidueShape;
std::string Quote(const std::string& value){std::string out="\"";for(char c:value){if(c=='\\'||c=='\"')out+='\\';out+=c;}return out+'\"';}
std::string Narrow(const std::wstring& value){return std::string(value.begin(),value.end());}
void Require(bool value){if(!value)throw std::runtime_error("test-assertion");}
struct Fixture {
 reg::Key software;
 std::wstring root;
 struct Item { std::wstring path;std::map<std::wstring,DWORD> values; };
 std::vector<Item> items;
 bool creationUnknown=false,writesAttempted=false;
 const char* cleanupStage=nullptr;HRESULT cleanupCode=S_OK;
 void start(){
  GUID id{};Require(SUCCEEDED(CoCreateGuid(&id)));wchar_t text[40]{};
  Require(StringFromGUID2(id,text,40)>0);
  root=L"YimeOwnedResidueAdapterTest-"+std::wstring(text);
  reg::Check(RegOpenKeyExW(HKEY_CURRENT_USER,L"Software",0,KEY_READ|KEY_CREATE_SUB_KEY|KEY_WOW64_64KEY,&software.value),"test-existing-software");
  std::cout<<"{\"schema\":\"owned-residue-registry-test-v1\",\"event\":\"before-first-write\",\"root\":"<<Quote("HKCU\\Software\\"+Narrow(root))<<"}\n"<<std::flush;
  Require(static_cast<bool>(std::cout)); // No write if the root evidence could not be flushed.
  create(L"");
 }
 std::wstring path(const std::wstring& relative)const{return root+(relative.empty()?L"":L"\\"+relative);}
 void create(const std::wstring& relative){
  const auto target=path(relative);reg::Key key;DWORD disposition=0;
  creationUnknown=true;writesAttempted=true;
  reg::Check(RegCreateKeyExW(software.value,target.c_str(),0,nullptr,REG_OPTION_NON_VOLATILE,KEY_READ|KEY_SET_VALUE|KEY_WOW64_64KEY,nullptr,&key.value,&disposition),"test-create");
  // A collision is never adopted or removed. Record only confirmed new items.
  if(disposition!=REG_CREATED_NEW_KEY){creationUnknown=false;throw std::runtime_error("preexisting-test-item");}
  items.push_back({target,{ }});creationUnknown=false;
 }
 void value(const std::wstring& relative,const wchar_t* name,DWORD data){
  reg::Key key;const auto target=path(relative);
  reg::Check(RegOpenKeyExW(software.value,target.c_str(),0,KEY_SET_VALUE|KEY_WOW64_64KEY,&key.value),"test-open-value");
  reg::Check(RegSetValueExW(key.value,name,0,REG_DWORD,reinterpret_cast<const BYTE*>(&data),sizeof(data)),"test-value");
  for(auto& item:items)if(item.path==target){item.values[name]=data;return;}
  throw std::runtime_error("unowned-test-item");
 }
 yime::stage1::ResidueObservation observe(const std::wstring& relative,REGSAM view=KEY_WOW64_64KEY){return reg::Observe(software.value,path(relative).c_str(),view,true);}
 void erase(const std::wstring& relative){reg::EraseOne(software.value,path(relative).c_str(),KEY_WOW64_64KEY);}
 bool cleanup() noexcept {
  if(creationUnknown){cleanupStage="creation-ownership-unknown";cleanupCode=E_FAIL;return false;}
  for(auto it=items.rbegin();it!=items.rend();++it){
   try {
    reg::Key key;auto status=RegOpenKeyExW(software.value,it->path.c_str(),0,KEY_READ|KEY_WOW64_64KEY,&key.value);
    if(status==ERROR_FILE_NOT_FOUND||status==ERROR_PATH_NOT_FOUND)continue;
    reg::Check(status,"test-cleanup-open");DWORD children=0,values=0;
    reg::Check(RegQueryInfoKeyW(key.value,nullptr,nullptr,nullptr,&children,nullptr,nullptr,&values,nullptr,nullptr,nullptr,nullptr),"test-cleanup-shape");
    Require(children==0&&values==it->values.size());
    for(const auto& value:it->values){DWORD data=0,type=0,size=sizeof(data);
     reg::Check(RegQueryValueExW(key.value,value.first.c_str(),nullptr,&type,reinterpret_cast<BYTE*>(&data),&size),"test-cleanup-value");
     Require(type==REG_DWORD&&size==sizeof(data)&&data==value.second);
    }
    RegCloseKey(key.value);key.value=nullptr;
    reg::EraseOne(software.value,it->path.c_str(),KEY_WOW64_64KEY);
    Require(reg::Observe(software.value,it->path.c_str(),KEY_WOW64_64KEY,false).shape==ResidueShape::Absent);
   }catch(const reg::Error& e){cleanupStage=e.stage;cleanupCode=e.code;return false;}
    catch(...){cleanupStage="cleanup-shape-or-exception";cleanupCode=E_FAIL;return false;} // Stop at first unknown; retain all remaining items.
  }
  return true;
 }
};
struct Backend {
 Fixture& fixture;bool injectChild=false;int deleted=0;
 void checkOwner(){} // Test-owned paths only; not production ledger authentication.
 yime::stage1::ResidueObservation observe(const std::string& id){return fixture.observe(std::wstring(id.begin(),id.end()));}
 void eraseOne(const std::string& id){
  if(injectChild&&id=="second")fixture.create(L"second\\racing-child");
  fixture.erase(std::wstring(id.begin(),id.end()));++deleted;
 }
 void record(const std::string&,const char*){}
};
void Run(Fixture& f,bool& aliasObserved,bool& aliasKnown,std::vector<std::string>& completed){
 using namespace yime::stage1;
 Require(f.observe(L"missing").shape==ResidueShape::Absent);completed.push_back("absent");
 f.create(L"empty");Require(f.observe(L"empty").shape==ResidueShape::Empty);completed.push_back("empty");
 f.create(L"disabled");f.value(L"disabled",L"Enable",0);Require(f.observe(L"disabled").shape==ResidueShape::DisabledOnly);completed.push_back("enable-dword-zero");
 f.create(L"extra");f.value(L"extra",L"Enable",0);f.value(L"extra",L"Extra",1);Require(f.observe(L"extra").shape==ResidueShape::Unexpected);completed.push_back("extra-value");
 f.create(L"parent");f.create(L"parent\\child");Require(f.observe(L"parent").shape==ResidueShape::Unexpected);completed.push_back("subkey");
 // Query permissions, not parent-handle deletion permissions: RegDeleteKeyEx
 // checks target access independently and a read-only parent is not a denial.
 reg::Key noQuery;reg::Check(RegOpenKeyExW(f.software.value,f.path(L"empty").c_str(),0,KEY_SET_VALUE|KEY_WOW64_64KEY,&noQuery.value),"test-no-query-open");
 bool denied=false;try{reg::ObserveHandle(noQuery.value,true);}catch(const reg::Error& error){denied=error.code==HRESULT_FROM_WIN32(ERROR_ACCESS_DENIED);}Require(denied);completed.push_back("query-access-denied");
 RegCloseKey(noQuery.value);noQuery.value=nullptr;
 const auto view32=f.observe(L"disabled",KEY_WOW64_32KEY);
 Require(view32.shape==ResidueShape::Absent||view32.shape==ResidueShape::DisabledOnly);
 aliasObserved=view32.shape==ResidueShape::DisabledOnly;
 if(aliasObserved)Require(view32==f.observe(L"disabled",KEY_WOW64_64KEY));
 aliasKnown=true;completed.push_back("actual-view-observation");
 Backend normal{f};CleanNewResidue(4,{{"empty",true,true,false},{"disabled",true,true,true}},normal);Require(normal.deleted==2);completed.push_back("empty-disabled-delete");
 Backend reject{f};bool rejected=false;
 try{CleanNewResidue(4,{{"extra",true,true,true}},reject);}catch(const std::runtime_error&){rejected=true;}Require(rejected&&reject.deleted==0&&f.observe(L"extra").shape==ResidueShape::Unexpected);completed.push_back("unexpected-shape-rejected");
 f.create(L"first");f.create(L"second");f.create(L"third");Backend partial{f,true};bool failed=false;
 try{CleanNewResidue(4,{{"first",true,true,false},{"second",true,true,false},{"third",true,true,false}},partial);}catch(const reg::Error&){failed=true;}
 Require(failed&&partial.deleted==1&&f.observe(L"first").shape==ResidueShape::Absent&&f.observe(L"second").shape==ResidueShape::Unexpected&&f.observe(L"third").shape==ResidueShape::Empty);completed.push_back("partial-delete-failure-stops");
}
}
int wmain(int argc,wchar_t** argv){
 if(argc!=2||std::wstring(argv[1])!=L"--confirm-disposable-hkcu-adapter-test"){
  std::cout<<"{\"schema\":\"owned-residue-registry-test-v1\",\"event\":\"blocked-before-write\",\"status\":\"blocked\",\"writesAttempted\":false,\"reason\":\"explicit-test-confirmation-required\"}\n";return 3;
 }
 // This target is native x64 only; no registration or TSF APIs are present.
 USHORT process=0,native=0;
 if(!IsWow64Process2(GetCurrentProcess(),&process,&native)||process!=0||native!=IMAGE_FILE_MACHINE_AMD64){
  std::cout<<"{\"schema\":\"owned-residue-registry-test-v1\",\"event\":\"blocked-before-write\",\"status\":\"blocked\",\"writesAttempted\":false,\"reason\":\"native-amd64-required\"}\n";return 3;
 }
 Fixture fixture;bool passed=false,alias=false,aliasKnown=false;std::vector<std::string> completed;const char* stage="complete";HRESULT code=S_OK;
 try{fixture.start();Run(fixture,alias,aliasKnown,completed);passed=true;}
 catch(const reg::Error& e){stage=e.stage;code=e.code;}
 catch(...){stage="test-assertion-or-exception";code=E_FAIL;}
 const bool cleaned=fixture.cleanup();
 std::cout<<"{\"schema\":\"owned-residue-registry-test-v1\",\"event\":\"result\",\"root\":"
 <<(fixture.root.empty()?"null":Quote("HKCU\\Software\\"+Narrow(fixture.root)))
 <<",\"status\":\""<<(passed&&cleaned?"passed":"failed")<<"\",\"writesAttempted\":"<<(fixture.writesAttempted?"true":"false")
 <<",\"creationUnknown\":"<<(fixture.creationUnknown?"true":"false")<<",\"cleanupVerified\":"<<(cleaned?"true":"false")
 <<",\"view32Aliases64Observed\":"<<(aliasKnown?(alias?"true":"false"):"null")<<",\"atomicCompareDelete\":false,\"firstFailure\":";
 if(passed)std::cout<<"null";else std::cout<<"{\"stage\":"<<Quote(stage)<<",\"code\":"<<static_cast<unsigned long>(code)<<"}";
 std::cout<<",\"cleanupFailure\":";
 if(cleaned)std::cout<<"null";else std::cout<<"{\"stage\":"<<Quote(fixture.cleanupStage)<<",\"code\":"<<static_cast<unsigned long>(fixture.cleanupCode)<<"}";
 std::cout<<",\"completedCases\":[";for(size_t i=0;i<completed.size();++i){if(i)std::cout<<',';std::cout<<Quote(completed[i]);}std::cout<<"]}\n";
 return passed&&cleaned&&std::cout?0:1;
}
