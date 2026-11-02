// Query-only inventory for one disposable cloud CI invocation. No thread-manager
// activation, keyboard-layout loading/switching, registration, or profile enable.
#include <windows.h>
#include <msctf.h>
#include <wrl/client.h>
#include <array>
#include <cstdint>
#include <iostream>
#include <set>
#include <string>
#include <nlohmann/json.hpp>
using Microsoft::WRL::ComPtr;
using nlohmann::json;
namespace {
struct Failure { const char* stage; HRESULT code; };
void check(HRESULT code,const char* stage){if(code!=S_OK)throw Failure{stage,code};}
void require(bool condition,const char* stage){if(!condition)throw Failure{stage,E_FAIL};}
std::uint64_t handleValue(HKL value){return static_cast<std::uint64_t>(reinterpret_cast<ULONG_PTR>(value));}
std::string guidText(REFGUID value){
 wchar_t buffer[39]{};require(StringFromGUID2(value,buffer,39)==39,"guid-format");
 std::string text;for(unsigned i=0;i<38;++i){require(buffer[i]<=127,"guid-format");text.push_back(static_cast<char>(buffer[i]));}return text;
}
void inventory(json& result){
 HKL current=GetKeyboardLayout(0);require(current!=nullptr,"current-hkl-query");result["currentHkl"]=handleValue(current);
 // One bounded retrieval, not a count/retry loop. A full buffer is conservatively
 // indeterminate because the API may have truncated the current loaded set.
 std::array<HKL,257> loaded{};SetLastError(ERROR_SUCCESS);
 const int count=GetKeyboardLayoutList(static_cast<int>(loaded.size()),loaded.data());
 if(count==0){DWORD error=GetLastError();throw Failure{"loaded-hkl-query",error?HRESULT_FROM_WIN32(error):E_FAIL};}
 require(count>0 && count<static_cast<int>(loaded.size()),"loaded-hkl-bound");
 std::set<LANGID> languages;
 languages.insert(LOWORD(reinterpret_cast<ULONG_PTR>(current)));
 for(int index=0;index<count;++index){
  require(loaded[index]!=nullptr,"loaded-hkl-null");
  const LANGID hint=LOWORD(reinterpret_cast<ULONG_PTR>(loaded[index]));languages.insert(hint);
  result["loadedLayouts"].push_back({{"hkl",handleValue(loaded[index])},{"hklLowWordLanguageHint",hint},{"isCurrentHkl",loaded[index]==current},
   {"association","unknown"},{"exactKeyboardProfileIndices",json::array()},{"substituteReferenceProfileIndices",json::array()}});
 }
 ComPtr<ITfInputProcessorProfileMgr> profiles;
 check(CoCreateInstance(CLSID_TF_InputProcessorProfiles,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&profiles)),"profile-query-object");
 ComPtr<ITfInputProcessorProfiles> languageProfiles;check(profiles.As(&languageProfiles),"language-query-interface");
 LANGID tsfLanguage=0;check(languageProfiles->GetCurrentLanguage(&tsfLanguage),"current-tsf-language-query");
 result["currentTsfLanguage"]=tsfLanguage;languages.insert(tsfLanguage);
 require(languages.size()<=64,"query-language-bound");
 // Language IDs only choose enumeration buckets. They do NOT establish an
 // HKL/profile equivalence. These queries are a snapshot, not an atomic view.
 for(LANGID language:languages){
  ComPtr<IEnumTfInputProcessorProfiles> values;check(profiles->EnumProfiles(language,&values),"enum-profiles-query");
  require(values.Get()!=nullptr,"enum-profiles-null");
  for(unsigned n=0;;++n){
   require(n<=1024,"profile-enumeration-bound");TF_INPUTPROCESSORPROFILE profile{};ULONG fetched=0;
   const HRESULT hr=values->Next(1,&profile,&fetched);
   if(hr==S_FALSE && fetched==0)break;
   check(hr,"profile-next-query");require(fetched==1,"profile-next-count");
   require(result["profiles"].size()<1024,"total-profile-bound");
   const auto index=result["profiles"].size();
   result["profiles"].push_back({{"queryLanguage",language},{"language",profile.langid},{"type",profile.dwProfileType},
    {"clsid",guidText(profile.clsid)},{"profileId",guidText(profile.guidProfile)},{"categoryId",guidText(profile.catid)},
    {"hkl",handleValue(profile.hkl)},{"hklSubstitute",handleValue(profile.hklSubstitute)},
    {"flags",profile.dwFlags},{"enabled",(profile.dwFlags&TF_IPP_FLAG_ENABLED)!=0},{"active",(profile.dwFlags&TF_IPP_FLAG_ACTIVE)!=0}});
   for(auto& layout:result["loadedLayouts"]){
    const auto hkl=layout["hkl"].get<std::uint64_t>();
    if(profile.dwProfileType==TF_PROFILETYPE_KEYBOARDLAYOUT && profile.hkl && handleValue(profile.hkl)==hkl)
     layout["exactKeyboardProfileIndices"].push_back(index);
    if(profile.dwProfileType==TF_PROFILETYPE_INPUTPROCESSOR && profile.hklSubstitute && handleValue(profile.hklSubstitute)==hkl)
     layout["substituteReferenceProfileIndices"].push_back(index);
   }
  }
  result["queriedLanguages"].push_back(language);
 }
 for(auto& layout:result["loadedLayouts"]){
  if(!layout["exactKeyboardProfileIndices"].empty())layout["association"]="exact-keyboard-profile-hkl";
  else if(!layout["substituteReferenceProfileIndices"].empty())layout["association"]="substitute-reference-only";
 }
}
}
int wmain(int argc,wchar_t**){
 json result={{"schema","input-language-inventory-v1"},{"scope","loaded-input-language-inventory-readonly"},
  {"status","failed"},{"stage","arguments"},{"code",static_cast<unsigned long>(E_INVALIDARG)},
  {"currentHkl",nullptr},{"currentTsfLanguage",nullptr},{"loadedLayouts",json::array()},{"profiles",json::array()},{"queriedLanguages",json::array()}};
 if(argc!=1){std::cout<<result.dump()<<std::endl;return 1;}
 const HRESULT initialized=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
 if(FAILED(initialized)){result["stage"]="com-initialize";result["code"]=static_cast<unsigned long>(initialized);std::cout<<result.dump()<<std::endl;return 1;}
 int exit=1;
 try{inventory(result);result["status"]="complete";result["stage"]="completed";result["code"]=0;exit=0;}
 catch(const Failure& failure){result["stage"]=failure.stage;result["code"]=static_cast<unsigned long>(failure.code);}
 catch(...){result["stage"]="unclassified-query-exception";result["code"]=static_cast<unsigned long>(E_FAIL);}
 CoUninitialize();std::cout<<result.dump()<<std::endl;return exit;
}
