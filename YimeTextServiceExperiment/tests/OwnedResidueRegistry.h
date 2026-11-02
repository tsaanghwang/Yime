#pragma once
#include <windows.h>
#include "OwnedResiduePolicy.h"

// Shared Win32 mechanism only. The caller owns path allowlisting and provenance.
// Neither observation nor deletion is an atomic compare-and-delete operation.
namespace yime::stage1::registry {
struct Error { const char* stage; HRESULT code; };
using Report=void(*)(HRESULT,const char*);
inline void Check(LSTATUS code,const char* stage,Report report=nullptr) {
 if(report)report(HRESULT_FROM_WIN32(code),stage);
 if(code!=ERROR_SUCCESS)throw Error{stage,HRESULT_FROM_WIN32(code)};
}
struct Key {
 HKEY value=nullptr;
 ~Key(){if(value)RegCloseKey(value);}
 Key()=default;Key(const Key&)=delete;Key& operator=(const Key&)=delete;
};
inline ResidueObservation ObserveHandle(HKEY key,bool disabled,Report report=nullptr) {
 DWORD children=0,values=0;FILETIME time{};
 Check(RegQueryInfoKeyW(key,nullptr,nullptr,nullptr,&children,nullptr,nullptr,&values,nullptr,nullptr,nullptr,&time),"residue-shape",report);
 auto shape=children==0&&values==0?ResidueShape::Empty:ResidueShape::Unexpected;
 if(disabled&&children==0&&values==1){
  DWORD type=0,value=1,size=sizeof(value);
  auto status=RegQueryValueExW(key,L"Enable",nullptr,&type,reinterpret_cast<BYTE*>(&value),&size);
  if(status!=ERROR_FILE_NOT_FOUND)Check(status,"residue-enable-read",report);
  if(status==ERROR_SUCCESS&&type==REG_DWORD&&size==sizeof(value)&&value==0)shape=ResidueShape::DisabledOnly;
 }
 DWORD afterChildren=0,afterValues=0;FILETIME after{};
 Check(RegQueryInfoKeyW(key,nullptr,nullptr,nullptr,&afterChildren,nullptr,nullptr,&afterValues,nullptr,nullptr,nullptr,&after),"residue-shape-recheck",report);
 const bool changed=children!=afterChildren||values!=afterValues||CompareFileTime(&time,&after)!=0;
 if(report)report(changed?E_FAIL:S_OK,"residue-changed-during-query");
 if(changed)
  throw Error{"residue-changed-during-query",E_FAIL};
 return {shape,(static_cast<std::uint64_t>(time.dwHighDateTime)<<32)|time.dwLowDateTime};
}
inline ResidueObservation Observe(HKEY hive,const wchar_t* path,REGSAM view,bool disabled,Report report=nullptr) {
 Key key;auto result=RegOpenKeyExW(hive,path,0,KEY_READ|view,&key.value);
 if(result==ERROR_FILE_NOT_FOUND||result==ERROR_PATH_NOT_FOUND)return {ResidueShape::Absent,0};
 Check(result,"residue-query",report);return ObserveHandle(key.value,disabled,report);
}
inline void EraseOne(HKEY hive,const wchar_t* path,REGSAM view,Report report=nullptr) {
 Check(RegDeleteKeyExW(hive,path,view,0),"cleanup-residue-delete-one",report);
}
}
