#pragma once
// Installed-file consistency proof, NOT signature/publisher or hostile-admin authentication.
// No registry writes, DLL loading, repair, backup, or recovery actions.
#include <windows.h>
#include <bcrypt.h>
#include "Installed18uArchitecture.h"
#include <nlohmann/json.hpp>
#include <algorithm>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <iostream>
#include <set>
#include <string>
#include <vector>
namespace yime18uinstallation {
namespace detail {
using Json=nlohmann::json;
struct Error { HRESULT code; };
inline void Need(bool condition) { if(!condition) throw Error{E_INVALIDARG}; }
inline void Win(bool condition) { if(!condition) {const DWORD error=GetLastError();throw Error{error?HRESULT_FROM_WIN32(error):E_FAIL};} }
inline void Crypto(NTSTATUS status) { if(status<0) throw Error{static_cast<HRESULT>(status|0x10000000L)}; }
inline bool Hex(const std::string& value,size_t size) {
    return value.size()==size && std::all_of(value.begin(),value.end(),[](unsigned char c){return (c>='0'&&c<='9')||(c>='a'&&c<='f');});
}
inline void PlainPath(const std::filesystem::path& path) {
    const auto text=path.native();
    Need(text.size()>3 && ((text[0]>=L'A'&&text[0]<=L'Z')||(text[0]>=L'a'&&text[0]<=L'z')) && text[1]==L':' && text[2]==L'\\');
    Need(text.find(L':',2)==std::wstring::npos && text.find(L'\0')==std::wstring::npos);
    Need(path.lexically_normal()==path);
    for(auto part=path; !part.empty(); part=part.parent_path()) {
        const DWORD attributes=GetFileAttributesW(part.c_str());
        Win(attributes!=INVALID_FILE_ATTRIBUTES);
        Need(!(attributes&FILE_ATTRIBUTE_REPARSE_POINT));
        if(part==part.root_path()) break;
    }
}
struct File {
    HANDLE handle=INVALID_HANDLE_VALUE;
    uint64_t bytes=0;
    explicit File(const std::filesystem::path& path,uint64_t limit) {
        PlainPath(path);
        handle=CreateFileW(path.c_str(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
        Win(handle!=INVALID_HANDLE_VALUE);
        // Any validation failure after opening must release the handle as construction throws.
        BY_HANDLE_FILE_INFORMATION info{};
        if(!GetFileInformationByHandle(handle,&info)) { const auto error=GetLastError(); CloseHandle(handle);handle=INVALID_HANDLE_VALUE;throw Error{error?HRESULT_FROM_WIN32(error):E_FAIL}; }
        bytes=(static_cast<uint64_t>(info.nFileSizeHigh)<<32)|info.nFileSizeLow;
        if((info.dwFileAttributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT))||bytes>limit) {
            CloseHandle(handle);handle=INVALID_HANDLE_VALUE;throw Error{E_INVALIDARG};
        }
    }
    File(const File&)=delete;
    File& operator=(const File&)=delete;
    ~File(){if(handle!=INVALID_HANDLE_VALUE)CloseHandle(handle);}
    std::vector<BYTE> Read() {
        Need(bytes<=2*1024*1024);
        LARGE_INTEGER zero{};Win(SetFilePointerEx(handle,zero,nullptr,FILE_BEGIN));
        std::vector<BYTE> data(static_cast<size_t>(bytes));
        DWORD got=0;
        if(!data.empty()) {Win(ReadFile(handle,data.data(),static_cast<DWORD>(data.size()),&got,nullptr));Need(got==data.size());}
        return data;
    }
};
inline std::string Hash(File& file) {
    BCRYPT_ALG_HANDLE algorithm=nullptr;BCRYPT_HASH_HANDLE hash=nullptr;
    std::vector<BYTE> object; // Must outlive BCryptDestroyHash, including failures.
    struct Cleanup {BCRYPT_ALG_HANDLE& a;BCRYPT_HASH_HANDLE& h;~Cleanup(){if(h)BCryptDestroyHash(h);if(a)BCryptCloseAlgorithmProvider(a,0);}} cleanup{algorithm,hash};
    Crypto(BCryptOpenAlgorithmProvider(&algorithm,BCRYPT_SHA256_ALGORITHM,nullptr,0));
    DWORD objectSize=0,returned=0;
    Crypto(BCryptGetProperty(algorithm,BCRYPT_OBJECT_LENGTH,reinterpret_cast<PUCHAR>(&objectSize),sizeof(objectSize),&returned,0));
    Need(returned==sizeof(objectSize)&&objectSize>0&&objectSize<=1024*1024);object.resize(objectSize);
    Crypto(BCryptCreateHash(algorithm,&hash,object.data(),objectSize,nullptr,0,0));
    LARGE_INTEGER zero{};Win(SetFilePointerEx(file.handle,zero,nullptr,FILE_BEGIN));
    BYTE buffer[65536]{};uint64_t total=0;
    for(;;){DWORD got=0;Win(ReadFile(file.handle,buffer,sizeof(buffer),&got,nullptr));if(!got)break;total+=got;Need(total<=file.bytes);Crypto(BCryptHashData(hash,buffer,got,0));}
    Need(total==file.bytes);BYTE digest[32]{};Crypto(BCryptFinishHash(hash,digest,sizeof(digest),0));
    static constexpr char hex[]="0123456789abcdef";std::string result;result.reserve(64);
    for(BYTE value:digest){result.push_back(hex[value>>4]);result.push_back(hex[value&15]);}return result;
}
inline Json Parse(File& file) {
    auto raw=file.Read();Need(!raw.empty());
    std::vector<std::set<std::string>> objects;
    auto callback=[&](int depth,Json::parse_event_t event,Json& parsed){
        Need(depth>=0&&depth<=32);
        if(event==Json::parse_event_t::object_start)objects.emplace_back();
        else if(event==Json::parse_event_t::key){Need(!objects.empty());Need(objects.back().insert(parsed.get<std::string>()).second);}
        else if(event==Json::parse_event_t::object_end){Need(!objects.empty());objects.pop_back();}
        return true;
    };
    auto value=Json::parse(raw.begin(),raw.end(),callback,true,false);Need(value.is_object()&&objects.empty());return value;
}
inline std::string String(const Json& object,const char* key) {
    Need(object.is_object()&&object.contains(key)&&object.at(key).is_string());
    auto value=object.at(key).get<std::string>();Need(value.find('\0')==std::string::npos);return value;
}
inline bool MemberPath(const std::string& path) {
    if(path.empty()||path.size()>512||path.front()=='/'||path.back()=='/')return false;
    size_t start=0;
    for(size_t i=0;i<=path.size();++i){
        if(i<path.size()){const auto c=static_cast<unsigned char>(path[i]);if(c<32||c==127||c=='\\'||c==':'||c=='*'||c=='?'||c=='"'||c=='<'||c=='>'||c=='|')return false;}
        if(i==path.size()||path[i]=='/'){const auto part=path.substr(start,i-start);if(part.empty()||part=="."||part==".."||part.back()=='.'||part.back()==' ')return false;start=i+1;}
    }
    return true;
}
struct Row {uint64_t bytes;std::string sha;};
inline Row Find(const Json& document,const char* wanted) {
    Need(document.contains("files")&&document.at("files").is_array());
    const auto& rows=document.at("files");Need(!rows.empty()&&rows.size()<=256);
    std::set<std::string> names;bool found=false;Row selected{};
    for(const auto& row:rows){
        const auto path=String(row,"path");Need(MemberPath(path));std::string folded=path;
        for(char& c:folded)if(c>='A'&&c<='Z')c=static_cast<char>(c-'A'+'a');
        Need(names.insert(folded).second);
        Need(row.contains("bytes")&&row.at("bytes").is_number_unsigned());
        const auto bytes=row.at("bytes").get<uint64_t>();Need(bytes<=1024ULL*1024*1024);
        const auto sha=String(row,"sha256");Need(Hex(sha,64));
        if(path==wanted){Need(!found);found=true;selected={bytes,sha};}
    }
    Need(found);return selected;
}
struct Diagnostic {
    const char* stage="path";
    bool hashAvailable=false;
    uint64_t expectedBytes=0,actualBytes=0;
    std::string expectedHash,actualHash;
    void SetHash(uint64_t expectedSize,const std::string& expected,uint64_t actualSize,const std::string& actual) {
        expectedHash=expected;actualHash=actual;expectedBytes=expectedSize;actualBytes=actualSize;hashAvailable=true;
    }
    void Emit(HRESULT code) const noexcept {
        try {
            Json record={{"kind","18u-installation-proof"},{"stage",stage},{"hresult",static_cast<uint32_t>(code)}};
            if(hashAvailable){record["expectedSHA256"]=expectedHash;record["actualSHA256"]=actualHash;record["expectedBytes"]=expectedBytes;record["actualBytes"]=actualBytes;}
            std::cerr<<record.dump()<<"\n";
        }catch(...){/* Diagnostics must not replace the original HRESULT. */}
    }
};
inline std::unique_ptr<File> VerifyImpl(const std::wstring& dll,Diagnostic& diagnostic,bool allowLegacyRemoval=false) {
    const std::filesystem::path dllPath(dll);PlainPath(dllPath);
    Need(dllPath.filename()==L"YimeTextService18u.dll"&&dllPath.parent_path().filename()==kInstalled18uDirectory);
    const auto root=dllPath.parent_path().parent_path();
    diagnostic.stage="marker";
    File markerFile(root/L".yime-product.json",2*1024*1024);
    const auto marker=Parse(markerFile);
    diagnostic.stage="maintenance-manifest";
    File manifestFile(root/L".setup"/L"product-package.json",2*1024*1024);
    const auto manifest=Parse(manifestFile);
    diagnostic.stage="descriptor-identity";
    File descriptorFile(root/L"installed-18u-product.json",2*1024*1024);
    const auto descriptor=Parse(descriptorFile);
    diagnostic.stage="marker";
    Need(String(marker,"format")=="yime-simple-install-1"&&String(marker,"product")=="yimecore-18u"&&String(marker,"target")==kInstalled18uTarget);
    const auto version=String(marker,"version");Need(!version.empty()&&version.size()<=128);
    diagnostic.stage="maintenance-manifest";
    Need(String(manifest,"format")=="yime-simple-package-18u-1"&&String(manifest,"product")=="yimecore-18u"&&String(manifest,"target")==kInstalled18uTarget&&String(manifest,"version")==version);
    Need(String(manifest,"host_architecture")==kInstalled18uHostArchitecture&&String(manifest,"tsf64_architecture")==kInstalled18uTsfArchitecture);
    diagnostic.stage="descriptor-identity";
    const auto schema=String(descriptor,"schema");
    Need(String(descriptor,"product")=="yimecore-18u");
    Need(Hex(String(descriptor,"sourceCommit"),40)&&String(descriptor,"architecture")==kInstalled18uDescriptorArchitecture);
    Need(descriptor.contains("autostart")&&descriptor.at("autostart").is_boolean());
    if(schema=="installed-18u-product-v1"){
        Need(descriptor.size()==9&&String(descriptor,"language")=="CN"&&String(descriptor,"mode")=="variable"&&!descriptor.at("autostart").get<bool>());
    }else{
        // This is the historical ARM installation descriptor, NOT Frontend v2.
        // It can authorize removal only; it cannot register or launch old input.
        Need(allowLegacyRemoval&&kInstalled18uMachine==IMAGE_FILE_MACHINE_ARM64&&schema=="installed-18u-product-v2");
        Need(descriptor.size()==10&&descriptor.at("autostart").get<bool>()&&!descriptor.contains("language")&&!descriptor.contains("mode"));
        Need(descriptor.value("languages",Json())==Json::array({"CN","EN"}));
        Need(descriptor.value("modes",Json())==Json::array({"full","variable","shorthand"}));
        Need(descriptor.value("capabilities",Json())==Json::array({"installed-tsf-frontend","composition","candidates","literal","host-editing"}));
        const auto oldFrontend=Find(descriptor,"bin/YimeTouchKeyboard.exe");
        const auto oldManifestFrontend=Find(manifest,"bin/YimeTouchKeyboard.exe");
        Need(oldFrontend.bytes==oldManifestFrontend.bytes&&oldFrontend.sha==oldManifestFrontend.sha);
        for(const auto& row:descriptor.at("files"))Need(String(row,"path").rfind("frontend/",0)!=0);
    }
    Need(descriptor.contains("identity")&&descriptor.at("identity").is_object());
    Need(String(descriptor.at("identity"),"clsid")=="{6DFACE1F-562E-4773-A9D6-D5753A314711}"&&String(descriptor.at("identity"),"profile")=="{1BD904AC-3194-4419-B70A-5574100F18B3}");
    diagnostic.stage="descriptor-hash";
    const auto descriptorRow=Find(manifest,"installed-18u-product.json");
    const auto descriptorHash=Hash(descriptorFile);
    diagnostic.SetHash(descriptorRow.bytes,descriptorRow.sha,descriptorFile.bytes,descriptorHash);
    Need(descriptorRow.bytes==descriptorFile.bytes&&descriptorRow.sha==descriptorHash);
    diagnostic.hashAvailable=false;diagnostic.stage="DLL-row-hash";
    const auto manifestDll=Find(manifest,kInstalled18uDllMember),descriptorDll=Find(descriptor,kInstalled18uDllMember);
    diagnostic.SetHash(manifestDll.bytes,manifestDll.sha,descriptorDll.bytes,descriptorDll.sha);
    Need(manifestDll.bytes==descriptorDll.bytes&&manifestDll.sha==descriptorDll.sha);
    diagnostic.hashAvailable=false;diagnostic.stage="DLL-byte-hash";
    auto verifiedDll=std::make_unique<File>(dllPath,512ULL*1024*1024);
    const auto dllHash=Hash(*verifiedDll);
    diagnostic.SetHash(manifestDll.bytes,manifestDll.sha,verifiedDll->bytes,dllHash);
    Need(verifiedDll->bytes==manifestDll.bytes&&dllHash==manifestDll.sha);
    // Keep the verified DLL read handle (no write/delete sharing) for this maintenance
    // process lifetime. Metadata consistency is not protection against a malicious owner.
    return verifiedDll;
}
} // detail
inline HRESULT Verify(const std::wstring& dll,bool allowLegacyRemoval=false) noexcept {
    detail::Diagnostic diagnostic;
    static std::unique_ptr<detail::File> heldDll;
    try{heldDll=detail::VerifyImpl(dll,diagnostic,allowLegacyRemoval);return S_OK;}
    catch(const detail::Error& error){diagnostic.Emit(error.code);return error.code;}
    catch(...){diagnostic.Emit(E_UNEXPECTED);return E_UNEXPECTED;}
}
} // yime18uinstallation
