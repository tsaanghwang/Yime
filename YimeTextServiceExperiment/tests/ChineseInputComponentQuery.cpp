// Query-only companion to a separately authorized current-user configuration step.
// Microsoft Pinyin identity: Microsoft Learn "Keyboard identifiers and input
// method editors for Windows" (windows-language-pack-default-values).
// A registered profile plus a system binary is NOT signature or usability proof.
#include <windows.h>
#include <msctf.h>
#include <wrl/client.h>
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>
#include <nlohmann/json.hpp>
using Microsoft::WRL::ComPtr;
using nlohmann::json;
namespace {
constexpr GUID pinyinClsid={0x81d4e9c9,0x1d3b,0x41bc,{0x9e,0x6c,0x4b,0x40,0xbf,0x79,0xe3,0x5e}};
constexpr GUID pinyinProfile={0xfa550b04,0x5ad7,0x411f,{0xa5,0xac,0xca,0x03,0x8e,0xc5,0x15,0xd7}};
constexpr wchar_t clsidPath[]=L"SOFTWARE\\Classes\\CLSID\\{81D4E9C9-1D3B-41BC-9E6C-4B40BF79E35E}";
constexpr char tip[]="0804:{81D4E9C9-1D3B-41BC-9E6C-4B40BF79E35E}{FA550B04-5AD7-411F-A5AC-CA038EC515D7}";
struct Failure{const char* stage;HRESULT code;};
void check(HRESULT code,const char* stage){if(code!=S_OK)throw Failure{stage,code};}
void require(bool value,const char* stage){if(!value)throw Failure{stage,E_FAIL};}
struct Key{HKEY value=nullptr;~Key(){if(value)RegCloseKey(value);}};
struct File{HANDLE value=INVALID_HANDLE_VALUE;~File(){if(value!=INVALID_HANDLE_VALUE)CloseHandle(value);}};
std::string utf8(const std::wstring& value){
 const int size=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),nullptr,0,nullptr,nullptr);
 require(size>0 && size<=32768,"binary-path-encoding");std::string text(size,'\0');
 require(WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),text.data(),size,nullptr,nullptr)==size,"binary-path-encoding");return text;
}
std::wstring finalPath(HANDLE file){
 std::vector<wchar_t> text(32768);DWORD count=GetFinalPathNameByHandleW(file,text.data(),static_cast<DWORD>(text.size()),FILE_NAME_NORMALIZED|VOLUME_NAME_DOS);
 require(count>0 && count<text.size(),"binary-final-path-query");std::wstring value(text.data(),count);
 require(value.size()>7 && value.compare(0,4,L"\\\\?\\")==0 && value[5]==L':' && value[6]==L'\\',"binary-local-dos-path");return value.substr(4);
}
void query(json& result){
 USHORT process=0,native=0;require(IsWow64Process2(GetCurrentProcess(),&process,&native) && process==IMAGE_FILE_MACHINE_UNKNOWN && native==IMAGE_FILE_MACHINE_AMD64,"native-x64-required");
 HKL current=GetKeyboardLayout(0);require(current!=nullptr,"current-hkl-query");
 result["actualHkl"]=static_cast<std::uint64_t>(reinterpret_cast<ULONG_PTR>(current));
 result["actualHklLanguageHint"]=LOWORD(reinterpret_cast<ULONG_PTR>(current));
 ComPtr<ITfInputProcessorProfileMgr> profiles;
 check(CoCreateInstance(CLSID_TF_InputProcessorProfiles,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&profiles)),"profile-query-object");
 ComPtr<ITfInputProcessorProfiles> languages;check(profiles.As(&languages),"language-query-interface");
 LANGID currentLanguage=0;check(languages->GetCurrentLanguage(&currentLanguage),"current-language-query");result["actualTsfLanguage"]=currentLanguage;
 TF_INPUTPROCESSORPROFILE profile{};
 check(profiles->GetProfile(TF_PROFILETYPE_INPUTPROCESSOR,0x0804,pinyinClsid,pinyinProfile,nullptr,&profile),"registered-microsoft-pinyin-profile-query");
 require(profile.dwProfileType==TF_PROFILETYPE_INPUTPROCESSOR && profile.langid==0x0804 && IsEqualGUID(profile.clsid,pinyinClsid) && IsEqualGUID(profile.guidProfile,pinyinProfile) && IsEqualGUID(profile.catid,GUID_TFCAT_TIP_KEYBOARD),"registered-profile-identity-mismatch");
 result["profileRegistered"]=true;result["profileEnabled"]=(profile.dwFlags&TF_IPP_FLAG_ENABLED)!=0;result["profileActive"]=(profile.dwFlags&TF_IPP_FLAG_ACTIVE)!=0;
 // HKCR merging must not redirect the known system identity to per-user code.
 for(REGSAM view:{KEY_WOW64_32KEY,KEY_WOW64_64KEY}){
  Key key;LSTATUS status=RegOpenKeyExW(HKEY_CURRENT_USER,clsidPath,0,KEY_READ|view,&key.value);
  if(status==ERROR_FILE_NOT_FOUND||status==ERROR_PATH_NOT_FOUND)continue;
  if(status==ERROR_SUCCESS)throw Failure{"per-user-com-override-present",E_FAIL};
  check(HRESULT_FROM_WIN32(status),"per-user-com-override-query");
 }
 Key server;const std::wstring path=std::wstring(clsidPath)+L"\\InprocServer32";
 check(HRESULT_FROM_WIN32(RegOpenKeyExW(HKEY_LOCAL_MACHINE,path.c_str(),0,KEY_READ|KEY_WOW64_64KEY,&server.value)),"system-com-server-query");
 DWORD type=0,bytes=0;check(HRESULT_FROM_WIN32(RegQueryValueExW(server.value,nullptr,nullptr,&type,nullptr,&bytes)),"system-com-path-size");
 require((type==REG_SZ||type==REG_EXPAND_SZ) && bytes>=sizeof(wchar_t) && bytes<=65536 && bytes%sizeof(wchar_t)==0,"system-com-path-type");
 std::wstring binary(bytes/sizeof(wchar_t),L'\0');const DWORD originalType=type;
 check(HRESULT_FROM_WIN32(RegQueryValueExW(server.value,nullptr,nullptr,&type,reinterpret_cast<BYTE*>(binary.data()),&bytes)),"system-com-path-read");
 require(type==originalType && bytes==binary.size()*sizeof(wchar_t) && binary.back()==L'\0',"system-com-path-shape");binary.pop_back();
 require(binary.find(L'\0')==std::wstring::npos && !binary.empty(),"system-com-path-shape");
 if(type==REG_EXPAND_SZ){std::vector<wchar_t> expanded(32768);DWORD count=ExpandEnvironmentStringsW(binary.c_str(),expanded.data(),static_cast<DWORD>(expanded.size()));require(count>1 && count<=expanded.size(),"system-com-path-expansion");binary.assign(expanded.data(),count-1);}
 // Reject remote/relative/device paths before opening any registered binary.
 std::vector<wchar_t> directory(32768);UINT count=GetSystemDirectoryW(directory.data(),static_cast<UINT>(directory.size()));require(count>0 && count<directory.size(),"system-directory-query");
 const std::wstring lexicalRoot=std::wstring(directory.data(),count)+L"\\";
 require(binary.size()>lexicalRoot.size() && _wcsnicmp(binary.c_str(),lexicalRoot.c_str(),lexicalRoot.size())==0 &&
         binary.find(L"\\..\\")==std::wstring::npos && binary.find(L"\\.\\")==std::wstring::npos && binary.find(L'/')==std::wstring::npos,
         "com-binary-not-local-system-path");
 File file;file.value=CreateFileW(binary.c_str(),FILE_READ_ATTRIBUTES,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
 require(file.value!=INVALID_HANDLE_VALUE,"system-com-binary-unavailable");
 BY_HANDLE_FILE_INFORMATION info{};require(GetFileInformationByHandle(file.value,&info)!=FALSE && !(info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY),"system-com-binary-not-file");
 const auto resolved=finalPath(file.value);
 File system;system.value=CreateFileW(directory.data(),FILE_READ_ATTRIBUTES,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS,nullptr);
 require(system.value!=INVALID_HANDLE_VALUE,"system-directory-open");const auto root=finalPath(system.value)+L"\\";
 require(resolved.size()>root.size() && _wcsnicmp(resolved.c_str(),root.c_str(),root.size())==0,"com-binary-not-native-system-path");
 result["componentBinaryPath"]=utf8(resolved);result["componentBinaryPresent"]=true;
}
}
int wmain(int argc,wchar_t**){
 json result={{"schema","chinese-input-component-query-v1"},{"scope","readonly-component-and-language"},{"status","blocked"},{"stage","arguments"},{"code",static_cast<unsigned long>(E_INVALIDARG)},
  {"actualHkl",nullptr},{"actualHklLanguageHint",nullptr},{"actualTsfLanguage",nullptr},{"profileRegistered",false},{"profileEnabled",nullptr},{"profileActive",nullptr},
  {"componentBinaryPath",nullptr},{"componentBinaryPresent",false},{"registrationView","native-x64"},{"expectedTip",tip}};
 if(argc!=1){std::cout<<result.dump()<<std::endl;return 3;}
 HRESULT initialized=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
 if(FAILED(initialized)){result["stage"]="com-initialize";result["code"]=static_cast<unsigned long>(initialized);std::cout<<result.dump()<<std::endl;return 3;}
 int exit=3;
 try{query(result);result["status"]="complete";result["stage"]="completed";result["code"]=0;exit=0;}
 catch(const Failure& failure){result["stage"]=failure.stage;result["code"]=static_cast<unsigned long>(failure.code);}
 catch(...){result["stage"]="unclassified-query-exception";result["code"]=static_cast<unsigned long>(E_FAIL);}
 CoUninitialize();std::cout<<result.dump()<<std::endl;return exit;
}
