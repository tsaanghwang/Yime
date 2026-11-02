// Shared registration transaction: original disposable CI entry or explicitly
// compiled MyComputer stage-1 entry. Neither is a general-purpose installer.
#include <windows.h>
#include <msctf.h>
#include <wrl/client.h>
#include <filesystem>
#include <iostream>
#include <string>
#include <vector>
#include <algorithm>
#include <cwctype>
#include <cstring>
#include <fstream>
#ifdef YIME_ACTIVATED_LOOP
#include <functional>
#include "ActivatedLoop.h"
#endif
#include <nlohmann/json.hpp>
#ifdef YIME_MYCOMPUTER_ACTIVATION_STAGE1
#include <bcrypt.h>
#include <wincrypt.h>
#include <sddl.h>
#include <iterator>
#include "MyComputerActivationPolicy.h"
#endif
#include "YimeTextServiceIds.h"
#include "ProductIdentity.h"
using Microsoft::WRL::ComPtr;
using nlohmann::json;
namespace {
constexpr LANGID language = 0x0804;
struct Failure { const char* stage; HRESULT code; };
void check(HRESULT result,const char* stage) { if(result!=S_OK) throw Failure{stage,result}; }
void require(bool value,const char* stage) { if(!value) throw Failure{stage,E_FAIL}; }
std::wstring guid(REFGUID id) { wchar_t text[39]{}; require(StringFromGUID2(id,text,39)==39,"guid");return text; }
struct Key { HKEY value=nullptr; ~Key(){if(value)RegCloseKey(value);} };
bool exists(HKEY hive,const std::wstring& path,REGSAM view) {
 Key key;const auto result=RegOpenKeyExW(hive,path.c_str(),0,KEY_READ|view,&key.value);
 if(result==ERROR_FILE_NOT_FOUND||result==ERROR_PATH_NOT_FOUND)return false;
 check(HRESULT_FROM_WIN32(result),"registry-query");return true;
}
// Read both identities anywhere in the persisted TIP tree, not only enabled profiles.
void scan(HKEY hive,const std::wstring& path,REGSAM view,unsigned depth,unsigned& budget) {
 require(depth<=12 && budget++<20000,"registry-scan-bound");
 Key key;auto result=RegOpenKeyExW(hive,path.c_str(),0,KEY_READ|view,&key.value);
 if(result==ERROR_FILE_NOT_FOUND||result==ERROR_PATH_NOT_FOUND)return;
 check(HRESULT_FROM_WIN32(result),"registry-scan-open");
 // CTF SortOrder can reference a profile in value data, not a key name.
 for(DWORD index=0;;++index) {
  wchar_t name[16384]{};DWORD nameCount=16384,type=0,bytes=0;
  result=RegEnumValueW(key.value,index,name,&nameCount,nullptr,&type,nullptr,&bytes);
  if(result==ERROR_NO_MORE_ITEMS)break;
  check(HRESULT_FROM_WIN32(result),"registry-value-enumerate");require(bytes<=1048576,"registry-value-bound");
  std::vector<BYTE> data(bytes);nameCount=16384;
  check(HRESULT_FROM_WIN32(RegEnumValueW(key.value,index,name,&nameCount,nullptr,&type,data.data(),&bytes)),"registry-value-read");
  for(auto id:{CLSID_YimeTextServiceExperiment,GUID_YimeTextServiceExperimentProfile}) {
   auto identity=guid(id);std::transform(identity.begin(),identity.end(),identity.begin(),towlower);
   std::wstring valueName(name);std::transform(valueName.begin(),valueName.end(),valueName.begin(),towlower);
   require(valueName.find(identity)==std::wstring::npos,"existing-identity-value-name");
   if(type==REG_SZ||type==REG_EXPAND_SZ||type==REG_MULTI_SZ) {
    require(bytes%sizeof(wchar_t)==0,"registry-string-shape");std::wstring text(bytes/sizeof(wchar_t),L'\0');
    if(bytes)std::memcpy(text.data(),data.data(),bytes);std::transform(text.begin(),text.end(),text.begin(),towlower);
    require(text.find(identity)==std::wstring::npos,"existing-identity-value-data");
   }
   if(bytes>=sizeof(GUID))for(size_t at=0;at+sizeof(GUID)<=bytes;++at)
    require(std::memcmp(data.data()+at,&id,sizeof(GUID))!=0,"existing-identity-binary-data");
  }
 }
 for(DWORD index=0;;++index) {
  wchar_t name[256]{};DWORD count=256;
  result=RegEnumKeyExW(key.value,index,name,&count,nullptr,nullptr,nullptr,nullptr);
  if(result==ERROR_NO_MORE_ITEMS)break;
  check(HRESULT_FROM_WIN32(result),"registry-scan-enumerate");
  require(_wcsicmp(name,guid(CLSID_YimeTextServiceExperiment).c_str())!=0 &&
          _wcsicmp(name,guid(GUID_YimeTextServiceExperimentProfile).c_str())!=0,"existing-tip-identity");
  scan(hive,path+L"\\"+name,view,depth+1,budget);
 }
}
void registryAbsent() {
 for(HKEY hive:{HKEY_LOCAL_MACHINE,HKEY_CURRENT_USER})for(REGSAM view:{KEY_WOW64_32KEY,KEY_WOW64_64KEY}) {
  for(auto id:{CLSID_YimeTextServiceExperiment,GUID_YimeTextServiceExperimentProfile})
   require(!exists(hive,L"SOFTWARE\\Classes\\CLSID\\"+guid(id),view),"existing-com-identity");
  unsigned budget=0;scan(hive,L"SOFTWARE\\Microsoft\\CTF",view,0,budget);
 }
}
void apiAbsent(ITfInputProcessorProfiles* languages,ITfInputProcessorProfileMgr* profiles,ITfCategoryMgr* categories) {
 LANGID* list=nullptr;ULONG count=0;check(languages->GetLanguageList(&list,&count),"language-enumeration");
 struct Free { LANGID* data;~Free(){CoTaskMemFree(data);} } free{list};
 require(count<=1024 && (count==0||list),"language-list-bound");
 std::vector<LANGID> allLanguages{language};
 for(ULONG i=0;i<count;++i)if(list[i]!=language)allLanguages.push_back(list[i]);
 for(LANGID lang:allLanguages) {
  ComPtr<IEnumTfInputProcessorProfiles> values;check(profiles->EnumProfiles(lang,&values),"profile-enumeration");
  for(unsigned n=0;;++n) {
   require(n<20000,"profile-enumeration-bound");TF_INPUTPROCESSORPROFILE value{};ULONG fetched=0;
   const HRESULT hr=values->Next(1,&value,&fetched);
   if(hr==S_FALSE && fetched==0)break;
   check(hr,"profile-next");require(fetched==1,"profile-next-count");
   require(!IsEqualGUID(value.clsid,CLSID_YimeTextServiceExperiment) &&
           !IsEqualGUID(value.guidProfile,GUID_YimeTextServiceExperimentProfile),"existing-profile-identity");
  }
 }
 for(auto id:{CLSID_YimeTextServiceExperiment,GUID_YimeTextServiceExperimentProfile}) {
  ComPtr<IEnumGUID> categoriesForItem;check(categories->EnumCategoriesInItem(id,&categoriesForItem),"category-enumeration");
  GUID value{};ULONG fetched=0;HRESULT hr=categoriesForItem->Next(1,&value,&fetched);
  require(hr==S_FALSE && fetched==0,"existing-or-unknown-category");
 }
}
bool elevated() {
 HANDLE token=nullptr;check(OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&token)?S_OK:HRESULT_FROM_WIN32(GetLastError()),"token-open");
 TOKEN_ELEVATION value{};DWORD size=0;BOOL ok=GetTokenInformation(token,TokenElevation,&value,sizeof(value),&size);DWORD error=GetLastError();CloseHandle(token);
 check(ok?S_OK:HRESULT_FROM_WIN32(error),"token-elevation");return value.TokenIsElevated!=0;
}
#ifdef YIME_MYCOMPUTER_ACTIVATION_STAGE1
#include "MyComputerActivationSupport.h"
#endif
struct Ledger {
 std::wstring path;
 json data;
#ifdef YIME_MYCOMPUTER_ACTIVATION_STAGE1
 LocalDllLock dllLock;
 std::wstring expectedSha;
 HANDLE cipherReadLock=INVALID_HANDLE_VALUE;
 std::string cipherSha256;
 std::wstring expectedCipherSha256;
 ~Ledger(){if(cipherReadLock!=INVALID_HANDLE_VALUE)CloseHandle(cipherReadLock);}
 bool bindingVerified=false;
 yime::stage1::OwnerState ownerState=yime::stage1::OwnerState::Unknown;
#endif
 static unsigned long long creation(HANDLE process) {
  FILETIME made{},exit{},kernel{},user{};require(GetProcessTimes(process,&made,&exit,&kernel,&user)!=FALSE,"process-time-query");
  return (static_cast<unsigned long long>(made.dwHighDateTime)<<32)|made.dwLowDateTime;
 }
 void location(const std::wstring& input) {
  const std::filesystem::path value(input);
#ifdef YIME_MYCOMPUTER_ACTIVATION_STAGE1
  require(value.is_absolute() && value.filename()==L"registration-ledger.dpapi" && std::filesystem::is_directory(value.parent_path()),"ledger-location");path=value.lexically_normal().wstring();
#else
  require(value.is_absolute() && value.filename()==L"registration-ledger.json" && std::filesystem::is_directory(value.parent_path()),"ledger-location");path=value.lexically_normal().wstring();
#endif
 }
 void save() {
  const std::wstring temporary=path+L".tmp";
#ifdef YIME_MYCOMPUTER_ACTIVATION_STAGE1
  const auto text=protectLocalJournal(data.dump());
#else
  const auto text=data.dump();
#endif
  HANDLE file=CreateFileW(temporary.c_str(),GENERIC_WRITE,0,nullptr,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,nullptr);
  require(file!=INVALID_HANDLE_VALUE,"ledger-temporary-create");DWORD written=0;
  BOOL ok=WriteFile(file,text.data(),static_cast<DWORD>(text.size()),&written,nullptr);if(ok)ok=FlushFileBuffers(file);CloseHandle(file);
  require(ok && written==text.size(),"ledger-flush");
  require(MoveFileExW(temporary.c_str(),path.c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH)!=FALSE,"ledger-publish");
 }
 void create(const std::wstring& input,const std::wstring& dll) {
  location(input);HANDLE file=CreateFileW(path.c_str(),GENERIC_WRITE,0,nullptr,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,nullptr);
  require(file!=INVALID_HANDLE_VALUE,"ledger-must-be-new");CloseHandle(file);
  data={{"schema","18u-registration-ledger-v1"},{"clsid","6DFACE1F-562E-4773-A9D6-D5753A314711"},{"profile","1BD904AC-3194-4419-B70A-5574100F18B3"},
   {"pid",GetCurrentProcessId()},{"creation",creation(GetCurrentProcess())},{"dll",std::filesystem::path(dll).u8string()},
   {"preflightAbsent",false},{"comAttempted",false},{"comOwned",false},{"profileAttempted",false},{"categoryAttempted",false},{"enableAttempted",false},{"activationAttempted",false},{"cleanupVerified",false}};
#ifdef YIME_MYCOMPUTER_ACTIVATION_STAGE1
  require(dllLock.file!=INVALID_HANDLE_VALUE && !dllLock.sha.empty(),"verified-dll-required");
  data["schema"]="18u-mycomputer-ledger-v3";data["host"]=localUtf8(localHostName());data["sid"]=localSid();data["dllSha256"]=dllLock.sha;
#endif
  save();
 }
 void load(const std::wstring& input) {
  location(input);require(std::filesystem::is_regular_file(path) && std::filesystem::file_size(path)<=16384,"ledger-file");
#ifdef YIME_MYCOMPUTER_ACTIVATION_STAGE1
  require(yime::stage1::GoodHash(expectedCipherSha256),"expected-ledger-hash-required");
  cipherReadLock=CreateFileW(path.c_str(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
  require(cipherReadLock!=INVALID_HANDLE_VALUE,"ledger-snapshot-read-lock");LARGE_INTEGER cipherSize{};
  require(GetFileSizeEx(cipherReadLock,&cipherSize)!=FALSE && cipherSize.QuadPart>0 && cipherSize.QuadPart<=16384,"ledger-snapshot-bound");
  std::string cipher(static_cast<size_t>(cipherSize.QuadPart),'\0');DWORD bytesRead=0;
  require(ReadFile(cipherReadLock,cipher.data(),static_cast<DWORD>(cipher.size()),&bytesRead,nullptr)!=FALSE && bytesRead==cipher.size(),"ledger-snapshot-read");
  cipherSha256=localCipherSha256(cipher);require(cipherSha256==localUtf8(expectedCipherSha256),"ledger-snapshot-hash-mismatch");
  data=json::parse(unprotectLocalJournal(cipher));
  require(data.is_object() && data.size()==17 && data.at("schema")=="18u-mycomputer-ledger-v3","ledger-local-schema");
  require(data.at("host")==localUtf8(localHostName()) && data.at("sid")==localSid(),"ledger-host-account-binding");
  const auto hash=data.at("dllSha256").get<std::string>();expectedSha.assign(hash.begin(),hash.end());require(yime::stage1::GoodHash(expectedSha),"ledger-dll-hash");
  require(data.is_object()
#else
  std::ifstream file{std::filesystem::path(path)};data=json::parse(file);
  require(data.is_object() && data.size()==14 && data.at("schema")=="18u-registration-ledger-v1"
#endif
   && data.at("clsid")=="6DFACE1F-562E-4773-A9D6-D5753A314711" && data.at("profile")=="1BD904AC-3194-4419-B70A-5574100F18B3","ledger-identity");
  for(const char* key:{"preflightAbsent","comAttempted","comOwned","profileAttempted","categoryAttempted","enableAttempted","activationAttempted","cleanupVerified"})require(data.at(key).is_boolean(),"ledger-boolean");
  require(data.at("pid").is_number_unsigned() && data.at("pid").get<unsigned long long>()<=MAXDWORD && data.at("creation").is_number_unsigned(),"ledger-process-identity");
  auto dll=std::filesystem::u8path(data.at("dll").get<std::string>());require(dll.is_absolute() && dll.filename()==L"YimeTextService18u.dll"
#ifndef YIME_MYCOMPUTER_ACTIVATION_STAGE1
   && std::filesystem::is_regular_file(dll)
#endif
   ,"ledger-dll");
#ifdef YIME_MYCOMPUTER_ACTIVATION_STAGE1
  const DWORD attributes=GetFileAttributesW(dll.c_str());
  if(attributes!=INVALID_FILE_ATTRIBUTES)dllLock.open(dll.wstring(),expectedSha);
  else require(GetLastError()==ERROR_FILE_NOT_FOUND||GetLastError()==ERROR_PATH_NOT_FOUND,"ledger-dll-presence-unknown");
#endif
  const bool preflight=data.at("preflightAbsent").get<bool>(),attempt=data.at("comAttempted").get<bool>(),owned=data.at("comOwned").get<bool>();
  require((!attempt||preflight) && (!owned||attempt) && (!data.at("profileAttempted").get<bool>()||owned) &&
          (!data.at("categoryAttempted").get<bool>()||data.at("profileAttempted").get<bool>()) &&
          (!data.at("enableAttempted").get<bool>()||data.at("categoryAttempted").get<bool>()) &&
          (!data.at("activationAttempted").get<bool>()||data.at("enableAttempted").get<bool>()),"ledger-order");
#ifdef YIME_MYCOMPUTER_ACTIVATION_STAGE1
  require(yime::stage1::ValidLedgerOrder({preflight,attempt,owned,data.at("profileAttempted").get<bool>(),data.at("categoryAttempted").get<bool>(),data.at("enableAttempted").get<bool>(),data.at("activationAttempted").get<bool>(),data.at("cleanupVerified").get<bool>()}),"ledger-policy-order");
#endif
  const DWORD pid=data.at("pid").get<DWORD>();require(pid!=0 && pid!=GetCurrentProcessId(),"ledger-process-id");
  HANDLE process=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION|SYNCHRONIZE,FALSE,pid);
  if(process){const auto made=creation(process);DWORD wait=WaitForSingleObject(process,0);CloseHandle(process);require(made!=data.at("creation").get<unsigned long long>() || wait==WAIT_OBJECT_0,"original-process-still-running");}
  else require(GetLastError()==ERROR_INVALID_PARAMETER,"original-process-state-unknown");
#ifdef YIME_MYCOMPUTER_ACTIVATION_STAGE1
  bindingVerified=true;ownerState=yime::stage1::OwnerState::DeadVerified;
#endif
 }
 void validateOwnedCom() {
#ifdef YIME_MYCOMPUTER_ACTIVATION_STAGE1
  require(strictLocalComShape(std::filesystem::u8path(data.at("dll").get<std::string>()).wstring(),data.at("profileAttempted").get<bool>(),localGeneration(data)),"owned-generation-missing");return;
#endif
  const std::wstring root=L"SOFTWARE\\Classes\\CLSID\\"+guid(CLSID_YimeTextServiceExperiment);
  if(!exists(HKEY_LOCAL_MACHINE,root,KEY_WOW64_64KEY))return;
  // Only the original exact 64-bit COM binding is eligible for recovery deletion.
  Key server;check(HRESULT_FROM_WIN32(RegOpenKeyExW(HKEY_LOCAL_MACHINE,(root+L"\\InprocServer32").c_str(),0,KEY_READ|KEY_WOW64_64KEY,&server.value)),"recovery-com-binding-query");
  for(const wchar_t* name:{L"",L"ThreadingModel"}) {
   DWORD type=0,bytes=0;check(HRESULT_FROM_WIN32(RegQueryValueExW(server.value,name,nullptr,&type,nullptr,&bytes)),"recovery-com-value-query");
   require(type==REG_SZ && bytes>=sizeof(wchar_t) && bytes<=65536 && bytes%sizeof(wchar_t)==0,"recovery-com-value-type");
   std::wstring value(bytes/sizeof(wchar_t),L'\0');check(HRESULT_FROM_WIN32(RegQueryValueExW(server.value,name,nullptr,&type,reinterpret_cast<BYTE*>(value.data()),&bytes)),"recovery-com-value-read");
   require(value.back()==L'\0',"recovery-com-value-shape");value.pop_back();
   const std::wstring expected=*name?L"Apartment":std::filesystem::u8path(data.at("dll").get<std::string>()).wstring();
   require(_wcsicmp(value.c_str(),expected.c_str())==0 && value.size()==expected.size(),"recovery-com-identity-mismatch");
  }
 }
 void mark(const char* field){data[field]=true;save();}
};
struct Transaction {
 ComPtr<ITfInputProcessorProfileMgr> profiles;ComPtr<ITfInputProcessorProfiles> languages;ComPtr<ITfCategoryMgr> categories;
 ComPtr<ITfThreadMgrEx> manager;ComPtr<ITfDocumentMgr> document;ComPtr<ITfContext> context;
 Ledger* ledger=nullptr;
 bool writes=false,comOwned=false,profileAttempted=false,categoryAttempted=false,enableAttempted=false,activationAttempted=false,managerActive=false;
 bool cleanupOK=true;const char* cleanupStage="none";HRESULT cleanupCode=S_OK;
 LANGID threadLanguage=0,currentLanguage=0;
 const std::wstring clsidString=guid(CLSID_YimeTextServiceExperiment);
 std::wstring comPath=L"SOFTWARE\\Classes\\CLSID\\"+clsidString;
 void cleanupCheck(HRESULT hr,const char* stage){if(hr!=S_OK){cleanupOK=false;if(cleanupCode==S_OK){cleanupStage=stage;cleanupCode=hr;}}}
 void initialize(){
  check(CoCreateInstance(CLSID_TF_InputProcessorProfiles,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&profiles)),"profile-manager");
  check(profiles.As(&languages),"language-manager");
  check(CoCreateInstance(CLSID_TF_CategoryMgr,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&categories)),"category-manager");
 }
 void run(const std::wstring& dll
#ifdef YIME_ACTIVATED_LOOP
 ,const std::function<void()>& activatedLoop={}
#endif
 ) {
#ifdef YIME_MYCOMPUTER_ACTIVATION_STAGE1
  localMachineGate();require(ledger->dllLock.file!=INVALID_HANDLE_VALUE,"write-dll-lock-required");
#endif
  require(GetEnvironmentVariableW(L"YIME_TEXTSERVICE_EXPERIMENT_DIRECT_TEST",nullptr,0)==0,"direct-test-bypass-forbidden");
  require(sizeof(void*)==8,"native-x64");USHORT process=0,native=0;
  require(IsWow64Process2(GetCurrentProcess(),&process,&native) && process==IMAGE_FILE_MACHINE_UNKNOWN && native==IMAGE_FILE_MACHINE_AMD64,"native-x64");
  require(elevated(),"elevation-required");
  threadLanguage=LOWORD(reinterpret_cast<ULONG_PTR>(GetKeyboardLayout(0)));
  require(threadLanguage==language,"thread-language-required");
  initialize();check(languages->GetCurrentLanguage(&currentLanguage),"current-language-query");require(currentLanguage==language,"current-language-required");
  require(std::filesystem::path(dll).is_absolute() && std::filesystem::is_regular_file(dll) && std::filesystem::path(dll).filename()==L"YimeTextService18u.dll","dedicated-dll-path");
  registryAbsent();apiAbsent(languages.Get(),profiles.Get(),categories.Get());
#ifdef YIME_MYCOMPUTER_ACTIVATION_STAGE1
  require(yime::stage1::CanRegister({localNative(),_wcsicmp(localHostName().c_str(),L"MyComputer")==0,threadLanguage==language,currentLanguage==language,elevated(),true,ledger->dllLock.file!=INVALID_HANDLE_VALUE,GetEnvironmentVariableW(L"YIME_TEXTSERVICE_EXPERIMENT_DIRECT_TEST",nullptr,0)==0}),"write-policy-preflight");
#endif
  ledger->mark("preflightAbsent");
  // Last absence check before exclusive new-key creation; existing keys are never overwritten.
  require(exists(HKEY_LOCAL_MACHINE,L"SOFTWARE\\Classes\\CLSID",KEY_WOW64_64KEY),"com-parent-required");
  Key root;DWORD disposition=0;
  ledger->mark("comAttempted");
  writes=true; // A write API is now attempted; failure is not evidence of no writes.
  auto status=RegCreateKeyExW(HKEY_LOCAL_MACHINE,comPath.c_str(),0,nullptr,REG_OPTION_NON_VOLATILE,KEY_READ|KEY_WRITE|KEY_WOW64_64KEY,nullptr,&root.value,&disposition);
  check(HRESULT_FROM_WIN32(status),"create-com-root");
  require(disposition==REG_CREATED_NEW_KEY,"com-race-existing");
#ifdef YIME_MYCOMPUTER_ACTIVATION_STAGE1
  const std::wstring generation=localGeneration(ledger->data);
  check(HRESULT_FROM_WIN32(RegSetValueExW(root.value,L"YimeMyComputerGeneration",0,REG_SZ,reinterpret_cast<const BYTE*>(generation.c_str()),static_cast<DWORD>((generation.size()+1)*sizeof(wchar_t)))),"write-owned-generation");
  // Do not claim ownership in memory until the marker and encrypted checkpoint
  // are durable. A crash/flush failure in this gap remains unknown, not deletable.
  ledger->mark("comOwned");comOwned=true;
#else
  comOwned=true;ledger->mark("comOwned");
#endif
  Key server;disposition=0;
  check(HRESULT_FROM_WIN32(RegCreateKeyExW(root.value,L"InprocServer32",0,nullptr,REG_OPTION_NON_VOLATILE,KEY_WRITE|KEY_WOW64_64KEY,nullptr,&server.value,&disposition)),"create-com-server");
  require(disposition==REG_CREATED_NEW_KEY,"com-server-race");
  check(HRESULT_FROM_WIN32(RegSetValueExW(server.value,nullptr,0,REG_SZ,reinterpret_cast<const BYTE*>(dll.c_str()),static_cast<DWORD>((dll.size()+1)*sizeof(wchar_t)))),"write-com-path");
  constexpr wchar_t apartment[]=L"Apartment";
  check(HRESULT_FROM_WIN32(RegSetValueExW(server.value,L"ThreadingModel",0,REG_SZ,reinterpret_cast<const BYTE*>(apartment),sizeof(apartment))),"write-com-apartment");
  profileAttempted=true;ledger->mark("profileAttempted");
  check(profiles->RegisterProfile(CLSID_YimeTextServiceExperiment,language,GUID_YimeTextServiceExperimentProfile,YIME_PRODUCT_NAME,static_cast<ULONG>(wcslen(YIME_PRODUCT_NAME)),dll.c_str(),static_cast<ULONG>(dll.size()),0,nullptr,0,FALSE,0),"register-disabled-profile");
  BOOL enabled=TRUE;check(languages->IsEnabledLanguageProfile(CLSID_YimeTextServiceExperiment,language,GUID_YimeTextServiceExperimentProfile,&enabled),"verify-profile-disabled");
  require(enabled==FALSE,"profile-unexpectedly-enabled");
  categoryAttempted=true;ledger->mark("categoryAttempted");
  check(categories->RegisterCategory(CLSID_YimeTextServiceExperiment,GUID_TFCAT_TIP_KEYBOARD,CLSID_YimeTextServiceExperiment),"register-own-keyboard-category");
  enableAttempted=true;ledger->mark("enableAttempted");
  check(languages->EnableLanguageProfile(CLSID_YimeTextServiceExperiment,language,GUID_YimeTextServiceExperimentProfile,TRUE),"enable-own-profile");
#ifdef YIME_ACTIVATED_LOOP
  if(activatedLoop){
   activationAttempted=true;ledger->mark("activationAttempted");
   activatedLoop();
   activationAttempted=false; // callback returned only after checked host deactivation; journal remains historical true
   return;
  }
#endif
  check(CoCreateInstance(CLSID_TF_ThreadMgr,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&manager)),"thread-manager");
  TfClientId client=TF_CLIENTID_NULL;
  check(manager->ActivateEx(&client,TF_TMAE_NOACTIVATETIP|TF_TMAE_NOACTIVATEKEYBOARDLAYOUT),"activate-manager");managerActive=true;
  check(manager->CreateDocumentMgr(&document),"create-document");TfEditCookie cookie=0;
  check(document->CreateContext(client,0,nullptr,&context,&cookie),"create-context");check(document->Push(context.Get()),"push-context");check(manager->SetFocus(document.Get()),"set-own-document");
  activationAttempted=true;ledger->mark("activationAttempted");
  check(profiles->ActivateProfile(TF_PROFILETYPE_INPUTPROCESSOR,language,CLSID_YimeTextServiceExperiment,GUID_YimeTextServiceExperimentProfile,nullptr,TF_IPPMF_FORPROCESS),"activate-own-profile-forprocess");
  // Bounded message delivery permits Windows, not this runner, to create/activate the TIP.
  const ULONGLONG end=GetTickCount64()+1000;
  while(GetTickCount64()<end){MSG message{};while(PeekMessageW(&message,nullptr,0,0,PM_REMOVE)){TranslateMessage(&message);DispatchMessageW(&message);}Sleep(10);}
  TF_INPUTPROCESSORPROFILE active{};check(profiles->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD,&active),"get-active-profile");
  require(active.dwProfileType==TF_PROFILETYPE_INPUTPROCESSOR && active.langid==language && IsEqualGUID(active.clsid,CLSID_YimeTextServiceExperiment) && IsEqualGUID(active.guidProfile,GUID_YimeTextServiceExperimentProfile),"active-profile-mismatch");
 }
 void cleanup() {
  // Attempt flags are recorded before each API: partial writes after an API failure
  // belong to the previously absent exact identity, and must not be silently left behind.
#ifdef YIME_MYCOMPUTER_ACTIVATION_STAGE1
  // Refuse all cleanup mutations when the original COM binding has changed.
  if(writes && comOwned){ledger->validateOwnedCom();if(profileAttempted)strictLocalTipShape(languages.Get(),profiles.Get(),categories.Get());}
#endif
  if(activationAttempted) {
   TF_INPUTPROCESSORPROFILE active{};HRESULT hr=profiles->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD,&active);
   if(hr==S_OK && IsEqualGUID(active.clsid,CLSID_YimeTextServiceExperiment))
    cleanupCheck(profiles->DeactivateProfile(TF_PROFILETYPE_INPUTPROCESSOR,language,CLSID_YimeTextServiceExperiment,GUID_YimeTextServiceExperimentProfile,nullptr,TF_IPPMF_FORPROCESS),"cleanup-deactivate");
   else if(hr!=S_OK)cleanupCheck(hr,"cleanup-active-query");
  }
  if(managerActive){cleanupCheck(manager->SetFocus(nullptr),"cleanup-focus");if(document)cleanupCheck(document->Pop(TF_POPF_ALL),"cleanup-pop");context.Reset();document.Reset();cleanupCheck(manager->Deactivate(),"cleanup-manager");managerActive=false;}
  manager.Reset();
