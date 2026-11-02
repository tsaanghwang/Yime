#pragma once
// Included only by the separate 18u product target. No recovery/rollback path.
#include "ProductRegistrationPolicy.h"
#include <vector>
#include <stdexcept>
namespace {
struct ProductError { HRESULT code; };
void productRequire(HRESULT hr) { if (hr != S_OK) throw ProductError{FAILED(hr) ? hr : E_UNEXPECTED}; }
void productWin(LSTATUS s) { if (s != ERROR_SUCCESS) throw ProductError{HRESULT_FROM_WIN32(s)}; }
struct ProductKey {
    HKEY h = nullptr;
    ~ProductKey() { if (h) RegCloseKey(h); }
    ProductKey() = default;
    ProductKey(const ProductKey&) = delete;
    ProductKey& operator=(const ProductKey&) = delete;
};
std::wstring productComRoot() { return L"SOFTWARE\\Classes\\CLSID\\" + guidText(CLSID_YimeTextServiceExperiment); }
std::wstring productTipRoot() { return L"SOFTWARE\\Microsoft\\CTF\\TIP\\" + guidText(CLSID_YimeTextServiceExperiment); }
bool productExists(HKEY hive, const std::wstring& path, REGSAM view) {
    ProductKey key;
    const LSTATUS s = RegOpenKeyExW(hive, path.c_str(), 0, KEY_READ | view, &key.h);
    if (s == ERROR_FILE_NOT_FOUND || s == ERROR_PATH_NOT_FOUND) return false;
    productWin(s); return true;
}
std::wstring productString(HKEY key, const wchar_t* name) {
    DWORD type = 0, size = 0;
    productWin(RegQueryValueExW(key, name, nullptr, &type, nullptr, &size));
    if (type != REG_SZ || size < sizeof(wchar_t) || size > 65536 || size % sizeof(wchar_t)) throw ProductError{E_UNEXPECTED};
    std::vector<wchar_t> value(size / sizeof(wchar_t));
    productWin(RegQueryValueExW(key, name, nullptr, &type, reinterpret_cast<BYTE*>(value.data()), &size));
    if (type != REG_SZ || value.back() != 0 || wcslen(value.data()) + 1 != value.size()) throw ProductError{E_UNEXPECTED};
    return value.data();
}
void productShape(HKEY key, DWORD subkeys, DWORD values) {
    DWORD actualKeys = 0, actualValues = 0;
    productWin(RegQueryInfoKeyW(key, nullptr, nullptr, nullptr, &actualKeys, nullptr, nullptr,
                              &actualValues, nullptr, nullptr, nullptr, nullptr));
    if (actualKeys != subkeys || actualValues != values) throw ProductError{E_UNEXPECTED};
}
std::wstring productDll(const wchar_t* path, bool requireSibling) {
    if (!path || !*path) throw ProductError{E_INVALIDARG};
    const std::filesystem::path candidate(path);
    wchar_t own[32768]{};
    const DWORD length = GetModuleFileNameW(nullptr, own, static_cast<DWORD>(std::size(own)));
    if (!length || length >= std::size(own)) throw ProductError{E_UNEXPECTED};
    if (!candidate.is_absolute() || candidate.filename() != L"YimeTextService18u.dll") throw ProductError{E_INVALIDARG};
    // Registration binds to the sibling DLL; read-only ownership/removal may run
    // from the package maintenance copy, but must match the exact registered COM path.
    const auto normalized = candidate.lexically_normal();
    const auto expected = std::filesystem::path(own).parent_path() / L"YimeTextService18u.dll";
    if (requireSibling && _wcsicmp(normalized.c_str(), expected.c_str())) throw ProductError{E_INVALIDARG};
    return normalized.native();
}
void productNativeGate() {
    GUID clsid{}, profile{};
    productRequire(CLSIDFromString(L"{6DFACE1F-562E-4773-A9D6-D5753A314711}",&clsid));
    productRequire(CLSIDFromString(L"{1BD904AC-3194-4419-B70A-5574100F18B3}",&profile));
    if(!IsEqualGUID(clsid,CLSID_YimeTextServiceExperiment) || !IsEqualGUID(profile,GUID_YimeTextServiceExperimentProfile) || kLanguageId!=0x0804)
        throw ProductError{E_UNEXPECTED};
    USHORT process = 0, native = 0;
    if (!IsWow64Process2(GetCurrentProcess(), &process, &native) ||
        process != IMAGE_FILE_MACHINE_UNKNOWN || native != IMAGE_FILE_MACHINE_AMD64 || sizeof(void*) != 8)
        throw ProductError{HRESULT_FROM_WIN32(ERROR_NOT_SUPPORTED)};
}
unsigned productCategories() {
    ITfCategoryMgr* raw = nullptr;
    productRequire(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER,
        __uuidof(ITfCategoryMgr), reinterpret_cast<void**>(&raw)));
    struct Release { ITfCategoryMgr* p; ~Release(){p->Release();} } release{raw};
    IEnumGUID* values = nullptr;
    productRequire(raw->EnumCategoriesInItem(CLSID_YimeTextServiceExperiment, &values));
    struct EnumRelease { IEnumGUID* p; ~EnumRelease(){p->Release();} } enumRelease{values};
    unsigned count = 0; bool seen[std::size(kTipCategories)]{};
    for (;;) {
        GUID value{}; ULONG fetched = 0; const HRESULT hr = values->Next(1, &value, &fetched);
        if (hr == S_FALSE && fetched == 0) break;
        productRequire(hr); if (fetched != 1 || count >= std::size(kTipCategories)) throw ProductError{E_UNEXPECTED};
        bool known = false;
        for (size_t i=0; i<std::size(kTipCategories); ++i) if (IsEqualGUID(value,*kTipCategories[i])) {
            if (seen[i]) throw ProductError{E_UNEXPECTED};
            seen[i]=true; known=true; break;
        }
        if (!known) throw ProductError{E_UNEXPECTED};
        ++count;
    }
    return count;
}
unsigned productProfiles() {
    ITfInputProcessorProfileMgr* raw = nullptr;
    productRequire(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
        __uuidof(ITfInputProcessorProfileMgr), reinterpret_cast<void**>(&raw)));
    struct Release { ITfInputProcessorProfileMgr* p; ~Release(){p->Release();} } release{raw};
    IEnumTfInputProcessorProfiles* values = nullptr;
    // Official EnumProfiles contract: language zero enumerates all languages.
    productRequire(raw->EnumProfiles(0, &values));
    struct EnumRelease { IEnumTfInputProcessorProfiles* p; ~EnumRelease(){p->Release();} } enumRelease{values};
    unsigned count = 0;
    for (unsigned j=0;; ++j) {
        TF_INPUTPROCESSORPROFILE p{}; ULONG fetched=0; const HRESULT hr=values->Next(1,&p,&fetched);
        if (hr==S_FALSE && fetched==0) break;
        productRequire(hr); if (fetched!=1 || j>=4096) throw ProductError{E_UNEXPECTED};
        if (IsEqualGUID(p.clsid, CLSID_YimeTextServiceExperiment)) {
            if (p.dwProfileType!=TF_PROFILETYPE_INPUTPROCESSOR || p.langid!=kLanguageId ||
                !IsEqualGUID(p.guidProfile,GUID_YimeTextServiceExperimentProfile) || ++count>1)
                throw ProductError{E_UNEXPECTED};
        }
    }
    return count;
}
struct ProductState { bool com=false, tip=false; unsigned categories=0, profiles=0; };
ProductState productState() {
    ProductState s;
    for (HKEY hive : {HKEY_LOCAL_MACHINE,HKEY_CURRENT_USER}) for (REGSAM view : {KEY_WOW64_64KEY,KEY_WOW64_32KEY}) {
        s.com = productExists(hive,productComRoot(),view) || s.com;
        s.tip = productExists(hive,productTipRoot(),view) || s.tip;
    }
    s.categories=productCategories(); s.profiles=productProfiles();
    s.tip = s.tip || s.profiles != 0; return s;
}

