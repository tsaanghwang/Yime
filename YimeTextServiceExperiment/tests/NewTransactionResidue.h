#pragma once
#include "OwnedResiduePolicy.h"
// Included inside RegistrationProbe's namespace after the local helpers.
struct LocalResiduePath {
 HKEY hive; REGSAM view; std::wstring path; const char* attempt; bool disabled;
 std::string id()const{return std::string(hive==HKEY_LOCAL_MACHINE?"HKLM/":"HKCU/")+(view==KEY_WOW64_64KEY?"64/":"32/")+localUtf8(path);}
};
std::vector<LocalResiduePath> localResiduePaths(){
 std::vector<LocalResiduePath> out;
 const auto root=L"SOFTWARE\\Microsoft\\CTF\\TIP\\"+guid(CLSID_YimeTextServiceExperiment);
 for(HKEY hive:{HKEY_LOCAL_MACHINE,HKEY_CURRENT_USER})for(REGSAM view:{KEY_WOW64_64KEY,KEY_WOW64_32KEY}){
  const auto add=[&](const std::wstring& suffix,const char* attempt,bool disabled=false){out.push_back({hive,view,root+suffix,attempt,disabled});};
  add(L"\\LanguageProfile\\0x00000804\\"+guid(GUID_YimeTextServiceExperimentProfile),"profileAttempted",hive==HKEY_CURRENT_USER);
  add(L"\\LanguageProfile\\0x00000804","profileAttempted");add(L"\\LanguageProfile","profileAttempted");
  add(L"\\Category\\Category\\"+guid(GUID_TFCAT_TIP_KEYBOARD),"categoryAttempted");add(L"\\Category\\Category","categoryAttempted");
  add(L"\\Category\\Item\\"+guid(CLSID_YimeTextServiceExperiment),"categoryAttempted");add(L"\\Category\\Item","categoryAttempted");
  add(L"\\Category","categoryAttempted");add(L"","profileAttempted");
 }
 return out;
}
yime::stage1::ResidueObservation observeLocalResidue(const LocalResiduePath& target){
 using Shape=yime::stage1::ResidueShape;
 Key key;auto hr=RegOpenKeyExW(target.hive,target.path.c_str(),0,KEY_READ|target.view,&key.value);
 if(hr==ERROR_FILE_NOT_FOUND||hr==ERROR_PATH_NOT_FOUND)return {Shape::Absent,0};
 check(HRESULT_FROM_WIN32(hr),"residue-query");
 DWORD children=0,values=0;FILETIME time{};
 check(HRESULT_FROM_WIN32(RegQueryInfoKeyW(key.value,nullptr,nullptr,nullptr,&children,nullptr,nullptr,&values,nullptr,nullptr,nullptr,&time)),"residue-shape");
 auto shape=children==0&&values==0?Shape::Empty:Shape::Unexpected;
 if(target.disabled&&children==0&&values==1){
  DWORD type=0,value=1,size=sizeof(value);
  auto status=RegQueryValueExW(key.value,L"Enable",nullptr,&type,reinterpret_cast<BYTE*>(&value),&size);
  if(status!=ERROR_FILE_NOT_FOUND)check(HRESULT_FROM_WIN32(status),"residue-enable-read");
  if(status==ERROR_SUCCESS&&type==REG_DWORD&&size==sizeof(value)&&value==0)shape=Shape::DisabledOnly;
 }
 DWORD afterChildren=0,afterValues=0;FILETIME after{};
 check(HRESULT_FROM_WIN32(RegQueryInfoKeyW(key.value,nullptr,nullptr,nullptr,&afterChildren,nullptr,nullptr,&afterValues,nullptr,nullptr,nullptr,&after)),"residue-shape-recheck");
 require(children==afterChildren&&values==afterValues&&CompareFileTime(&time,&after)==0,"residue-changed-during-query");
 return {shape,(static_cast<std::uint64_t>(time.dwHighDateTime)<<32)|time.dwLowDateTime};
}
json captureLocalAbsence(){
 json rows=json::array();
 for(const auto& target:localResiduePaths()){
  require(observeLocalResidue(target).shape==yime::stage1::ResidueShape::Absent,"new-item-not-absent");
  rows.push_back({{"id",target.id()},{"absentBefore",true}});
 }
 return rows;
}
void validateLocalAbsence(const json& rows){
 const auto paths=localResiduePaths();require(rows.is_array()&&rows.size()==paths.size(),"item-provenance-count");
 for(size_t i=0;i<paths.size();++i)require(rows[i].is_object()&&rows[i].size()==2&&rows[i].at("id")==paths[i].id()&&rows[i].at("absentBefore")==true,"item-provenance-binding");
}