#ifdef YIME_MYCOMPUTER_ACTIVATION_STAGE1
  // Idempotent re-run (recovery after a partial first cleanup): a failed API call
  // counts as success only when the target is re-read as already absent.
  auto idempotent=[&](HRESULT hr,const char* stage,auto absent){
   if(hr==S_OK)return;bool gone=false;
   try{gone=absent();}catch(...){gone=false;}
   if(!gone)cleanupCheck(hr,stage);
  };
  if(enableAttempted)idempotent(languages->EnableLanguageProfile(CLSID_YimeTextServiceExperiment,language,GUID_YimeTextServiceExperimentProfile,FALSE),"cleanup-disable-own",[&]{
   BOOL enabled=TRUE;if(languages->IsEnabledLanguageProfile(CLSID_YimeTextServiceExperiment,language,GUID_YimeTextServiceExperimentProfile,&enabled)==S_OK)return enabled==FALSE;
   return !localProfileListed(languages.Get(),profiles.Get());});
  if(categoryAttempted)idempotent(categories->UnregisterCategory(CLSID_YimeTextServiceExperiment,GUID_TFCAT_TIP_KEYBOARD,CLSID_YimeTextServiceExperiment),"cleanup-category",[&]{return !localCategoryListed(categories.Get());});
  if(profileAttempted)idempotent(profiles->UnregisterProfile(CLSID_YimeTextServiceExperiment,language,GUID_YimeTextServiceExperimentProfile,0),"cleanup-profile",[&]{return !localProfileListed(languages.Get(),profiles.Get());});
