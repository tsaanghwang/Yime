// CI-only drill of the stage1 residue classification, removal and snapshot code
// against the real registry and real TSF COM objects, using synthetic keys under
// the independent 18u CLSID only. It never registers a profile, never touches
// another identity, and refuses to run where any residue of this CLSID already
// exists (that is the MyComputer recovery case, not a fixture).
#define YIME_RESIDUE_FIXTURE_TESTS 1
#include <set>
#include "RegistrationProbe.cpp"

namespace {
struct CaseFailure { std::string name; std::string stage; };
void expect(bool ok,const char* stage){ if(!ok) throw Failure{stage,E_FAIL}; }
std::wstring tipParent(){return L"SOFTWARE\\Microsoft\\CTF\\TIP";}

void createKey(HKEY hive,const std::wstring& path,REGSAM view){
 Key key;DWORD disposition=0;
 check(HRESULT_FROM_WIN32(RegCreateKeyExW(hive,path.c_str(),0,nullptr,REG_OPTION_NON_VOLATILE,KEY_WRITE|view,nullptr,&key.value,&disposition)),"fixture-create");
}
void setDword(HKEY hive,const std::wstring& path,REGSAM view,const wchar_t* name,DWORD value){
 Key key;check(HRESULT_FROM_WIN32(RegOpenKeyExW(hive,path.c_str(),0,KEY_SET_VALUE|view,&key.value)),"fixture-open");
 check(HRESULT_FROM_WIN32(RegSetValueExW(key.value,name,0,REG_DWORD,reinterpret_cast<const BYTE*>(&value),sizeof(value))),"fixture-set");
}
void setString(HKEY hive,const std::wstring& path,REGSAM view,const wchar_t* name,const std::wstring& value){
 Key key;check(HRESULT_FROM_WIN32(RegOpenKeyExW(hive,path.c_str(),0,KEY_SET_VALUE|view,&key.value)),"fixture-open");
 check(HRESULT_FROM_WIN32(RegSetValueExW(key.value,name,0,REG_SZ,reinterpret_cast<const BYTE*>(value.c_str()),static_cast<DWORD>((value.size()+1)*sizeof(wchar_t)))),"fixture-set");
}
// Exactly the shape UnregisterProfile/UnregisterCategory left on MyComputer.
void createShell(){
 const auto tip=localTipPath();const auto category=guid(GUID_TFCAT_TIP_KEYBOARD),clsid=guid(CLSID_YimeTextServiceExperiment),profile=guid(GUID_YimeTextServiceExperimentProfile);
 for(REGSAM view:{KEY_WOW64_32KEY,KEY_WOW64_64KEY}){
  createKey(HKEY_LOCAL_MACHINE,tip+L"\\Category\\Category\\"+category,view);
  createKey(HKEY_LOCAL_MACHINE,tip+L"\\Category\\Item\\"+clsid,view);
  createKey(HKEY_LOCAL_MACHINE,tip+L"\\LanguageProfile\\0x00000804",view);
  createKey(HKEY_CURRENT_USER,tip+L"\\LanguageProfile\\0x00000804\\"+profile,view);
  setDword(HKEY_CURRENT_USER,tip+L"\\LanguageProfile\\0x00000804\\"+profile,view,L"Enable",0);
 }
}
// Test-owned teardown of fixtures under this CLSID only; never used by the product path.
void teardown(){
 for(HKEY hive:{HKEY_LOCAL_MACHINE,HKEY_CURRENT_USER})for(REGSAM view:{KEY_WOW64_32KEY,KEY_WOW64_64KEY}){
  Key parent;const LSTATUS opened=RegOpenKeyExW(hive,tipParent().c_str(),0,KEY_READ|KEY_WRITE|view,&parent.value);
  if(opened==ERROR_FILE_NOT_FOUND||opened==ERROR_PATH_NOT_FOUND)continue;
  check(HRESULT_FROM_WIN32(opened),"teardown-open");
  const LSTATUS removed=RegDeleteTreeW(parent.value,guid(CLSID_YimeTextServiceExperiment).c_str());
  expect(removed==ERROR_SUCCESS||removed==ERROR_FILE_NOT_FOUND||removed==ERROR_PATH_NOT_FOUND,"teardown-delete");
 }
 expect(!localTipResidueExists(),"teardown-residue-remains");
}
std::set<std::string> snapshotKeys(const json& entries){
 std::set<std::string> keys;
 for(const auto& entry:entries)keys.insert(entry.at("hive").get<std::string>()+"/"+entry.at("view").get<std::string>()+" "+entry.at("path").get<std::string>());
 return keys;
}
std::set<std::string> expectedShellKeys(){
 const auto tip=localUtf8(localTipPath());const auto category=localUtf8(guid(GUID_TFCAT_TIP_KEYBOARD)),clsid=localUtf8(guid(CLSID_YimeTextServiceExperiment)),profile=localUtf8(guid(GUID_YimeTextServiceExperimentProfile));
 std::set<std::string> keys;
 for(const char* view:{"32","64"}){
  for(const std::string path:{tip,tip+"\\Category",tip+"\\Category\\Category",tip+"\\Category\\Category\\"+category,tip+"\\Category\\Item",tip+"\\Category\\Item\\"+clsid,tip+"\\LanguageProfile",tip+"\\LanguageProfile\\0x00000804"})keys.insert(std::string("HKLM/")+view+" "+path);
  for(const std::string path:{tip,tip+"\\LanguageProfile",tip+"\\LanguageProfile\\0x00000804",tip+"\\LanguageProfile\\0x00000804\\"+profile})keys.insert(std::string("HKCU/")+view+" "+path);
 }
 return keys;
}
void expectRemovalRefused(Transaction& t,const char* stage){
 try{localRemoveOwnedTipResidue(t.languages.Get(),t.profiles.Get(),t.categories.Get());}
 catch(const Failure& failure){expect(std::string(failure.stage)==stage,"refusal-stage-mismatch");expect(localTipResidueExists(),"refused-removal-must-keep-residue");return;}
 throw Failure{"foreign-residue-was-removed",E_FAIL};
}
}

