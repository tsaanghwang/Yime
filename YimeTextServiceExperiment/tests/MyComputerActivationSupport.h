#pragma once
// Included only by the opt-in local target, inside RegistrationProbe's namespace.
// DPAPI binds this journal to its Windows user; it is not protection against a
// malicious process already running as that same user.
std::wstring localHostName(){wchar_t text[MAX_COMPUTERNAME_LENGTH+1]{};DWORD size=MAX_COMPUTERNAME_LENGTH+1;require(GetComputerNameW(text,&size)!=FALSE,"hostname-query");return {text,size};}
std::string localUtf8(const std::wstring& value){int size=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),nullptr,0,nullptr,nullptr);require(size>0&&size<32768,"identity-encoding");std::string result(size,'\0');require(WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),result.data(),size,nullptr,nullptr)==size,"identity-encoding");return result;}
std::string localSid(){
 HANDLE token=nullptr;require(OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&token)!=FALSE,"owner-token-query");
 DWORD size=0;GetTokenInformation(token,TokenUser,nullptr,0,&size);if(size==0||size>65536){CloseHandle(token);throw Failure{"owner-token-bound",E_FAIL};}
 std::vector<BYTE> data(size);BOOL ok=GetTokenInformation(token,TokenUser,data.data(),size,&size);CloseHandle(token);require(ok!=FALSE,"owner-token-user");
 LPWSTR text=nullptr;require(ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(data.data())->User.Sid,&text)!=FALSE,"owner-sid-query");std::wstring sid(text);LocalFree(text);return localUtf8(sid);
}
bool localNative(){USHORT process=0,native=0;require(IsWow64Process2(GetCurrentProcess(),&process,&native)!=FALSE,"native-architecture-query");return sizeof(void*)==8&&process==IMAGE_FILE_MACHINE_UNKNOWN&&native==IMAGE_FILE_MACHINE_AMD64;}
void localMachineGate(){require(localNative(),"native-x64-required");require(_wcsicmp(localHostName().c_str(),L"MyComputer")==0,"mycomputer-host-required");}
std::string protectLocalJournal(const std::string& plain){
 DATA_BLOB input{static_cast<DWORD>(plain.size()),reinterpret_cast<BYTE*>(const_cast<char*>(plain.data()))},output{};
 require(CryptProtectData(&input,L"Yime MyComputer stage1",nullptr,nullptr,nullptr,CRYPTPROTECT_UI_FORBIDDEN,&output)!=FALSE,"ledger-protect");
 std::string result(reinterpret_cast<char*>(output.pbData),output.cbData);LocalFree(output.pbData);return result;
}
std::string unprotectLocalJournal(const std::string& cipher){
 DATA_BLOB input{static_cast<DWORD>(cipher.size()),reinterpret_cast<BYTE*>(const_cast<char*>(cipher.data()))},output{};
 require(CryptUnprotectData(&input,nullptr,nullptr,nullptr,nullptr,CRYPTPROTECT_UI_FORBIDDEN,&output)!=FALSE,"ledger-owner-decrypt");
 std::string result(reinterpret_cast<char*>(output.pbData),output.cbData);LocalFree(output.pbData);require(result.size()<=16384,"ledger-plaintext-bound");return result;
}
struct LocalDllLock {
 HANDLE file=INVALID_HANDLE_VALUE;std::wstring canonical;std::string sha;
 ~LocalDllLock(){if(file!=INVALID_HANDLE_VALUE)CloseHandle(file);}
 void open(const std::wstring& input,const std::wstring& expected){
  require(file==INVALID_HANDLE_VALUE && yime::stage1::GoodHash(expected),"dll-hash-contract");
  require(input.size()>3 && input[1]==L':' && input[2]==L'\\' && input.find(L':',2)==std::wstring::npos,"dll-local-absolute-path");
  file=CreateFileW(input.c_str(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);require(file!=INVALID_HANDLE_VALUE,"dll-read-lock");
  std::vector<wchar_t> path(32768);DWORD length=GetFinalPathNameByHandleW(file,path.data(),static_cast<DWORD>(path.size()),FILE_NAME_NORMALIZED|VOLUME_NAME_DOS);
  require(length>7&&length<path.size(),"dll-canonical-path");canonical.assign(path.data(),length);require(canonical.compare(0,4,L"\\\\?\\")==0&&canonical[5]==L':'&&canonical[6]==L'\\',"dll-local-canonical-path");canonical.erase(0,4);
  require(std::filesystem::path(canonical).filename()==L"YimeTextService18u.dll","dedicated-dll-filename");
  LARGE_INTEGER size{};require(GetFileSizeEx(file,&size)!=FALSE && size.QuadPart>0 && size.QuadPart<=128*1024*1024,"dll-size-bound");
  IMAGE_DOS_HEADER dos{};DWORD read=0;require(ReadFile(file,&dos,sizeof(dos),&read,nullptr)&&read==sizeof(dos)&&dos.e_magic==IMAGE_DOS_SIGNATURE&&dos.e_lfanew>=0&&static_cast<LONGLONG>(dos.e_lfanew)+4+sizeof(IMAGE_FILE_HEADER)<=size.QuadPart,"dll-dos-header");
  LARGE_INTEGER offset{};offset.QuadPart=dos.e_lfanew;require(SetFilePointerEx(file,offset,nullptr,FILE_BEGIN)!=FALSE,"dll-pe-seek");DWORD signature=0;IMAGE_FILE_HEADER header{};
  require(ReadFile(file,&signature,sizeof(signature),&read,nullptr)&&read==sizeof(signature)&&signature==IMAGE_NT_SIGNATURE,"dll-pe-signature");
  require(ReadFile(file,&header,sizeof(header),&read,nullptr)&&read==sizeof(header)&&header.Machine==IMAGE_FILE_MACHINE_AMD64&&(header.Characteristics&IMAGE_FILE_DLL),"dll-amd64-required");
  offset.QuadPart=0;require(SetFilePointerEx(file,offset,nullptr,FILE_BEGIN)!=FALSE,"dll-hash-seek");
  BCRYPT_ALG_HANDLE algorithm=nullptr;BCRYPT_HASH_HANDLE hash=nullptr;
  std::vector<BYTE> object; // Must outlive BCryptDestroyHash on success and exceptions.
  struct Cleanup{BCRYPT_ALG_HANDLE& a;BCRYPT_HASH_HANDLE& h;~Cleanup(){if(h)BCryptDestroyHash(h);if(a)BCryptCloseAlgorithmProvider(a,0);}}cleanup{algorithm,hash};
  require(BCryptOpenAlgorithmProvider(&algorithm,BCRYPT_SHA256_ALGORITHM,nullptr,0)==0,"dll-hash-provider");DWORD objectSize=0,returned=0;
  require(BCryptGetProperty(algorithm,BCRYPT_OBJECT_LENGTH,reinterpret_cast<PUCHAR>(&objectSize),sizeof(objectSize),&returned,0)==0&&objectSize<=65536,"dll-hash-object");object.resize(objectSize);
  require(BCryptCreateHash(algorithm,&hash,object.data(),objectSize,nullptr,0,0)==0,"dll-hash-create");std::vector<BYTE> block(65536);LONGLONG total=0;
  for(;;){require(ReadFile(file,block.data(),static_cast<DWORD>(block.size()),&read,nullptr)!=FALSE,"dll-hash-read");if(!read)break;total+=read;require(total<=size.QuadPart&&BCryptHashData(hash,block.data(),read,0)==0,"dll-hash-data");}
  BYTE digest[32]{};require(total==size.QuadPart&&BCryptFinishHash(hash,digest,sizeof(digest),0)==0,"dll-hash-finish");constexpr char digits[]="0123456789abcdef";
  for(BYTE b:digest){sha.push_back(digits[b>>4]);sha.push_back(digits[b&15]);}require(sha==localUtf8(expected),"dll-sha256-mismatch");
 }
};
std::wstring localGeneration(const json& ledger){
 const auto sha=ledger.at("dllSha256").get<std::string>();
 const auto text=yime::stage1::Generation(ledger.at("pid").get<DWORD>(),ledger.at("creation").get<unsigned long long>(),std::wstring(sha.begin(),sha.end()));
 require(!text.empty()&&text.size()<=96,"ledger-generation-bound");return text;
}
bool strictLocalComShape(const std::wstring& expected,bool profileAttempted,const std::wstring& generation){
 Key root;const std::wstring path=L"SOFTWARE\\Classes\\CLSID\\"+guid(CLSID_YimeTextServiceExperiment);
 LSTATUS status=RegOpenKeyExW(HKEY_LOCAL_MACHINE,path.c_str(),0,KEY_READ|KEY_WOW64_64KEY,&root.value);if(status==ERROR_FILE_NOT_FOUND||status==ERROR_PATH_NOT_FOUND)return false;check(HRESULT_FROM_WIN32(status),"owned-com-root-query");
 DWORD children=0,values=0;check(HRESULT_FROM_WIN32(RegQueryInfoKeyW(root.value,nullptr,nullptr,nullptr,&children,nullptr,nullptr,&values,nullptr,nullptr,nullptr,nullptr)),"owned-com-root-shape");
 require(values==1&&children<=1,"owned-com-root-changed");
 DWORD generationType=0,generationBytes=0;
 check(HRESULT_FROM_WIN32(RegQueryValueExW(root.value,L"YimeMyComputerGeneration",nullptr,&generationType,nullptr,&generationBytes)),"owned-generation-query");
 require(generationType==REG_SZ&&generationBytes==(generation.size()+1)*sizeof(wchar_t),"owned-generation-shape");
 std::wstring actualGeneration(generation.size()+1,L'\0');
 check(HRESULT_FROM_WIN32(RegQueryValueExW(root.value,L"YimeMyComputerGeneration",nullptr,&generationType,reinterpret_cast<BYTE*>(actualGeneration.data()),&generationBytes)),"owned-generation-read");
 require(generationType==REG_SZ&&generationBytes==actualGeneration.size()*sizeof(wchar_t)&&actualGeneration.back()==L'\0',"owned-generation-shape");actualGeneration.pop_back();
 require(actualGeneration==generation,"owned-generation-mismatch");
 if(children==0){require(!profileAttempted,"owned-com-incomplete-after-profile");return true;}
 wchar_t name[256]{};DWORD count=256;check(HRESULT_FROM_WIN32(RegEnumKeyExW(root.value,0,name,&count,nullptr,nullptr,nullptr,nullptr)),"owned-com-child-query");require(_wcsicmp(name,L"InprocServer32")==0,"owned-com-child-changed");
 Key server;check(HRESULT_FROM_WIN32(RegOpenKeyExW(root.value,L"InprocServer32",0,KEY_READ,&server.value)),"owned-com-server-query");
 check(HRESULT_FROM_WIN32(RegQueryInfoKeyW(server.value,nullptr,nullptr,nullptr,&children,nullptr,nullptr,&values,nullptr,nullptr,nullptr,nullptr)),"owned-com-server-shape");require(children==0&&values<=2&&(!profileAttempted||values==2),"owned-com-server-changed");
 for(DWORD i=0;i<values;++i){wchar_t field[256]{};DWORD chars=256,type=0,bytes=0;check(HRESULT_FROM_WIN32(RegEnumValueW(server.value,i,field,&chars,nullptr,&type,nullptr,&bytes)),"owned-com-value-query");require((chars==0||_wcsicmp(field,L"ThreadingModel")==0)&&(!(values==1)||chars==0)&&type==REG_SZ&&bytes>=2&&bytes<=65536&&bytes%sizeof(wchar_t)==0,"owned-com-value-changed");std::wstring value(bytes/sizeof(wchar_t),L'\0');check(HRESULT_FROM_WIN32(RegQueryValueExW(server.value,field,nullptr,&type,reinterpret_cast<BYTE*>(value.data()),&bytes)),"owned-com-value-read");require(type==REG_SZ&&bytes==value.size()*sizeof(wchar_t)&&value.back()==L'\0',"owned-com-value-shape");value.pop_back();const std::wstring wanted=chars?L"Apartment":expected;require(value.size()==wanted.size()&&_wcsicmp(value.c_str(),wanted.c_str())==0,"owned-com-binding-changed");}
 return true;
}
std::vector<std::wstring> localChildren(HKEY key){
 std::vector<std::wstring> result;for(DWORD index=0;index<64;++index){wchar_t name[256]{};DWORD count=256;const LSTATUS status=RegEnumKeyExW(key,index,name,&count,nullptr,nullptr,nullptr,nullptr);if(status==ERROR_NO_MORE_ITEMS)return result;check(HRESULT_FROM_WIN32(status),"owned-tip-children-query");result.emplace_back(name,count);}throw Failure{"owned-tip-children-bound",E_FAIL};
}
void localCategoryShape(HKEY key,unsigned depth){
 require(depth<=6,"owned-category-depth");
 const auto owner=guid(CLSID_YimeTextServiceExperiment),category=guid(GUID_TFCAT_TIP_KEYBOARD);
 for(const auto& name:localChildren(key)){
  require(_wcsicmp(name.c_str(),owner.c_str())==0||_wcsicmp(name.c_str(),category.c_str())==0||_wcsicmp(name.c_str(),L"Item")==0||_wcsicmp(name.c_str(),L"Category")==0,"owned-category-unknown-reference");
  Key child;check(HRESULT_FROM_WIN32(RegOpenKeyExW(key,name.c_str(),0,KEY_READ,&child.value)),"owned-category-child");localCategoryShape(child.value,depth+1);
 }
 DWORD values=0;check(HRESULT_FROM_WIN32(RegQueryInfoKeyW(key,nullptr,nullptr,nullptr,nullptr,nullptr,nullptr,&values,nullptr,nullptr,nullptr,nullptr)),"owned-category-values");require(values==0,"owned-category-value-unknown");
}
void strictLocalTipShape(ITfInputProcessorProfiles* languages,ITfInputProcessorProfileMgr* profiles,ITfCategoryMgr* categories){
 LANGID* list=nullptr;ULONG count=0;check(languages->GetLanguageList(&list,&count),"owned-language-list");struct Free{LANGID* p;~Free(){CoTaskMemFree(p);}}free{list};require(count<=1024&&(count==0||list),"owned-language-bound");
 std::vector<LANGID> all{language};for(ULONG i=0;i<count;++i)if(list[i]!=language)all.push_back(list[i]);
 for(LANGID lang:all){ComPtr<IEnumTfInputProcessorProfiles> items;check(profiles->EnumProfiles(lang,&items),"owned-profile-list");for(unsigned n=0;;++n){require(n<20000,"owned-profile-bound");TF_INPUTPROCESSORPROFILE value{};ULONG fetched=0;HRESULT hr=items->Next(1,&value,&fetched);if(hr==S_FALSE&&fetched==0)break;check(hr,"owned-profile-next");require(fetched==1,"owned-profile-count");if(IsEqualGUID(value.clsid,CLSID_YimeTextServiceExperiment)||IsEqualGUID(value.guidProfile,GUID_YimeTextServiceExperimentProfile))require(value.langid==language&&IsEqualGUID(value.clsid,CLSID_YimeTextServiceExperiment)&&IsEqualGUID(value.guidProfile,GUID_YimeTextServiceExperimentProfile),"owned-profile-mixed-identity");}}
 ComPtr<IEnumGUID> categoryList;check(categories->EnumCategoriesInItem(CLSID_YimeTextServiceExperiment,&categoryList),"owned-category-list");for(unsigned n=0;;++n){require(n<16,"owned-category-bound");GUID value{};ULONG fetched=0;HRESULT hr=categoryList->Next(1,&value,&fetched);if(hr==S_FALSE&&fetched==0)break;check(hr,"owned-category-next");require(fetched==1&&IsEqualGUID(value,GUID_TFCAT_TIP_KEYBOARD),"owned-category-mixed-identity");}
 for(HKEY hive:{HKEY_LOCAL_MACHINE,HKEY_CURRENT_USER})for(REGSAM view:{KEY_WOW64_32KEY,KEY_WOW64_64KEY}){
  Key root;const auto path=L"SOFTWARE\\Microsoft\\CTF\\TIP\\"+guid(CLSID_YimeTextServiceExperiment);LSTATUS status=RegOpenKeyExW(hive,path.c_str(),0,KEY_READ|view,&root.value);if(status==ERROR_FILE_NOT_FOUND||status==ERROR_PATH_NOT_FOUND)continue;check(HRESULT_FROM_WIN32(status),"owned-tip-root");
  for(const auto& name:localChildren(root.value)){
   Key child;check(HRESULT_FROM_WIN32(RegOpenKeyExW(root.value,name.c_str(),0,KEY_READ,&child.value)),"owned-tip-child");
   if(_wcsicmp(name.c_str(),L"Category")==0){localCategoryShape(child.value,0);continue;}
   require(_wcsicmp(name.c_str(),L"LanguageProfile")==0,"owned-tip-unknown-child");
   for(const auto& lang:localChildren(child.value)){
    require(_wcsicmp(lang.c_str(),L"0x00000804")==0,"owned-tip-other-language");Key langKey;check(HRESULT_FROM_WIN32(RegOpenKeyExW(child.value,lang.c_str(),0,KEY_READ,&langKey.value)),"owned-tip-language");
    for(const auto& profile:localChildren(langKey.value)){
     require(_wcsicmp(profile.c_str(),guid(GUID_YimeTextServiceExperimentProfile).c_str())==0,"owned-tip-other-profile");Key leaf;check(HRESULT_FROM_WIN32(RegOpenKeyExW(langKey.value,profile.c_str(),0,KEY_READ,&leaf.value)),"owned-tip-profile");require(localChildren(leaf.value).empty(),"owned-tip-profile-unknown-child");
    }
   }
  }
 }
}

std::string localCipherSha256(const std::string& bytes){
 require(bytes.size()<=16384,"ledger-cipher-bound");BCRYPT_ALG_HANDLE algorithm=nullptr;
 struct Cleanup{BCRYPT_ALG_HANDLE& value;~Cleanup(){if(value)BCryptCloseAlgorithmProvider(value,0);}}cleanup{algorithm};
 require(BCryptOpenAlgorithmProvider(&algorithm,BCRYPT_SHA256_ALGORITHM,nullptr,0)==0,"ledger-hash-provider");
 BYTE digest[32]{};require(BCryptHash(algorithm,nullptr,0,reinterpret_cast<PUCHAR>(const_cast<char*>(bytes.data())),static_cast<ULONG>(bytes.size()),digest,sizeof(digest))==0,"ledger-hash-query");
 constexpr char digits[]="0123456789abcdef";std::string result;for(BYTE byte:digest){result.push_back(digits[byte>>4]);result.push_back(digits[byte&15]);}return result;
}

void localTipAbsent(ITfInputProcessorProfiles* languages,ITfInputProcessorProfileMgr* profiles,ITfCategoryMgr* categories){
 for(HKEY hive:{HKEY_LOCAL_MACHINE,HKEY_CURRENT_USER})for(REGSAM view:{KEY_WOW64_32KEY,KEY_WOW64_64KEY}){
  unsigned budget=0;scan(hive,L"SOFTWARE\\Microsoft\\CTF",view,0,budget);
 }
 apiAbsent(languages,profiles,categories);
}

// --- Owned TIP residue: UnregisterProfile/UnregisterCategory leave CTF\TIP\{CLSID},
// its Category parent, the empty 0x00000804 branch and the HKCU Enable leaf behind.
std::wstring localTipPath(){return L"SOFTWARE\\Microsoft\\CTF\\TIP\\"+guid(CLSID_YimeTextServiceExperiment);}
bool localTipResidueExists(){
 bool any=false;
 for(HKEY hive:{HKEY_LOCAL_MACHINE,HKEY_CURRENT_USER})for(REGSAM view:{KEY_WOW64_32KEY,KEY_WOW64_64KEY})any=exists(hive,localTipPath(),view)||any;
 return any;
}
// TSF no longer enumerates this CLSID/profile in any language and lists no category
// for it. Failure stages come from apiAbsent and are not presence evidence by themselves.
bool localProfileEnumerationAbsent(ITfInputProcessorProfiles* languages,ITfInputProcessorProfileMgr* profiles,ITfCategoryMgr* categories){
 try{apiAbsent(languages,profiles,categories);return true;}
 catch(const Failure& failure){
  const std::string stage=failure.stage;
  if(stage=="existing-profile-identity"||stage=="existing-or-unknown-category")return false;
  throw;
 }
}
// Single-fact re-reads used to judge idempotent cleanup steps whose API call failed.
bool localProfileListed(ITfInputProcessorProfiles* languages,ITfInputProcessorProfileMgr* profiles){
 LANGID* list=nullptr;ULONG count=0;check(languages->GetLanguageList(&list,&count),"language-enumeration");
 struct Free{LANGID* data;~Free(){CoTaskMemFree(data);}}free{list};require(count<=1024&&(count==0||list),"language-list-bound");
 std::vector<LANGID> all{language};for(ULONG i=0;i<count;++i)if(list[i]!=language)all.push_back(list[i]);
 for(LANGID lang:all){
  ComPtr<IEnumTfInputProcessorProfiles> values;check(profiles->EnumProfiles(lang,&values),"profile-enumeration");
  for(unsigned n=0;;++n){
   require(n<20000,"profile-enumeration-bound");TF_INPUTPROCESSORPROFILE value{};ULONG fetched=0;const HRESULT hr=values->Next(1,&value,&fetched);
   if(hr==S_FALSE&&fetched==0)break;check(hr,"profile-next");require(fetched==1,"profile-next-count");
   if(IsEqualGUID(value.clsid,CLSID_YimeTextServiceExperiment)||IsEqualGUID(value.guidProfile,GUID_YimeTextServiceExperimentProfile))return true;
  }
 }
 return false;
}
bool localCategoryListed(ITfCategoryMgr* categories){
 ComPtr<IEnumGUID> list;check(categories->EnumCategoriesInItem(CLSID_YimeTextServiceExperiment,&list),"category-enumeration");
 GUID value{};ULONG fetched=0;const HRESULT hr=list->Next(1,&value,&fetched);
 if(hr==S_FALSE&&fetched==0)return false;check(hr,"category-next");return true;
}
// Stages strictLocalTipShape raises for a foreign reference inside the owned subtree.
// Query, access and bound failures keep their own stages and are never "not owned".
bool localForeignReferenceStage(const std::string& stage){
 for(const char* foreign:{"owned-profile-mixed-identity","owned-category-mixed-identity","owned-tip-unknown-child","owned-tip-other-language","owned-tip-other-profile","owned-tip-profile-unknown-child","owned-category-unknown-reference","owned-category-value-unknown"})
  if(stage==foreign)return true;
 return false;
}
yime::stage1::ResidueShape localResidueShape(ITfInputProcessorProfiles* languages,ITfInputProcessorProfileMgr* profiles,ITfCategoryMgr* categories){
 using yime::stage1::ResidueShape;
 if(!localTipResidueExists())return ResidueShape::Absent;
 if(!localProfileEnumerationAbsent(languages,profiles,categories))return ResidueShape::NotOwned;
 try{strictLocalTipShape(languages,profiles,categories);return ResidueShape::OwnedEmptyShell;}
 catch(const Failure& failure){
  if(localForeignReferenceStage(failure.stage))return ResidueShape::NotOwned;
  throw;
 }
}
// Caller proves CanRemoveResidue first. Unregister is TSF's whole-tree removal; any
// view still holding the shell is re-checked for exact shape before RegDeleteTree.
// Success is only the re-read absence of every view, never an HRESULT.
void localRemoveOwnedTipResidue(ITfInputProcessorProfiles* languages,ITfInputProcessorProfileMgr* profiles,ITfCategoryMgr* categories){
 require(localTipResidueExists(),"residue-already-absent");
 strictLocalTipShape(languages,profiles,categories);
 const HRESULT unregistered=languages->Unregister(CLSID_YimeTextServiceExperiment);
 (void)unregistered; // Judged by re-reading below; an absent target is not an error.
 for(HKEY hive:{HKEY_LOCAL_MACHINE,HKEY_CURRENT_USER})for(REGSAM view:{KEY_WOW64_32KEY,KEY_WOW64_64KEY}){
  if(!exists(hive,localTipPath(),view))continue;
  strictLocalTipShape(languages,profiles,categories);
  Key parent;const LSTATUS opened=RegOpenKeyExW(hive,L"SOFTWARE\\Microsoft\\CTF\\TIP",0,KEY_READ|KEY_WRITE|view,&parent.value);
  if(opened==ERROR_FILE_NOT_FOUND||opened==ERROR_PATH_NOT_FOUND)continue;
  check(HRESULT_FROM_WIN32(opened),"residue-tip-parent-open");
  const LSTATUS removed=RegDeleteTreeW(parent.value,guid(CLSID_YimeTextServiceExperiment).c_str());
  require(removed==ERROR_SUCCESS||removed==ERROR_FILE_NOT_FOUND||removed==ERROR_PATH_NOT_FOUND,"residue-tip-delete");
  require(yime::stage1::ResidueStepSucceeded(exists(hive,localTipPath(),view)),"residue-tip-remains");
 }
 require(yime::stage1::ResidueStepSucceeded(localTipResidueExists()),"residue-tip-remains");
}
std::string localSha256Hex(const BYTE* bytes,size_t size){
 require(size<=1048576,"snapshot-value-bound");BCRYPT_ALG_HANDLE algorithm=nullptr;
 struct Cleanup{BCRYPT_ALG_HANDLE& value;~Cleanup(){if(value)BCryptCloseAlgorithmProvider(value,0);}}cleanup{algorithm};
 require(BCryptOpenAlgorithmProvider(&algorithm,BCRYPT_SHA256_ALGORITHM,nullptr,0)==0,"snapshot-hash-provider");
 BYTE digest[32]{};require(BCryptHash(algorithm,nullptr,0,const_cast<PUCHAR>(bytes),static_cast<ULONG>(size),digest,sizeof(digest))==0,"snapshot-hash-query");
 constexpr char digits[]="0123456789abcdef";std::string result;for(BYTE byte:digest){result.push_back(digits[byte>>4]);result.push_back(digits[byte&15]);}return result;
}
// Read-only snapshot of only the owned subtrees: key paths, subkey names and value
// names/types/lengths with a SHA-256 of the data. Value data itself is never recorded.
std::string localSnapshotName(const std::wstring& value){return value.empty()?std::string():localUtf8(value);} // Default values have empty names.
void localSnapshotKey(HKEY hive,const std::wstring& path,REGSAM view,const char* hiveName,const char* viewName,unsigned depth,unsigned& budget,json& entries){
 require(depth<=8&&budget++<256,"snapshot-bound");
 Key key;const LSTATUS opened=RegOpenKeyExW(hive,path.c_str(),0,KEY_READ|view,&key.value);
 if(opened==ERROR_FILE_NOT_FOUND||opened==ERROR_PATH_NOT_FOUND)return;
 check(HRESULT_FROM_WIN32(opened),"snapshot-open");
 json entry={{"hive",hiveName},{"view",viewName},{"path",localUtf8(path)},{"subkeys",json::array()},{"values",json::array()}};
 for(DWORD index=0;;++index){
  wchar_t name[16384]{};DWORD nameCount=16384,type=0,bytes=0;
  LSTATUS status=RegEnumValueW(key.value,index,name,&nameCount,nullptr,&type,nullptr,&bytes);
  if(status==ERROR_NO_MORE_ITEMS)break;
  check(HRESULT_FROM_WIN32(status),"snapshot-value-enumerate");require(bytes<=1048576,"snapshot-value-bound");
  std::vector<BYTE> data(bytes);nameCount=16384;
  check(HRESULT_FROM_WIN32(RegEnumValueW(key.value,index,name,&nameCount,nullptr,&type,data.data(),&bytes)),"snapshot-value-read");
  entry["values"].push_back({{"name",localSnapshotName(std::wstring(name,nameCount))},{"type",type},{"bytes",bytes},{"sha256",localSha256Hex(data.data(),bytes)}});
 }
 std::vector<std::wstring> children;
 for(DWORD index=0;;++index){
  wchar_t name[256]{};DWORD count=256;
  const LSTATUS status=RegEnumKeyExW(key.value,index,name,&count,nullptr,nullptr,nullptr,nullptr);
  if(status==ERROR_NO_MORE_ITEMS)break;
  check(HRESULT_FROM_WIN32(status),"snapshot-key-enumerate");children.emplace_back(name,count);entry["subkeys"].push_back(localSnapshotName(std::wstring(name,count)));
 }
 entries.push_back(entry);
 for(const auto& child:children)localSnapshotKey(hive,path+L"\\"+child,view,hiveName,viewName,depth+1,budget,entries);
}
json localResidueSnapshot(){
 json entries=json::array();unsigned budget=0;
 for(HKEY hive:{HKEY_LOCAL_MACHINE,HKEY_CURRENT_USER})for(REGSAM view:{KEY_WOW64_32KEY,KEY_WOW64_64KEY}){
  const char* hiveName=hive==HKEY_LOCAL_MACHINE?"HKLM":"HKCU";const char* viewName=view==KEY_WOW64_64KEY?"64":"32";
  localSnapshotKey(hive,localTipPath(),view,hiveName,viewName,0,budget,entries);
 }
 localSnapshotKey(HKEY_LOCAL_MACHINE,L"SOFTWARE\\Classes\\CLSID\\"+guid(CLSID_YimeTextServiceExperiment),KEY_WOW64_64KEY,"HKLM","64",0,budget,entries);
 return entries;
}
