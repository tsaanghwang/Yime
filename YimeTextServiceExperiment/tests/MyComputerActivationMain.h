#pragma once
#include "ActivationFailureTrace.h"
// Only compiled for the separately named, default-OFF local stage-1 tool.
namespace {
json localConditions(){return {{"nativeX64",nullptr},{"hostMatches",nullptr},{"hkl0804",nullptr},{"tsf0804",nullptr},{"elevated",nullptr},{"identityAbsent",nullptr},{"dllVerified",nullptr},{"directTestAbsent",nullptr}};}
yime::stage1::PreflightFacts inspectLocal(Transaction& transaction,Ledger& ledger,const yime::stage1::Arguments& args,json& report){
 yime::stage1::PreflightFacts facts;report["preconditions"]=localConditions();
 auto observe=[&](const char* key,bool& fact,auto action){try{fact=action();report["preconditions"][key]=fact;}catch(const Failure& f){if(report["stage"]=="completed"){report["stage"]=f.stage;report["code"]=static_cast<unsigned long>(f.code);}}catch(...){if(report["stage"]=="completed"){report["stage"]="preflight-query-exception";report["code"]=static_cast<unsigned long>(E_FAIL);}}};
 observe("nativeX64",facts.nativeX64,[]{return localNative();});
 observe("hostMatches",facts.hostMatches,[&]{const auto host=localHostName();report["actualHostName"]=localUtf8(host);return _wcsicmp(host.c_str(),L"MyComputer")==0;});
 observe("elevated",facts.elevated,[]{return elevated();});
 observe("hkl0804",facts.hkl0804,[&]{HKL hkl=GetKeyboardLayout(0);require(hkl!=nullptr,"preflight-hkl-query");transaction.threadLanguage=LOWORD(reinterpret_cast<ULONG_PTR>(hkl));report["threadLanguage"]=transaction.threadLanguage;return transaction.threadLanguage==language;});
 observe("tsf0804",facts.tsf0804,[&]{transaction.initialize();check(transaction.languages->GetCurrentLanguage(&transaction.currentLanguage),"preflight-tsf-language");report["currentLanguage"]=transaction.currentLanguage;return transaction.currentLanguage==language;});
 observe("directTestAbsent",facts.directTestAbsent,[]{return GetEnvironmentVariableW(L"YIME_TEXTSERVICE_EXPERIMENT_DIRECT_TEST",nullptr,0)==0;});
 observe("identityAbsent",facts.identityAbsent,[&]{require(transaction.languages&&transaction.profiles&&transaction.categories,"preflight-api-unavailable");registryAbsent();apiAbsent(transaction.languages.Get(),transaction.profiles.Get(),transaction.categories.Get());return true;});
 if(!args.dll.empty())observe("dllVerified",facts.dllVerified,[&]{ledger.expectedSha=args.sha256;ledger.dllLock.open(args.dll,args.sha256);report["dllSha256"]=ledger.dllLock.sha;report["dllPresent"]=true;return true;});
 report["prerequisitesSatisfied"]=yime::stage1::CanRegister(facts);return facts;
}
yime::stage1::LedgerFlags inspectedFlags(const Ledger& ledger){
 const auto& d=ledger.data;return {d.at("preflightAbsent").get<bool>(),d.at("comAttempted").get<bool>(),d.at("comOwned").get<bool>(),d.at("profileAttempted").get<bool>(),d.at("categoryAttempted").get<bool>(),d.at("enableAttempted").get<bool>(),d.at("activationAttempted").get<bool>(),d.at("cleanupVerified").get<bool>()};
}
bool currentAbsence(Transaction& transaction){
 try{registryAbsent();apiAbsent(transaction.languages.Get(),transaction.profiles.Get(),transaction.categories.Get());return true;}
 catch(const Failure& failure){
  const std::string stage=failure.stage;
  if(stage=="existing-com-identity"||stage=="existing-tip-identity"||stage=="existing-identity-value-name"||stage=="existing-identity-value-data"||stage=="existing-identity-binary-data"||stage=="existing-profile-identity")return false;
  throw; // Access denial, malformed enumeration and unknown state are not presence evidence.
 }
}
bool inspectOwnedScope(Transaction& transaction,Ledger& ledger){
 const auto flags=inspectedFlags(ledger);
 if(currentAbsence(transaction))return false;
 require(!(flags.comAttempted&&!flags.comOwned&&!flags.cleanupVerified),"unconfirmed-com-creation-window");
 require(!flags.cleanupVerified,"previous-cleanup-evidence-conflicts-with-residue");
 require(flags.comAttempted&&flags.comOwned&&yime::stage1::CanRecover(flags,ledger.ownerState,ledger.bindingVerified),"inspection-ownership-not-proven");
 ledger.validateOwnedCom();
 if(flags.profileAttempted)strictLocalTipShape(transaction.languages.Get(),transaction.profiles.Get(),transaction.categories.Get());
 else apiAbsent(transaction.languages.Get(),transaction.profiles.Get(),transaction.categories.Get());
 return true;
}
json recoveryInspectionReport(){return {{"schema","mycomputer-recovery-inspection-v1"},{"scope","readonly-recovery-ownership"},{"status","blocked"},{"stage","completed"},{"code",0},{"ledgerSha256",nullptr},{"ownerPid",nullptr},{"ownerCreationTime",nullptr},{"dllSha256",nullptr},{"bindingVerified",false},{"ownerDeadVerified",false},{"ownedScopeVerified",false},{"cleanupVerified",nullptr},{"flags",nullptr},{"recoveryRequired",nullptr},{"residueShape",nullptr},{"recoveryToolCapable",nullptr}};}
int inspectRecoveryOnly(const yime::stage1::Arguments& args){
 json report=recoveryInspectionReport();const HRESULT initialized=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
 if(FAILED(initialized)){report["stage"]="com-initialize";report["code"]=static_cast<unsigned long>(initialized);std::cout<<report.dump()<<std::endl;return 3;}
 int exit=3;
 {
  Transaction transaction;Ledger ledger;transaction.ledger=&ledger;ledger.expectedCipherSha256=args.ledgerSha256;
  try{
   localMachineGate();ledger.load(args.ledger);transaction.initialize();
   report["ledgerSha256"]=ledger.cipherSha256;report["ownerPid"]=ledger.data.at("pid");report["ownerCreationTime"]=ledger.data.at("creation");report["dllSha256"]=ledger.data.at("dllSha256");
   report["bindingVerified"]=ledger.bindingVerified;report["ownerDeadVerified"]=ledger.ownerState==yime::stage1::OwnerState::DeadVerified;
   json flags=json::object();for(const char* key:{"preflightAbsent","comAttempted","comOwned","profileAttempted","categoryAttempted","enableAttempted","activationAttempted","cleanupVerified"})flags[key]=ledger.data.at(key);report["flags"]=flags;report["cleanupVerified"]=flags.at("cleanupVerified");
   report["recoveryRequired"]=inspectOwnedScope(transaction,ledger);report["ownedScopeVerified"]=true;
   // Residue shape tells the orchestrator whether this tool can clear what remains
   // before it consumes the single recovery claim; "not-owned" must stop there.
   const auto shape=localResidueShape(transaction.languages.Get(),transaction.profiles.Get(),transaction.categories.Get());
   report["residueShape"]=yime::stage1::ResidueShapeName(shape);report["recoveryToolCapable"]=yime::stage1::RecoveryToolCapable(shape);
   report["status"]="verified";exit=0;
  }catch(const Failure& failure){report["stage"]=failure.stage;report["code"]=static_cast<unsigned long>(failure.code);}catch(...){report["stage"]="inspection-query-exception";report["code"]=static_cast<unsigned long>(E_FAIL);}
 }
 CoUninitialize();std::cout<<report.dump()<<std::endl;return exit;
}
// Read-only snapshot of the owned residue for the recovery evidence directory. It
// binds to the pinned ledger like inspection and records no value data.
int snapshotResidueOnly(const yime::stage1::Arguments& args){
 json report={{"schema","mycomputer-residue-snapshot-v1"},{"scope","readonly-owned-residue-snapshot"},{"status","blocked"},{"stage","completed"},{"code",0},{"ledgerSha256",nullptr},{"dllSha256",nullptr},{"residueShape",nullptr},{"entries",nullptr}};
 const HRESULT initialized=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
 if(FAILED(initialized)){report["stage"]="com-initialize";report["code"]=static_cast<unsigned long>(initialized);std::cout<<report.dump()<<std::endl;return 3;}
 int exit=3;
 {
  Transaction transaction;Ledger ledger;transaction.ledger=&ledger;ledger.expectedCipherSha256=args.ledgerSha256;
  try{
   localMachineGate();ledger.load(args.ledger);transaction.initialize();
   report["ledgerSha256"]=ledger.cipherSha256;report["dllSha256"]=ledger.data.at("dllSha256");
   report["residueShape"]=yime::stage1::ResidueShapeName(localResidueShape(transaction.languages.Get(),transaction.profiles.Get(),transaction.categories.Get()));
   report["entries"]=localResidueSnapshot();report["status"]="captured";exit=0;
  }catch(const Failure& failure){report["stage"]=failure.stage;report["code"]=static_cast<unsigned long>(failure.code);}catch(...){report["stage"]="snapshot-query-exception";report["code"]=static_cast<unsigned long>(E_FAIL);}
 }
 CoUninitialize();std::cout<<report.dump()<<std::endl;return exit;
}
json localReport(const char* mode){return {{"schema","mycomputer-activation-stage1-v1"},{"scope","mycomputer-registration-activation-only"},{"mode",mode},{"status","failed"},{"stage","completed"},{"code",0},{"writesStarted",false},{"cleanupVerified",false},{"preconditions",localConditions()},{"prerequisitesSatisfied",false},{"actualHostName",nullptr},{"threadLanguage",nullptr},{"currentLanguage",nullptr},{"dllSha256",nullptr},{"dllPresent",nullptr},{"publisherTrust","not-established"},{"brokerEditingVerified",false},{"profileActivationApiVerified",false},{"actualDllActivationVerified",false}};}
}
int wmain(int argc,wchar_t** argv){
 std::vector<std::wstring> arguments;for(int i=1;i<argc;++i)arguments.emplace_back(argv[i]);
 const auto args=yime::stage1::ParseArguments(arguments);using Mode=yime::stage1::Mode;
 if(args.mode==Mode::InspectRecovery)return inspectRecoveryOnly(args);
 if(args.mode==Mode::SnapshotResidue)return snapshotResidueOnly(args);
 const char* mode=args.mode==Mode::Preflight?"preflight":args.mode==Mode::RegisterOnce?"register-once":args.mode==Mode::Recover?"recover":args.mode==Mode::Verify?"verify":"invalid";
 json report=localReport(mode);if(args.mode==Mode::Invalid){report["status"]="blocked";report["stage"]="arguments";report["code"]=static_cast<unsigned long>(E_INVALIDARG);std::cout<<report.dump()<<std::endl;return 3;}
 HRESULT initialized=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);if(FAILED(initialized)){report["status"]="blocked";report["stage"]="com-initialize";report["code"]=static_cast<unsigned long>(initialized);std::cout<<report.dump()<<std::endl;return 3;}
 int exit=1;
 {
  Transaction transaction;Ledger ledger;transaction.ledger=&ledger;bool recoveryUnknown=args.mode==Mode::Recover;bool completed=false;
  try{
   if(args.mode==Mode::Preflight || args.mode==Mode::RegisterOnce){
    const auto facts=inspectLocal(transaction,ledger,args,report);
    if(args.mode==Mode::Preflight){report["status"]=report["stage"]=="completed"?"checked":"blocked";exit=report["stage"]=="completed"?0:3;completed=true;}
    else{
     require(yime::stage1::CanRegister(facts),"registration-preconditions-not-proven");
     // No ledger is created until all read-only preconditions passed. run()
     // repeats actual machine/language/elevation/absence checks before writing.
     ledger.create(args.ledger,ledger.dllLock.canonical);
     transaction.run(ledger.dllLock.canonical);report["profileActivationApiVerified"]=true;completed=true;
    }
   }else if(args.mode==Mode::Verify){localMachineGate();transaction.initialize();registryAbsent();apiAbsent(transaction.languages.Get(),transaction.profiles.Get(),transaction.categories.Get());report["cleanupVerified"]=true;completed=true;}
   else{
    ledger.expectedCipherSha256=args.ledgerSha256;
    localMachineGate();ledger.load(args.ledger);transaction.initialize();report["dllSha256"]=ledger.data.at("dllSha256");report["dllPresent"]=ledger.dllLock.file!=INVALID_HANDLE_VALUE;
    transaction.writes=ledger.data.at("comAttempted").get<bool>();transaction.comOwned=ledger.data.at("comOwned").get<bool>();transaction.profileAttempted=ledger.data.at("profileAttempted").get<bool>();transaction.categoryAttempted=ledger.data.at("categoryAttempted").get<bool>();transaction.enableAttempted=ledger.data.at("enableAttempted").get<bool>();
    // load() proves the original PID+creation-time process is dead, not merely
    // unreachable. Process-local activation cannot survive its termination.
    const bool recoveryRequired=inspectOwnedScope(transaction,ledger);
    if(recoveryRequired){
     if(transaction.writes)require(elevated(),"recovery-elevation-required");transaction.cleanup();require(transaction.cleanupOK,"recovery-cleanup-failed");
     registryAbsent();apiAbsent(transaction.languages.Get(),transaction.profiles.Get(),transaction.categories.Get());
    }
    // Preserve the original ciphertext/flags as historical evidence. The read
    // lock remains held through cleanup. This receipt plus independent --verify,
    // not a rewrite of the original journal, records the new cleanup result.
    recoveryUnknown=false;report["cleanupVerified"]=true;completed=true;
   }
  }catch(const Failure& failure){report["stage"]=failure.stage;report["code"]=static_cast<unsigned long>(failure.code);}catch(...){report["stage"]="unclassified-exception";report["code"]=static_cast<unsigned long>(E_FAIL);}
  // Preserve the operation failure before cleanup potentially replaces stage/code.
  yime::stage1::WriteFailureTrace(report,yime::stage1::FailurePhase::Operation,std::cerr);
  if(args.mode==Mode::RegisterOnce && transaction.writes){
   try{transaction.cleanup();if(transaction.cleanupOK){ledger.mark("cleanupVerified");report["cleanupVerified"]=true;}}
   catch(const Failure& failure){transaction.cleanupCheck(failure.code,failure.stage);}catch(...){transaction.cleanupCheck(E_FAIL,"cleanup-exception");}
   if(!transaction.cleanupOK){
    report["stage"]=transaction.cleanupStage;report["code"]=static_cast<unsigned long>(transaction.cleanupCode);completed=false;
    yime::stage1::WriteFailureTrace(report,yime::stage1::FailurePhase::Cleanup,std::cerr);
   }
  }
  report["writesStarted"]=recoveryUnknown?json(nullptr):json(transaction.writes);
  if(args.mode!=Mode::Preflight){report["status"]=completed?"pass":(!transaction.writes&&!recoveryUnknown?"blocked":"failed");exit=completed?0:(!transaction.writes&&!recoveryUnknown?3:1);}
  if(args.mode==Mode::RegisterOnce && completed){
   // Stage 2 must correlate the real DLL's unique stderr activation marker.
   // GetActiveProfile alone is intentionally not a successful activation claim.
   report["status"]="activation-unconfirmed";exit=4;
  }
 }
 CoUninitialize();std::cout<<report.dump()<<std::endl;return exit;
}