void productOnlyChildren(HKEY hive, REGSAM view, const std::wstring& path,
                         std::initializer_list<const wchar_t*> allowed) {
    ProductKey key;
    const LSTATUS opened=RegOpenKeyExW(hive,path.c_str(),0,KEY_READ|view,&key.h);
    if(opened==ERROR_FILE_NOT_FOUND || opened==ERROR_PATH_NOT_FOUND) return;
    productWin(opened);
    for(DWORD index=0;;++index) {
        wchar_t name[256]{}; DWORD size=static_cast<DWORD>(std::size(name));
        const LSTATUS next=RegEnumKeyExW(key.h,index,name,&size,nullptr,nullptr,nullptr,nullptr);
        if(next==ERROR_NO_MORE_ITEMS) break;
        productWin(next); if(index>=16) throw ProductError{E_UNEXPECTED};
        bool known=false; for(const auto expected:allowed) if(!_wcsicmp(name,expected)) known=true;
        if(!known) throw ProductError{E_UNEXPECTED};
    }
}

void productCategoryLeaves(HKEY hive, REGSAM view, const std::wstring& path,
                           unsigned depth, std::vector<std::wstring>& leaves) {
    if(depth>6 || leaves.size()>64) throw ProductError{E_UNEXPECTED};
    ProductKey key; const LSTATUS opened=RegOpenKeyExW(hive,path.c_str(),0,KEY_READ|view,&key.h);
    if(opened==ERROR_FILE_NOT_FOUND || opened==ERROR_PATH_NOT_FOUND) return;
    productWin(opened);
    DWORD values=0; productWin(RegQueryInfoKeyW(key.h,nullptr,nullptr,nullptr,nullptr,nullptr,nullptr,&values,nullptr,nullptr,nullptr,nullptr));
    if(values!=0) throw ProductError{E_UNEXPECTED};
    const auto own=guidText(CLSID_YimeTextServiceExperiment);
    for(DWORD index=0;;++index) {
        wchar_t name[256]{}; DWORD length=static_cast<DWORD>(std::size(name));
        const LSTATUS next=RegEnumKeyExW(key.h,index,name,&length,nullptr,nullptr,nullptr,nullptr);
        if(next==ERROR_NO_MORE_ITEMS) break;
        productWin(next); if(index>=16) throw ProductError{E_UNEXPECTED};
        bool allowed=!_wcsicmp(name,L"Category") || !_wcsicmp(name,L"Item") || !_wcsicmp(name,own.c_str());
        for(const GUID* category:kTipCategories) if(!_wcsicmp(name,guidText(*category).c_str())) allowed=true;
        if(!allowed) throw ProductError{E_UNEXPECTED};
        productCategoryLeaves(hive,view,path+L"\\"+name,depth+1,leaves);
    }
    if(leaves.size()>=64) throw ProductError{E_UNEXPECTED};
    leaves.push_back(path); // Read-only bounded postorder observation, never recursive delete.
}
void productLanguageShape() {
    const auto root=productTipRoot(), languages=root+L"\\LanguageProfile", language=languages+L"\\0x00000804";
    const auto profile=guidText(GUID_YimeTextServiceExperimentProfile);
    for(HKEY hive:{HKEY_LOCAL_MACHINE,HKEY_CURRENT_USER}) for(REGSAM view:{KEY_WOW64_64KEY,KEY_WOW64_32KEY}) {
        productOnlyChildren(hive,view,root,{L"LanguageProfile",L"Category"});
        std::vector<std::wstring> categories;
        productCategoryLeaves(hive,view,root+L"\\Category",0,categories);
        productOnlyChildren(hive,view,languages,{L"0x00000804"});
        productOnlyChildren(hive,view,language,{profile.c_str()});
        productOnlyChildren(hive,view,language+L"\\"+profile,{});
    }
}
void productOwned(const std::wstring& dll) {
    // No HKCU COM shadow, no alternate architecture installation for this x64 product.
    if (productExists(HKEY_CURRENT_USER,productComRoot(),KEY_WOW64_64KEY) ||
        productExists(HKEY_CURRENT_USER,productComRoot(),KEY_WOW64_32KEY) ||
        productExists(HKEY_LOCAL_MACHINE,productComRoot(),KEY_WOW64_32KEY)) throw ProductError{E_UNEXPECTED};
    ProductKey root, server;
    productWin(RegOpenKeyExW(HKEY_LOCAL_MACHINE,productComRoot().c_str(),0,KEY_READ|KEY_WOW64_64KEY,&root.h));
    productShape(root.h,1,0);
    productWin(RegOpenKeyExW(root.h,L"InprocServer32",0,KEY_READ,&server.h));
    productShape(server.h,0,2);
    if (_wcsicmp(productString(server.h,nullptr).c_str(),dll.c_str()) || productString(server.h,L"ThreadingModel")!=L"Apartment")
        throw ProductError{E_UNEXPECTED};
    // Enumerate all languages/categories for this identity: foreign additions fail closed.
    productLanguageShape();
    if (productProfiles()!=1 || productCategories()!=std::size(kTipCategories)) throw ProductError{E_UNEXPECTED};
}