#else
  if(enableAttempted)cleanupCheck(languages->EnableLanguageProfile(CLSID_YimeTextServiceExperiment,language,GUID_YimeTextServiceExperimentProfile,FALSE),"cleanup-disable-own");
  if(categoryAttempted)cleanupCheck(categories->UnregisterCategory(CLSID_YimeTextServiceExperiment,GUID_TFCAT_TIP_KEYBOARD,CLSID_YimeTextServiceExperiment),"cleanup-category");
  if(profileAttempted)cleanupCheck(profiles->UnregisterProfile(CLSID_YimeTextServiceExperiment,language,GUID_YimeTextServiceExperimentProfile,0),"cleanup-profile");
#endif
#ifdef YIME_MYCOMPUTER_ACTIVATION_STAGE1
  // Owned residue removal. UnregisterProfile/UnregisterCategory leave CTF\TIP\{CLSID}
  // shells in all four views; delete them only with every ownership fact proven.
  // Any doubt keeps the shell and the COM generation marker for later review.
  if(cleanupOK && writes && comOwned && profileAttempted && ledger)try{
   if(localTipResidueExists()){
    const auto& d=ledger->data;
    const yime::stage1::LedgerFlags flags{d.at("preflightAbsent").get<bool>(),d.at("comAttempted").get<bool>(),d.at("comOwned").get<bool>(),d.at("profileAttempted").get<bool>(),d.at("categoryAttempted").get<bool>(),d.at("enableAttempted").get<bool>(),d.at("activationAttempted").get<bool>(),d.at("cleanupVerified").get<bool>()};
    bool ownedCom=false;try{ledger->validateOwnedCom();ownedCom=true;}catch(const Failure&){ownedCom=false;}
    const auto shape=localResidueShape(languages.Get(),profiles.Get(),categories.Get());
    const bool enumerationAbsent=localProfileEnumerationAbsent(languages.Get(),profiles.Get(),categories.Get());
    require(yime::stage1::CanRemoveResidue(flags,ownedCom,shape,enumerationAbsent),"cleanup-residue-ownership-not-proven");
    localRemoveOwnedTipResidue(languages.Get(),profiles.Get(),categories.Get());
   }
  }catch(const Failure& f){cleanupCheck(f.code,f.stage);}catch(...){cleanupCheck(E_FAIL,"cleanup-residue-exception");}
