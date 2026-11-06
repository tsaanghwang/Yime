#pragma once
// Included only by the separate 18u product target. No recovery/rollback path.
#include "ProductRegistrationPolicy.h"
#include "ProductInstallationProof.h"
#include <vector>
#include <stdexcept>
namespace {
struct ProductError { HRESULT code; bool foreignSnapshot=false; };
const wchar_t* productStage = L"initialization";
void productDiagnostic(const wchar_t* api, unsigned long actual, unsigned long expected) noexcept {
    try { std::wcerr << L"product_stage=" << productStage << L"; api=" << api
        << L"; actual=0x" << std::hex << actual << L"; expected=0x" << expected << std::dec << L"\n"; } catch (...) {}
}
void productLocation(HKEY hive,REGSAM view,const std::wstring& path) noexcept {
    try {std::wcerr<<L"product_stage="<<productStage<<L"; hive="<<(hive==HKEY_LOCAL_MACHINE?L"HKLM":L"HKCU")
        <<L"; view="<<(view==KEY_WOW64_64KEY?64:32)<<L"; key="<<path<<L"\n";}catch(...){}
}
void productKeyDiagnostic(HKEY hive,REGSAM view,const std::wstring& path,const wchar_t* api,
                          LSTATUS status,DWORD subkeys=0,DWORD values=0) noexcept {
    productLocation(hive,view,path);
    try {std::wcerr<<L"registry_api="<<api<<L"; win32="<<status<<L"; expected_success="<<ERROR_SUCCESS
        <<L"; missing="<<(status==ERROR_FILE_NOT_FOUND||status==ERROR_PATH_NOT_FOUND)
        <<L"; subkeys="<<subkeys<<L"; values="<<values<<L"\n";}catch(...){}
}
void productWriteResult(std::wstring_view operation,HRESULT result) noexcept {
    try {writeResult(operation,result);}catch(...){} // Reporting cannot replace the operation exit code.
}
void productRequire(HRESULT hr) {
    productDiagnostic(L"HRESULT",static_cast<unsigned long>(hr),static_cast<unsigned long>(S_OK));
    if (hr != S_OK) throw ProductError{FAILED(hr) ? hr : E_UNEXPECTED};
}
void productWin(LSTATUS s) {
    if(s!=ERROR_SUCCESS) productDiagnostic(L"Win32",static_cast<unsigned long>(s),ERROR_SUCCESS);
    if (s != ERROR_SUCCESS) throw ProductError{HRESULT_FROM_WIN32(s)};
}
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
    productKeyDiagnostic(hive,view,path,L"RegOpenKeyExW-exists",s);
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
    if (actualKeys != subkeys || actualValues != values) {
        productDiagnostic(L"registry-subkeys",actualKeys,subkeys);
        productDiagnostic(L"registry-values",actualValues,values);
        throw ProductError{E_UNEXPECTED};
    }
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
    if (!Installed18uNativeProcess(GetCurrentProcess()))
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
        productRequire(hr); if (fetched != 1 || count >= std::size(kTipCategories)) throw ProductError{E_UNEXPECTED,true};
        bool known = false;
        for (size_t i=0; i<std::size(kTipCategories); ++i) if (IsEqualGUID(value,*kTipCategories[i])) {
            if (seen[i]) throw ProductError{E_UNEXPECTED,true};
            seen[i]=true; known=true; break;
        }
        if (!known) throw ProductError{E_UNEXPECTED,true};
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
        productRequire(hr); if (fetched!=1 || j>=4096) throw ProductError{E_UNEXPECTED,true};
        if (IsEqualGUID(p.clsid, CLSID_YimeTextServiceExperiment)) {
            if (p.dwProfileType!=TF_PROFILETYPE_INPUTPROCESSOR || p.langid!=kLanguageId ||
                !IsEqualGUID(p.guidProfile,GUID_YimeTextServiceExperimentProfile) || ++count>1)
                throw ProductError{E_UNEXPECTED,true};
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

// All parent values and child names are checked; missing shared views are benign.
void productOnlyChildren(HKEY hive, REGSAM view, const std::wstring& path,
                         const std::vector<std::wstring>& allowed) {
    productLocation(hive,view,path);
    ProductKey key;
    const LSTATUS opened=RegOpenKeyExW(hive,path.c_str(),0,KEY_READ|view,&key.h);
    productKeyDiagnostic(hive,view,path,L"RegOpenKeyExW",opened);
    if(opened==ERROR_FILE_NOT_FOUND || opened==ERROR_PATH_NOT_FOUND) return;
    productWin(opened);
    DWORD values=0; productWin(RegQueryInfoKeyW(key.h,nullptr,nullptr,nullptr,nullptr,nullptr,nullptr,&values,nullptr,nullptr,nullptr,nullptr));
    if(values) {productDiagnostic(L"parent-values",values,0);throw ProductError{E_UNEXPECTED};}
    for(DWORD index=0;;++index) {
        wchar_t name[256]{}; DWORD size=static_cast<DWORD>(std::size(name));
        const LSTATUS next=RegEnumKeyExW(key.h,index,name,&size,nullptr,nullptr,nullptr,nullptr);
        if(next==ERROR_NO_MORE_ITEMS) break;
        productWin(next); if(index>=16) throw ProductError{E_UNEXPECTED};
        bool known=false; for(const auto& expected:allowed) if(!_wcsicmp(name,expected.c_str())) known=true;
        if(!known) {productDiagnostic(L"foreign-child",1,0);throw ProductError{E_UNEXPECTED};}
    }
}
DWORD productDword(HKEY key,const wchar_t* name) {
    DWORD type=0,bytes=sizeof(DWORD),value=0;
    productWin(RegQueryValueExW(key,name,nullptr,&type,reinterpret_cast<BYTE*>(&value),&bytes));
    if(type!=REG_DWORD || bytes!=sizeof(DWORD)) throw ProductError{E_UNEXPECTED};
    return value;
}
struct ProductPersistent { bool anyTip=false, machineProfile=false, completeMachineProfile=false; unsigned categoryMask=0, machinePairedMask=0; };
// Only these two directional relationships are valid, not an arbitrary tree of allowed GUIDs.
unsigned productCategoryShape(HKEY hive,REGSAM view,std::vector<std::wstring>* leaves=nullptr,unsigned* pairedMask=nullptr) {
    const auto base=productTipRoot()+L"\\Category";
    const auto own=guidText(CLSID_YimeTextServiceExperiment);
    std::vector<std::wstring> names; for(const GUID* category:kTipCategories) names.push_back(guidText(*category));
    productOnlyChildren(hive,view,base,{L"Category",L"Item"});
    productOnlyChildren(hive,view,base+L"\\Category",names);
    productOnlyChildren(hive,view,base+L"\\Item",{own});
    productOnlyChildren(hive,view,base+L"\\Item\\"+own,names);
    unsigned mask=0;
    for(size_t i=0;i<names.size();++i) {
        const auto cat=base+L"\\Category\\"+names[i], forward=cat+L"\\"+own;
        const auto reverse=base+L"\\Item\\"+own+L"\\"+names[i];
        productOnlyChildren(hive,view,cat,{own});
        productOnlyChildren(hive,view,forward,{}); productOnlyChildren(hive,view,reverse,{});
        const bool hasForward=productExists(hive,forward,view),hasReverse=productExists(hive,reverse,view);
        if(hasForward||hasReverse) mask|=1u<<i;
        if(pairedMask && hasForward && hasReverse) *pairedMask|=1u<<i;
        if(leaves) {leaves->push_back(forward);leaves->push_back(cat);leaves->push_back(reverse);}
    }
    if(leaves) {
        leaves->push_back(base+L"\\Category");leaves->push_back(base+L"\\Item\\"+own);
        leaves->push_back(base+L"\\Item");leaves->push_back(base);
    }
    return mask;
}
ProductPersistent productPersistent(const std::wstring& dll) {
    productStage=L"persistent-shape";
    ProductPersistent result;
    const auto root=productTipRoot(),languages=root+L"\\LanguageProfile",language=languages+L"\\0x00000804";
    const auto profile=guidText(GUID_YimeTextServiceExperimentProfile),leaf=language+L"\\"+profile;
    const auto icon=(std::filesystem::path(dll).parent_path().parent_path()/L"profile-icon.ico").native();
    for(HKEY hive:{HKEY_LOCAL_MACHINE,HKEY_CURRENT_USER}) for(REGSAM view:{KEY_WOW64_64KEY,KEY_WOW64_32KEY}) {
        result.anyTip=productExists(hive,root,view)||result.anyTip;
        productOnlyChildren(hive,view,root,{L"LanguageProfile",L"Category"});
        productOnlyChildren(hive,view,languages,{L"0x00000804"});
        productOnlyChildren(hive,view,language,{profile});
        unsigned paired=0;
        result.categoryMask|=productCategoryShape(hive,view,nullptr,&paired);
        if(hive==HKEY_LOCAL_MACHINE && view==KEY_WOW64_64KEY) result.machinePairedMask=paired;
        if(!productExists(hive,leaf,view)) continue;
        productLocation(hive,view,leaf);
        ProductKey key;productWin(RegOpenKeyExW(hive,leaf.c_str(),0,KEY_READ|view,&key.h));
        DWORD subkeys=0,values=0;
        productWin(RegQueryInfoKeyW(key.h,nullptr,nullptr,nullptr,&subkeys,nullptr,nullptr,&values,nullptr,nullptr,nullptr,nullptr));
        productKeyDiagnostic(hive,view,leaf,L"RegQueryInfoKeyW-profile",ERROR_SUCCESS,subkeys,values);
        if(subkeys) throw ProductError{E_UNEXPECTED};
        if(!values) continue; // Exact empty residue, not an active profile.
        if(hive==HKEY_CURRENT_USER && values==1) {
            const DWORD enable=productDword(key.h,L"Enable");
            if(!yime18ureg::ValidProfileShape(false,subkeys,values,true,false,false,0,enable)) throw ProductError{E_UNEXPECTED};
            continue;
        }
        if(hive!=HKEY_LOCAL_MACHINE || values!=4) {
            productDiagnostic(L"profile-values",values,hive==HKEY_LOCAL_MACHINE?4:1);throw ProductError{E_UNEXPECTED};
        }
        const bool descriptionMatches=productString(key.h,L"Description")==kProfileName;
        const bool iconMatches=!_wcsicmp(productString(key.h,L"IconFile").c_str(),icon.c_str());
        const DWORD iconIndex=productDword(key.h,L"IconIndex"),enable=productDword(key.h,L"Enable");
        if(!yime18ureg::ValidProfileShape(true,subkeys,values,true,descriptionMatches,iconMatches,iconIndex,enable)) {
            productDiagnostic(L"Description-match",descriptionMatches,1);productDiagnostic(L"IconFile-match",iconMatches,1);
            productDiagnostic(L"IconIndex",iconIndex,0);productDiagnostic(L"Enable-valid",enable<=1,1);
            throw ProductError{E_UNEXPECTED};
        }
        result.machineProfile=true;
        if(view==KEY_WOW64_64KEY) result.completeMachineProfile=true;
    }
    return result;
}
void productComOwned(const std::wstring& dll) {
    productStage=L"COM-ownership";
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
}
struct ProductApiSnapshot { bool categoriesKnown=false,profilesKnown=false,foreignSnapshot=false;unsigned categories=0,profiles=0; HRESULT firstError=S_OK; };
ProductApiSnapshot productSnapshot() noexcept {
    ProductApiSnapshot s;
    productStage=L"API-category-snapshot";
    try{s.categories=productCategories();s.categoriesKnown=true;}catch(const ProductError& e){s.foreignSnapshot=s.foreignSnapshot||e.foreignSnapshot;if(s.firstError==S_OK)s.firstError=e.code;productDiagnostic(L"snapshot-error",e.code,S_OK);}catch(...){if(s.firstError==S_OK)s.firstError=E_UNEXPECTED;productDiagnostic(L"snapshot-error",E_UNEXPECTED,S_OK);}
    productStage=L"API-profile-snapshot";
    try{s.profiles=productProfiles();s.profilesKnown=true;}catch(const ProductError& e){s.foreignSnapshot=s.foreignSnapshot||e.foreignSnapshot;if(s.firstError==S_OK)s.firstError=e.code;productDiagnostic(L"snapshot-error",e.code,S_OK);}catch(...){if(s.firstError==S_OK)s.firstError=E_UNEXPECTED;productDiagnostic(L"snapshot-error",E_UNEXPECTED,S_OK);}
    try {std::wcerr<<L"api_snapshot categories_known="<<s.categoriesKnown<<L" categories="<<s.categories
        <<L" profiles_known="<<s.profilesKnown<<L" profiles="<<s.profiles<<L"\n";} catch(...){}
    return s;
}
ProductPersistent productOwned(const std::wstring& dll) {
    productComOwned(dll);
    const auto s=productPersistent(dll);
    const auto api=productSnapshot(); // Valid cached counts may lag; positive foreign observations may not.
    productStage=L"persistent-ownership";
    if(!yime18ureg::MayMaintainPersistent(yime18ureg::ClassifyPersistent(true,s.anyTip,s.completeMachineProfile,s.machinePairedMask,true),api.foreignSnapshot))
        throw ProductError{E_UNEXPECTED};
    return s;
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
           nt.Signature!=IMAGE_NT_SIGNATURE || nt.FileHeader.Machine!=kInstalled18uMachine ||
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
    productLocation(hive,view,path);
    ProductKey key;
    const LSTATUS opened=RegOpenKeyExW(hive,path.c_str(),0,KEY_READ|view,&key.h);
    productKeyDiagnostic(hive,view,path,L"RegOpenKeyExW",opened);
    if(opened==ERROR_FILE_NOT_FOUND || opened==ERROR_PATH_NOT_FOUND) return;
    productWin(opened);
    DWORD subkeys=0,values=0;
    productWin(RegQueryInfoKeyW(key.h,nullptr,nullptr,nullptr,&subkeys,nullptr,nullptr,&values,nullptr,nullptr,nullptr,nullptr));
    productKeyDiagnostic(hive,view,path,L"RegQueryInfoKeyW",ERROR_SUCCESS,subkeys,values);
    bool enableZero=false;
    if(profileLeaf && values==1) {
        DWORD type=0,bytes=sizeof(DWORD),enable=1;
        const LSTATUS queried=RegQueryValueExW(key.h,L"Enable",nullptr,&type,reinterpret_cast<BYTE*>(&enable),&bytes);
        productKeyDiagnostic(hive,view,path,L"RegQueryValueExW-Enable",queried,subkeys,values);
        enableZero=queried==ERROR_SUCCESS && type==REG_DWORD && bytes==sizeof(DWORD) && enable==0;
    }
    if(!yime18ureg::RemovableResidue(subkeys,values,profileLeaf,enableZero)) throw ProductError{E_UNEXPECTED};
    // A concurrent added child makes this nonrecursive delete fail. A value-only race
    // remains possible; this maintenance command is not a concurrent installer protocol.
    RegCloseKey(key.h); key.h=nullptr;
    const LSTATUS removed=RegDeleteKeyExW(hive,path.c_str(),view,0);
    productKeyDiagnostic(hive,view,path,L"RegDeleteKeyExW",removed,subkeys,values);
    productWin(removed);
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
        productCategoryShape(hive,view,&categories);
        for(const auto& path:categories) productRemoveResidueLeaf(hive,view,path,false);
        productRemoveResidueLeaf(hive,view,root,false);
    }
}
void productRemove(const std::wstring& dll, bool tipOnly) {
    const auto owned=productOwned(dll);
    // Persisted exact relationships decide which removal APIs are applicable.
    // Snapshot counts may lag and never turn a missing record into an API request.
    if(owned.categoryMask) {
        productStage=L"remove-category-manager";
        ITfCategoryMgr* raw=nullptr;
        productRequire(CoCreateInstance(CLSID_TF_CategoryMgr,nullptr,CLSCTX_INPROC_SERVER,
            __uuidof(ITfCategoryMgr),reinterpret_cast<void**>(&raw)));
        struct Release {ITfCategoryMgr* p;~Release(){p->Release();}} release{raw};
        for(unsigned i=0;i<std::size(kTipCategories);++i) {
            if(!yime18ureg::ShouldRemoveCategory(owned.categoryMask,i)) continue;
            productStage=L"remove-present-category";
            const HRESULT hr=raw->UnregisterCategory(CLSID_YimeTextServiceExperiment,*kTipCategories[i],CLSID_YimeTextServiceExperiment);
            traceProductCategory(L"product-unregister-category",*kTipCategories[i],hr);
            productRequire(hr); // S_FALSE is recorded, never silently called S_OK.
        }
    }
    if(owned.machineProfile) {
        productStage=L"remove-profile-manager";
        ITfInputProcessorProfileMgr* raw=nullptr;
        productRequire(CoCreateInstance(CLSID_TF_InputProcessorProfiles,nullptr,CLSCTX_INPROC_SERVER,
            __uuidof(ITfInputProcessorProfileMgr),reinterpret_cast<void**>(&raw)));
        struct Release {ITfInputProcessorProfileMgr* p;~Release(){p->Release();}} release{raw};
        productStage=L"remove-present-profile";
        const HRESULT hr=raw->UnregisterProfile(CLSID_YimeTextServiceExperiment,kLanguageId,GUID_YimeTextServiceExperimentProfile,0);
        traceRegistrationStep(L"product-unregister-profile",hr);productRequire(hr);
    }
    productStage=L"post-removal-persistent-shape";
    const auto after=productPersistent(dll);
    if(after.machineProfile || after.categoryMask) throw ProductError{E_UNEXPECTED};
    productStage=L"bounded-residue-delete";
    productRemoveResidue(); // Exact empty/Enable=0 leaves only; nonrecursive; COM retained on failure.
    const auto finalPersistent=productPersistent(dll);
    if(finalPersistent.anyTip) throw ProductError{HRESULT_FROM_WIN32(ERROR_DIR_NOT_EMPTY)};
    if(tipOnly) {
        // TSF enumeration can retain the pre-removal snapshot in this process.
        // This phase succeeds only for persisted TIP removal, never COM removal.
        // Setup starts a fresh unregister process for the unchanged final guards.
        std::wcout<<L"tip_removal_complete=true\ncom_retained=true\ncompletion_required=true\n";
        return;
    }
    const auto api=productSnapshot();
    productStage=L"final-API-absence-before-COM";
    if(!yime18ureg::FinalApiAbsent(api.categoriesKnown,api.categories,api.profilesKnown,api.profiles))
        throw ProductError{api.firstError==S_OK?E_UNEXPECTED:api.firstError}; // No polling/retry; stale or unknown final API retains COM.
    productComOwned(dll);
    productStage=L"COM-delete-last";
    // Recheck exact COM shape after API calls, without requiring the now-removed profile.
    ProductKey root, server;
    productWin(RegOpenKeyExW(HKEY_LOCAL_MACHINE,productComRoot().c_str(),0,KEY_READ|KEY_WRITE|KEY_WOW64_64KEY,&root.h));
    productShape(root.h,1,0);
    productWin(RegOpenKeyExW(root.h,L"InprocServer32",0,KEY_READ,&server.h)); productShape(server.h,0,2);
    if (_wcsicmp(productString(server.h,nullptr).c_str(),dll.c_str()) || productString(server.h,L"ThreadingModel")!=L"Apartment") throw ProductError{E_UNEXPECTED};
    RegCloseKey(server.h); server.h=nullptr;
    const LSTATUS serverRemoved=RegDeleteKeyExW(root.h,L"InprocServer32",KEY_WOW64_64KEY,0);
    productKeyDiagnostic(HKEY_LOCAL_MACHINE,KEY_WOW64_64KEY,productComRoot()+L"\\InprocServer32",L"RegDeleteKeyExW",serverRemoved);
    productWin(serverRemoved);
    RegCloseKey(root.h); root.h=nullptr;
    const LSTATUS comRemoved=RegDeleteKeyExW(HKEY_LOCAL_MACHINE,productComRoot().c_str(),KEY_WOW64_64KEY,0);
    productKeyDiagnostic(HKEY_LOCAL_MACHINE,KEY_WOW64_64KEY,productComRoot(),L"RegDeleteKeyExW",comRemoved);
    productWin(comRemoved);
    const auto state=productState();
    if (!yime18ureg::CanRegister(true,state.com,state.tip,state.categories)) throw ProductError{HRESULT_FROM_WIN32(ERROR_DIR_NOT_EMPTY)};
}
}
int wmain(int argc,wchar_t** argv) {
    const auto operation=yime18ureg::Parse(argc,argc>1?argv[1]:nullptr);
    if (operation==yime18ureg::Operation::Invalid) return 2;
    HRESULT result=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
    if (FAILED(result)) { productWriteResult(L"initialize",result); return 2; }
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
            productStage=L"installed-marker-manifest-DLL-binding";
            productRequire(yime18uinstallation::Verify(dll,yime18ureg::AllowsLegacyInstallation(operation)));
            if (operation==yime18ureg::Operation::CheckOwned) { productOwned(dll); std::wcout<<L"owned=true\nmutation_performed=false\ncom_path="<<dll<<L"\n"; }
            else {
                if(!isElevated()) throw ProductError{E_ACCESSDENIED};
                if(operation==yime18ureg::Operation::Register) {
                    const auto s=productState();
                    if(!yime18ureg::CanRegister(true,s.com,s.tip,s.categories)) throw ProductError{HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS)};
                    ProductDllReadLock lock; lock.open(dll);
                    productStage=L"create-COM";productCreateCom(dll);
                    productStage=L"register-profile-and-categories";productRequire(registerProfileAndCategories(dll.c_str()));
                    const auto registered=productOwned(dll);
                    productStage=L"register-persistent-postcondition";
                    if(yime18ureg::ClassifyPersistent(true,registered.anyTip,registered.completeMachineProfile,registered.machinePairedMask,true)!=yime18ureg::PersistentKind::Complete)
                        throw ProductError{E_UNEXPECTED};
                } else productRemove(dll,operation==yime18ureg::Operation::UnregisterTip);
                productWriteResult(argv[1],S_OK);
            }
        }
    } catch(const ProductError& e) { productDiagnostic(L"first-error",e.code,S_OK); productWriteResult(argv[1],e.code); code=5; }
      catch(...) { productWriteResult(argv[1],E_UNEXPECTED); code=5; }
    CoUninitialize(); return code;
}