struct ProductDllReadLock {
    HANDLE file=INVALID_HANDLE_VALUE;
    ~ProductDllReadLock(){ if(file!=INVALID_HANDLE_VALUE) CloseHandle(file); }
    void open(const std::wstring& path) {
        const DWORD attributes=GetFileAttributesW(path.c_str());
        if(attributes==INVALID_FILE_ATTRIBUTES || (attributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT)))
            throw ProductError{E_INVALIDARG};
        file=CreateFileW(path.c_str(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
        if(file==INVALID_HANDLE_VALUE) throw ProductError{HRESULT_FROM_WIN32(GetLastError())};
        IMAGE_DOS_HEADER dos{}; DWORD read=0;
        if(!ReadFile(file,&dos,sizeof(dos),&read,nullptr) || read!=sizeof(dos) || dos.e_magic!=IMAGE_DOS_SIGNATURE || dos.e_lfanew<static_cast<LONG>(sizeof(dos)) || dos.e_lfanew>1048576)
            throw ProductError{E_INVALIDARG};
        LARGE_INTEGER offset{}; offset.QuadPart=dos.e_lfanew;
        IMAGE_NT_HEADERS64 nt{};
        if(!SetFilePointerEx(file,offset,nullptr,FILE_BEGIN) || !ReadFile(file,&nt,sizeof(nt),&read,nullptr) || read!=sizeof(nt) ||
           nt.Signature!=IMAGE_NT_SIGNATURE || nt.FileHeader.Machine!=IMAGE_FILE_MACHINE_AMD64 ||
           !(nt.FileHeader.Characteristics&IMAGE_FILE_DLL) || nt.OptionalHeader.Magic!=IMAGE_NT_OPTIONAL_HDR64_MAGIC)
            throw ProductError{E_INVALIDARG};
        // This verifies architecture/shape, not publisher identity. Setup verifies manifest/hash.
    }
};
void productCreateCom(const std::wstring& dll) {
    if (!std::filesystem::is_regular_file(dll) ||
        !std::filesystem::is_regular_file(std::filesystem::path(dll).parent_path().parent_path()/L"profile-icon.ico"))
        throw ProductError{HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND)};
    ProductKey root, server; DWORD disposition=0;
    productWin(RegCreateKeyExW(HKEY_LOCAL_MACHINE,productComRoot().c_str(),0,nullptr,0,
        KEY_READ|KEY_WRITE|KEY_WOW64_64KEY,nullptr,&root.h,&disposition));
    if (disposition!=REG_CREATED_NEW_KEY) throw ProductError{HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS)};
    // Any later failure is reported with its new records preserved; never automatic rollback.
    productWin(RegCreateKeyExW(root.h,L"InprocServer32",0,nullptr,0,KEY_WRITE,nullptr,&server.h,&disposition));
    if (disposition!=REG_CREATED_NEW_KEY) throw ProductError{E_UNEXPECTED};
    productWin(RegSetValueExW(server.h,nullptr,0,REG_SZ,reinterpret_cast<const BYTE*>(dll.c_str()),static_cast<DWORD>((dll.size()+1)*sizeof(wchar_t))));
    constexpr wchar_t apartment[]=L"Apartment";
    productWin(RegSetValueExW(server.h,L"ThreadingModel",0,REG_SZ,reinterpret_cast<const BYTE*>(apartment),sizeof(apartment)));
}