#endif
#ifndef YIME_MYCOMPUTER_ACTIVATION_STAGE1
  if(profileAttempted)try{
   bool remaining=false;for(HKEY hive:{HKEY_LOCAL_MACHINE,HKEY_CURRENT_USER})for(REGSAM view:{KEY_WOW64_32KEY,KEY_WOW64_64KEY})
    remaining=exists(hive,L"SOFTWARE\\Microsoft\\CTF\\TIP\\"+clsidString,view)||remaining;
   if(remaining)cleanupCheck(languages->Unregister(CLSID_YimeTextServiceExperiment),"cleanup-owned-service-residue");
  }catch(const Failure& f){cleanupCheck(f.code,f.stage);}catch(...){cleanupCheck(E_FAIL,"cleanup-service-query");}
#endif
#ifdef YIME_MYCOMPUTER_ACTIVATION_STAGE1
  // Keep the sole generation marker if any earlier cleanup failed or if TIP
  // references cannot be proved absent. Never erase recovery provenance first.
  if(comOwned && cleanupOK)try{ledger->validateOwnedCom();localTipAbsent(languages.Get(),profiles.Get(),categories.Get());}
   catch(const Failure& failure){cleanupCheck(failure.code,failure.stage);}catch(...){cleanupCheck(E_FAIL,"cleanup-owned-tip-absence-unknown");}
  if(comOwned && cleanupOK)
