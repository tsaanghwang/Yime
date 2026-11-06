// Synthetic package files only. No DLL loading, registry access or TSF activation.
#include "../ProductInstallationProof.h"
#include <fstream>
#include <functional>
#include <stdexcept>

namespace fs = std::filesystem;
using namespace yime18uinstallation::detail;
void check(bool value,const char* message){if(!value)throw std::runtime_error(message);}
void write(const fs::path& path,const std::string& text){
    std::ofstream stream(path,std::ios::binary|std::ios::trunc);
    stream.write(text.data(),static_cast<std::streamsize>(text.size()));
    check(stream.good(),"fixture write failed");
}
Json row(const char* name,const fs::path& path){
    File file(path,1024*1024);
    return {{"path",name},{"bytes",file.bytes},{"sha256",Hash(file)}};
}
struct Fixture {
    fs::path root,dll;
    Json marker,descriptor,manifest;
    Fixture(){
        wchar_t temp[32768]{};
        const auto n=GetTempPathW(static_cast<DWORD>(std::size(temp)),temp);
        check(n&&n<std::size(temp),"temp unavailable");
        root=fs::path(temp)/(L"yime-18u-proof-"+std::to_wstring(GetCurrentProcessId())+L"-"+std::to_wstring(GetTickCount64()));
        check(fs::create_directory(root),"fresh fixture required");
        fs::create_directory(root/kInstalled18uDirectory);fs::create_directory(root/L".setup");
        dll=root/kInstalled18uDirectory/L"YimeTextService18u.dll";
        write(dll,"synthetic DLL bytes: never loaded");
        marker={{"format","yime-simple-install-1"},{"product","yimecore-18u"},{"target",kInstalled18uTarget},{"version","fixture.1"}};
        descriptor={{"schema","installed-18u-product-v1"},{"product","yimecore-18u"},{"sourceCommit",std::string(40,'a')},
            {"identity",{{"clsid","{6DFACE1F-562E-4773-A9D6-D5753A314711}"},{"profile","{1BD904AC-3194-4419-B70A-5574100F18B3}"}}},
            {"architecture",kInstalled18uDescriptorArchitecture},{"language","CN"},{"mode","variable"},{"autostart",false},
            {"files",Json::array({row(kInstalled18uDllMember,dll)})}};
        manifest={{"format","yime-simple-package-18u-1"},{"product","yimecore-18u"},{"target",kInstalled18uTarget},
            {"host_architecture",kInstalled18uHostArchitecture},{"tsf64_architecture",kInstalled18uTsfArchitecture},{"version","fixture.1"}};
    }
    ~Fixture(){std::error_code error;fs::remove_all(root,error);}
    void save(){
        write(root/L".yime-product.json",marker.dump());
        write(root/L"installed-18u-product.json",descriptor.dump());
        manifest["files"]=descriptor.at("files");
        manifest["files"].push_back(row("installed-18u-product.json",root/L"installed-18u-product.json"));
        write(root/L".setup"/L"product-package.json",manifest.dump());
    }
    bool verify(bool legacy=false){
        Diagnostic diagnostic;
        try{auto lock=VerifyImpl(dll.native(),diagnostic,legacy);return lock!=nullptr;}catch(...){return false;}
    }
    void legacy(){
        descriptor["schema"]="installed-18u-product-v2";descriptor["autostart"]=true;
        descriptor.erase("language");descriptor.erase("mode");
        descriptor["languages"]=Json::array({"CN","EN"});
        descriptor["modes"]=Json::array({"full","variable","shorthand"});
        descriptor["capabilities"]=Json::array({"installed-tsf-frontend","composition","candidates","literal","host-editing"});
        descriptor["files"].push_back({{"path","bin/YimeTouchKeyboard.exe"},{"bytes",uint64_t(7)},{"sha256",std::string(64,'a')}});
    }
};
int main(){try{
    check(Installed18uNativeProcess(GetCurrentProcess()),"test must execute natively");
    check(Installed18uNativeMachine(true,0,kInstalled18uMachine),"matching native target");
    check(!Installed18uNativeMachine(false,0,kInstalled18uMachine),"failed query accepted");
    check(!Installed18uNativeMachine(true,IMAGE_FILE_MACHINE_I386,kInstalled18uMachine),"WOW64 accepted");
    check(!Installed18uNativeMachine(true,IMAGE_FILE_MACHINE_AMD64,IMAGE_FILE_MACHINE_ARM64),"x64 emulation accepted");
    check(!Installed18uNativeMachine(true,0,kInstalled18uMachine,4),"32-bit accepted");
    const auto foreignMachine=kInstalled18uMachine==IMAGE_FILE_MACHINE_ARM64?IMAGE_FILE_MACHINE_AMD64:IMAGE_FILE_MACHINE_ARM64;
    check(!Installed18uNativeMachine(true,0,foreignMachine),"foreign native host accepted");
    Fixture f;f.save();check(f.verify(),"matching current proof refused");
    const auto marker=f.marker,descriptor=f.descriptor,manifest=f.manifest;
    const auto reject=[&](const std::function<void()>& change,const char* reason){
        f.marker=marker;f.descriptor=descriptor;f.manifest=manifest;change();f.save();check(!f.verify(),reason);
    };
    reject([&]{f.marker["target"]="windows-foreign";},"foreign marker accepted");
    reject([&]{f.manifest["target"]="windows-foreign";},"foreign package accepted");
    reject([&]{f.manifest["host_architecture"]="foreign";},"foreign frontend accepted");
    reject([&]{f.manifest["tsf64_architecture"]="arm64x";},"ARM64X accepted");
    reject([&]{f.descriptor["architecture"]="native-foreign";},"foreign descriptor accepted");
    reject([&]{f.descriptor["files"][0]["path"]="foreign/YimeTextService18u.dll";},"foreign DLL member accepted");
    reject([&]{f.descriptor["files"].push_back(f.descriptor["files"][0]);},"duplicate DLL member accepted");
    reject([&]{f.descriptor["files"][0]["sha256"]=std::string(64,'0');},"stale DLL hash accepted");
    reject([&]{f.descriptor["autostart"]=true;},"old startup silently enabled");
    reject([&]{f.descriptor["extra"]=true;},"extra descriptor field accepted");
    f.marker=marker;f.descriptor=descriptor;f.manifest=manifest;f.legacy();f.save();
    check(!f.verify(),"legacy package admitted for registration");
    const bool arm=kInstalled18uMachine==IMAGE_FILE_MACHINE_ARM64;
    check(f.verify(true)==arm,"legacy removal architecture boundary");
    f.descriptor["modes"]=Json::array({"variable"});f.save();check(!f.verify(true),"altered legacy capabilities accepted");
    f.descriptor=descriptor;f.legacy();f.descriptor["language"]="CN";f.save();check(!f.verify(true),"mixed legacy schema accepted");
    f.descriptor=descriptor;f.legacy();f.descriptor["files"].push_back({{"path","frontend/YimeTouchKeyboard.exe"},{"bytes",uint64_t(7)},{"sha256",std::string(64,'a')}});f.save();
    check(!f.verify(true),"mixed legacy frontend accepted");
    std::cout<<"PASS installation proof: native machine and architecture identity, file hashes, current schema, legacy ARM removal only; synthetic files, no registration\n";
    return 0;
}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}