void productRemoveResidueLeaf(HKEY hive, REGSAM view, const std::wstring& path, bool profileLeaf) {
    ProductKey key;
    const LSTATUS opened=RegOpenKeyExW(hive,path.c_str(),0,KEY_READ|view,&key.h);
    if(opened==ERROR_FILE_NOT_FOUND || opened==ERROR_PATH_NOT_FOUND) return;
    productWin(opened);
    DWORD subkeys=0,values=0;
    productWin(RegQueryInfoKeyW(key.h,nullptr,nullptr,nullptr,&subkeys,nullptr,nullptr,&values,nullptr,nullptr,nullptr,nullptr));
    bool enableZero=false;
    if(profileLeaf && values==1) {
        DWORD type=0,bytes=sizeof(DWORD),enable=1;
        const LSTATUS queried=RegQueryValueExW(key.h,L"Enable",nullptr,&type,reinterpret_cast<BYTE*>(&enable),&bytes);
        enableZero=queried==ERROR_SUCCESS && type==REG_DWORD && bytes==sizeof(DWORD) && enable==0;
    }
    if(!yime18ureg::RemovableResidue(subkeys,values,profileLeaf,enableZero)) throw ProductError{E_UNEXPECTED};
    // A concurrent added child makes this nonrecursive delete fail. A value-only race
    // remains possible; this maintenance command is not a concurrent installer protocol.
    RegCloseKey(key.h); key.h=nullptr;
    productWin(RegDeleteKeyExW(hive,path.c_str(),view,0));
}
void productRemoveResidue() {
    const auto root=productTipRoot();
    const auto languages=root+L"\\LanguageProfile";
    const auto language=languages+L"\\0x00000804";
    const auto profile=language+L"\\"+guidText(GUID_YimeTextServiceExperimentProfile);
    for(HKEY hive : {HKEY_LOCAL_MACHINE,HKEY_CURRENT_USER}) for(REGSAM view : {KEY_WOW64_64KEY,KEY_WOW64_32KEY}) {
        productRemoveResidueLeaf(hive,view,profile,true);
        productRemoveResidueLeaf(hive,view,language,false);
        productRemoveResidueLeaf(hive,view,languages,false);
        std::vector<std::wstring> categories;
        productCategoryLeaves(hive,view,root+L"\\Category",0,categories);
        for(const auto& path:categories) productRemoveResidueLeaf(hive,view,path,false);
        productRemoveResidueLeaf(hive,view,root,false);
    }
}
void productRemove(const std::wstring& dll) {
    productOwned(dll);
    // Existing API helper targets only the fixed profile and category list.
    const HRESULT hr=unregisterProfileAndCategories();
    productRequire(hr); // On failure preserve COM, with no broad fallback.
    if (!yime18ureg::CanRemoveCom(true,hr==S_OK,productCategories()==0,productProfiles()==0)) throw ProductError{E_UNEXPECTED};
    productRemoveResidue(); // Same invocation, only after owned/API checks; failure preserves COM.
    // Recheck exact COM shape after API calls, without requiring the now-removed profile.
    ProductKey root, server;
    productWin(RegOpenKeyExW(HKEY_LOCAL_MACHINE,productComRoot().c_str(),0,KEY_READ|KEY_WRITE|KEY_WOW64_64KEY,&root.h));
    productShape(root.h,1,0);
    productWin(RegOpenKeyExW(root.h,L"InprocServer32",0,KEY_READ,&server.h)); productShape(server.h,0,2);
    if (_wcsicmp(productString(server.h,nullptr).c_str(),dll.c_str()) || productString(server.h,L"ThreadingModel")!=L"Apartment") throw ProductError{E_UNEXPECTED};
    RegCloseKey(server.h); server.h=nullptr;
    productWin(RegDeleteKeyExW(root.h,L"InprocServer32",KEY_WOW64_64KEY,0));
    RegCloseKey(root.h); root.h=nullptr;
    productWin(RegDeleteKeyExW(HKEY_LOCAL_MACHINE,productComRoot().c_str(),KEY_WOW64_64KEY,0));
    const auto state=productState();
    if (!yime18ureg::CanRegister(true,state.com,state.tip,state.categories)) throw ProductError{HRESULT_FROM_WIN32(ERROR_DIR_NOT_EMPTY)};
}
}
int wmain(int argc,wchar_t** argv) {
    const auto operation=yime18ureg::Parse(argc,argc>1?argv[1]:nullptr);
    if (operation==yime18ureg::Operation::Invalid) return 2;
    HRESULT result=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
    if (FAILED(result)) { writeResult(L"initialize",result); return 2; }
    int code=0;
    try {
        productNativeGate();
        if (operation==yime18ureg::Operation::Status || operation==yime18ureg::Operation::VerifyAbsent) {
            const auto s=productState();
            std::wcout<<L"tool_version=yime-18u-product-registration-v1\nmutation_performed=false\ncom_registered="<<(s.com?L"true":L"false")
                <<L"\ntip_registered="<<(s.tip?L"true":L"false")<<L"\nprofile_count="<<s.profiles<<L"\ncategories_registered_count="<<s.categories<<L"\n";
            if(productExists(HKEY_LOCAL_MACHINE,productComRoot()+L"\\InprocServer32",KEY_WOW64_64KEY)) {
                ProductKey key; productWin(RegOpenKeyExW(HKEY_LOCAL_MACHINE,(productComRoot()+L"\\InprocServer32").c_str(),0,KEY_READ|KEY_WOW64_64KEY,&key.h));
                std::wcout<<L"com_path="<<productString(key.h,nullptr)<<L"\n";
            } else std::wcout<<L"com_path=\n";
            if(operation==yime18ureg::Operation::VerifyAbsent && !yime18ureg::CanRegister(true,s.com,s.tip,s.categories)) code=4;
        } else {
            const auto dll=productDll(argv[2],operation==yime18ureg::Operation::Register);
            if (operation==yime18ureg::Operation::CheckOwned) { productOwned(dll); std::wcout<<L"owned=true\nmutation_performed=false\ncom_path="<<dll<<L"\n"; }
            else {
                if(!isElevated()) throw ProductError{E_ACCESSDENIED};
                if(operation==yime18ureg::Operation::Register) {
                    const auto s=productState();
                    if(!yime18ureg::CanRegister(true,s.com,s.tip,s.categories)) throw ProductError{HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS)};
                    ProductDllReadLock lock; lock.open(dll);
                    productCreateCom(dll); productRequire(registerProfileAndCategories(dll.c_str())); productOwned(dll);
                } else productRemove(dll);
                writeResult(argv[1],S_OK);
            }
        }
    } catch(const ProductError& e) { writeResult(argv[1],e.code); code=5; }
      catch(...) { writeResult(argv[1],E_UNEXPECTED); code=5; }
    CoUninitialize(); return code;
}