#else
  if(comOwned)
#endif
  {Key parent;LSTATUS hr=RegOpenKeyExW(HKEY_LOCAL_MACHINE,L"SOFTWARE\\Classes\\CLSID",0,KEY_READ|KEY_WRITE|KEY_WOW64_64KEY,&parent.value);if(hr==ERROR_SUCCESS)hr=RegDeleteTreeW(parent.value,clsidString.c_str());cleanupCheck(HRESULT_FROM_WIN32(hr),"cleanup-owned-com");}
  if(writes)try{registryAbsent();apiAbsent(languages.Get(),profiles.Get(),categories.Get());}catch(const Failure& f){cleanupCheck(f.code,f.stage);}catch(...){cleanupCheck(E_FAIL,"cleanup-query-exception");}
 }
};
}
json output(const char* status,bool writes,bool clean,const char* stage,HRESULT code,const char* scope,const Transaction* t=nullptr) {
 return {{"status",status},{"writesStarted",writes},{"cleanupVerified",clean},{"stage",stage},{"code",static_cast<unsigned long>(code)},{"scope",scope},
  {"threadLanguage",t?t->threadLanguage:0},{"currentLanguage",t?t->currentLanguage:0},
  {"ledger",{{"comOwned",t&&t->comOwned},{"profileAttempted",t&&t->profileAttempted},{"categoryAttempted",t&&t->categoryAttempted},{"enableAttempted",t&&t->enableAttempted},{"activationAttempted",t&&t->activationAttempted}}}};
}
#ifndef YIME_MYCOMPUTER_ACTIVATION_STAGE1
int wmain(int argc,wchar_t** argv) {
 const bool normal=argc==5 && wcscmp(argv[1],L"--dll")==0 && wcscmp(argv[3],L"--ledger")==0;
 const bool recovery=argc==4 && wcscmp(argv[1],L"--cleanup-only")==0 && wcscmp(argv[2],L"--ledger")==0;
 const bool verify=argc==2 && wcscmp(argv[1],L"--verify-absent")==0;
 const char* scope=normal?"profile-activation-only":(recovery?"profile-cleanup-only":"profile-absence-only");
 if(!normal&&!recovery&&!verify){std::cout<<output("blocked",false,false,"arguments",E_INVALIDARG,scope).dump()<<std::endl;return 3;}
 const HRESULT initialized=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
 if(FAILED(initialized)){std::cout<<output(normal?"blocked":"failed",false,false,"com-initialize",initialized,scope).dump()<<std::endl;return normal?3:1;}
 int exit=1;
 {
  Transaction transaction;Ledger ledger;transaction.ledger=&ledger;
  const char* stage="completed";HRESULT code=S_OK;bool completed=false,unknown=false;
  try {
   if(normal){ledger.create(argv[4],argv[2]);transaction.run(argv[2]);completed=true;}
   else if(verify){transaction.initialize();registryAbsent();apiAbsent(transaction.languages.Get(),transaction.profiles.Get(),transaction.categories.Get());completed=true;}
   else {
    unknown=true;ledger.load(argv[3]);
    require(ledger.data.at("preflightAbsent").get<bool>() || !ledger.data.at("comAttempted").get<bool>(),"ledger-inconsistent");
    transaction.writes=ledger.data.at("comAttempted").get<bool>();
    transaction.comOwned=ledger.data.at("comOwned").get<bool>();
    transaction.profileAttempted=ledger.data.at("profileAttempted").get<bool>();
    transaction.categoryAttempted=ledger.data.at("categoryAttempted").get<bool>();
    transaction.enableAttempted=ledger.data.at("enableAttempted").get<bool>();
    // Process-scoped activation cannot survive the confirmed-dead original process.
    transaction.activationAttempted=false;
    transaction.initialize();
    if(!ledger.data.at("cleanupVerified").get<bool>()) {
     require(!transaction.writes || transaction.comOwned,"unconfirmed-com-creation-window");
     if(transaction.writes){require(elevated(),"cleanup-elevation-required");ledger.validateOwnedCom();}
     transaction.cleanup();
    } else {registryAbsent();apiAbsent(transaction.languages.Get(),transaction.profiles.Get(),transaction.categories.Get());}
    require(transaction.cleanupOK,"recovery-cleanup-failed");unknown=false;completed=true;
   }
  }catch(const Failure& failure){stage=failure.stage;code=failure.code;}catch(...){stage="unclassified-exception";code=E_FAIL;}
  if(normal)try{transaction.cleanup();}catch(const Failure& failure){transaction.cleanupCheck(failure.code,failure.stage);}catch(...){transaction.cleanupCheck(E_FAIL,"cleanup-exception");}
  if(!transaction.cleanupOK){stage=transaction.cleanupStage;code=transaction.cleanupCode;}
  if((normal||recovery) && transaction.cleanupOK && !unknown && !ledger.data.empty())try{ledger.mark("cleanupVerified");}catch(...){transaction.cleanupCheck(E_FAIL,"ledger-cleanup-checkpoint");stage="ledger-cleanup-checkpoint";code=E_FAIL;}
  const char* status=completed && transaction.cleanupOK?"pass":(normal&&!transaction.writes?"blocked":"failed");
  exit=std::string(status)=="pass"?0:(normal&&!transaction.writes?3:1);
  const bool clean=transaction.cleanupOK && !unknown && (verify?completed:(transaction.writes||recovery));
  auto report=output(status,transaction.writes,clean,stage,code,scope,&transaction);
  if(recovery && unknown)report["writesStarted"]=nullptr;
  std::cout<<report.dump()<<std::endl;
 }
 CoUninitialize();return exit;
}

#endif
#if defined(YIME_MYCOMPUTER_ACTIVATION_STAGE1) && !defined(YIME_RESIDUE_FIXTURE_TESTS)
#include "MyComputerActivationMain.h"
#endif

#ifdef YIME_ACTIVATED_LOOP
#include "ActivatedLoopMain.h"
#endif