int wmain(int,wchar_t**){
 using yime::stage1::ResidueShape;
 json report={{"schema","18u-residue-fixture-drill-v1"},{"scope","synthetic-keys-under-18u-clsid-only"},{"status","blocked"},{"stage","completed"},{"code",0},{"cases",json::array()},{"registration",false}};
 const HRESULT initialized=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
 if(FAILED(initialized)){report["stage"]="com-initialize";report["code"]=static_cast<unsigned long>(initialized);std::cout<<report.dump()<<std::endl;return 3;}
 int exit=3;
 {
  Transaction t;
  try{
   t.initialize();
   expect(elevated(),"fixture-elevation-required");
   // Any real residue of this CLSID belongs to a recovery case, never to a drill.
   expect(!localTipResidueExists(),"preexisting-residue-not-a-fixture");
   expect(!exists(HKEY_LOCAL_MACHINE,L"SOFTWARE\\Classes\\CLSID\\"+guid(CLSID_YimeTextServiceExperiment),KEY_WOW64_64KEY),"preexisting-com-root-not-a-fixture");
   expect(localProfileEnumerationAbsent(t.languages.Get(),t.profiles.Get(),t.categories.Get()),"profile-registered-on-runner");
   auto run=[&](const char* name,auto body){
    try{body();report["cases"].push_back({{"case",name},{"result","pass"}});}
    catch(const Failure& failure){report["cases"].push_back({{"case",name},{"result","fail"},{"stage",failure.stage}});throw CaseFailure{name,failure.stage};}
   };
   run("absent-baseline",[&]{
    expect(localResidueShape(t.languages.Get(),t.profiles.Get(),t.categories.Get())==ResidueShape::Absent,"baseline-shape");
    expect(localResidueSnapshot().empty(),"baseline-snapshot-not-empty");
   });
   run("owned-shell-classified-snapshotted-removed",[&]{
    createShell();
    setString(HKEY_LOCAL_MACHINE,localTipPath()+L"\\LanguageProfile\\0x00000804",KEY_WOW64_64KEY,nullptr,L"default-value-fixture");
    expect(localTipResidueExists(),"shell-not-created");
    expect(localResidueShape(t.languages.Get(),t.profiles.Get(),t.categories.Get())==ResidueShape::OwnedEmptyShell,"shell-shape");
    const json snapshot=localResidueSnapshot();
    expect(snapshotKeys(snapshot)==expectedShellKeys(),"snapshot-key-set");
    bool sawEnable=false,sawDefault=false;
    for(const auto& entry:snapshot)for(const auto& value:entry.at("values")){
     expect(value.size()==4&&value.contains("name")&&value.contains("type")&&value.contains("bytes")&&value.contains("sha256")&&!value.contains("data"),"snapshot-value-record");
     if(value.at("name")=="Enable"){expect(value.at("type")==REG_DWORD&&value.at("bytes")==4,"snapshot-enable-record");sawEnable=true;}
     if(value.at("name")==""){expect(value.at("type")==REG_SZ,"snapshot-default-record");sawDefault=true;}
     expect(value.at("sha256").get<std::string>().size()==64,"snapshot-hash");
    }
    expect(sawEnable&&sawDefault,"snapshot-values-missing");
    localRemoveOwnedTipResidue(t.languages.Get(),t.profiles.Get(),t.categories.Get());
    expect(!localTipResidueExists(),"shell-still-exists");
    expect(localResidueShape(t.languages.Get(),t.profiles.Get(),t.categories.Get())==ResidueShape::Absent,"shape-after-removal");
    expect(localResidueSnapshot().empty(),"snapshot-after-removal");
   });
   run("removal-of-absent-residue-refused",[&]{
    try{localRemoveOwnedTipResidue(t.languages.Get(),t.profiles.Get(),t.categories.Get());}
    catch(const Failure& failure){expect(std::string(failure.stage)=="residue-already-absent","absent-refusal-stage");return;}
    throw Failure{"absent-removal-not-refused",E_FAIL};
   });
   run("foreign-language-kept",[&]{
    createShell();createKey(HKEY_LOCAL_MACHINE,localTipPath()+L"\\LanguageProfile\\0x00000409",KEY_WOW64_64KEY);
    expect(localResidueShape(t.languages.Get(),t.profiles.Get(),t.categories.Get())==ResidueShape::NotOwned,"foreign-language-shape");
    expectRemovalRefused(t,"owned-tip-other-language");teardown();
   });
   run("foreign-category-kept",[&]{
    createShell();createKey(HKEY_LOCAL_MACHINE,localTipPath()+L"\\Category\\Category\\{5E9D2F4A-7C1B-4B6E-9A3F-0C2D8E1F6B77}",KEY_WOW64_64KEY);
    expect(localResidueShape(t.languages.Get(),t.profiles.Get(),t.categories.Get())==ResidueShape::NotOwned,"foreign-category-shape");
    expectRemovalRefused(t,"owned-category-unknown-reference");teardown();
   });
   run("foreign-profile-kept",[&]{
    createShell();createKey(HKEY_CURRENT_USER,localTipPath()+L"\\LanguageProfile\\0x00000804\\{0B1C2D3E-4F50-4617-8293-A4B5C6D7E8F9}",KEY_WOW64_64KEY);
    expect(localResidueShape(t.languages.Get(),t.profiles.Get(),t.categories.Get())==ResidueShape::NotOwned,"foreign-profile-shape");
    expectRemovalRefused(t,"owned-tip-other-profile");teardown();
   });
   run("unknown-child-kept",[&]{
    createShell();createKey(HKEY_LOCAL_MACHINE,localTipPath()+L"\\Unexpected",KEY_WOW64_64KEY);
    expect(localResidueShape(t.languages.Get(),t.profiles.Get(),t.categories.Get())==ResidueShape::NotOwned,"unknown-child-shape");
    expectRemovalRefused(t,"owned-tip-unknown-child");teardown();
   });
   expect(!localTipResidueExists(),"final-residue");
   report["status"]="pass";exit=0;
  }catch(const CaseFailure& failure){report["status"]="failed";report["stage"]=failure.name+":"+failure.stage;report["code"]=static_cast<unsigned long>(E_FAIL);exit=1;try{teardown();}catch(...){report["teardown"]="failed";}}
  catch(const Failure& failure){report["stage"]=failure.stage;report["code"]=static_cast<unsigned long>(failure.code);}
  catch(...){report["status"]="failed";report["stage"]="unclassified-exception";report["code"]=static_cast<unsigned long>(E_FAIL);exit=1;}
 }
 CoUninitialize();std::cout<<report.dump()<<std::endl;return exit;
}
