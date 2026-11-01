#pragma once
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
json localReport(const char* mode){return {{"schema","mycomputer-activation-stage1-v1"},{"scope","mycomputer-registration-activation-only"},{"mode",mode},{"status","failed"},{"stage","completed"},{"code",0},{"writesStarted",false},{"cleanupVerified",false},{"preconditions",localConditions()},{"prerequisitesSatisfied",false},{"actualHostName",nullptr},{"threadLanguage",nullptr},{"currentLanguage",nullptr},{"dllSha256",nullptr},{"dllPresent",nullptr},{"publisherTrust","not-established"},{"brokerEditingVerified",false},{"profileActivationApiVerified",false},{"actualDllActivationVerified",false}};}
}
int wmain(int argc,wchar_t** argv){
 std::vector<std::wstring> arguments;for(int i=1;i<argc;++i)arguments.emplace_back(argv[i]);
 const auto args=yime::stage1::ParseArguments(arguments);using Mode=yime::stage1::Mode;
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
    localMachineGate();ledger.load(args.ledger);transaction.initialize();report["dllSha256"]=ledger.data.at("dllSha256");report["dllPresent"]=ledger.dllLock.file!=INVALID_HANDLE_VALUE;
    transaction.writes=ledger.data.at("comAttempted").get<bool>();transaction.comOwned=ledger.data.at("comOwned").get<bool>();transaction.profileAttempted=ledger.data.at("profileAttempted").get<bool>();transaction.categoryAttempted=ledger.data.at("categoryAttempted").get<bool>();transaction.enableAttempted=ledger.data.at("enableAttempted").get<bool>();
    // load() proves the original PID+creation-time process is dead, not merely
    // unreachable. Process-local activation cannot survive its termination.
    yime::stage1::LedgerFlags flags{ledger.data.at("preflightAbsent").get<bool>(),transaction.writes,transaction.comOwned,transaction.profileAttempted,transaction.categoryAttempted,transaction.enableAttempted,ledger.data.at("activationAttempted").get<bool>(),ledger.data.at("cleanupVerified").get<bool>()};
    if(flags.cleanupVerified){registryAbsent();apiAbsent(transaction.languages.Get(),transaction.profiles.Get(),transaction.categories.Get());}
    else{
     require(yime::stage1::CanRecover(flags,ledger.ownerState,ledger.bindingVerified),"recovery-ownership-not-proven");
     if(transaction.writes)require(elevated(),"recovery-elevation-required");transaction.cleanup();require(transaction.cleanupOK,"recovery-cleanup-failed");
     registryAbsent();apiAbsent(transaction.languages.Get(),transaction.profiles.Get(),transaction.categories.Get());
     ledger.mark("cleanupVerified");
    }
    recoveryUnknown=false;report["cleanupVerified"]=true;completed=true;
   }
  }catch(const Failure& failure){report["stage"]=failure.stage;report["code"]=static_cast<unsigned long>(failure.code);}catch(...){report["stage"]="unclassified-exception";report["code"]=static_cast<unsigned long>(E_FAIL);}
  if(args.mode==Mode::RegisterOnce && transaction.writes){
   try{transaction.cleanup();if(transaction.cleanupOK){ledger.mark("cleanupVerified");report["cleanupVerified"]=true;}}
   catch(const Failure& failure){transaction.cleanupCheck(failure.code,failure.stage);}catch(...){transaction.cleanupCheck(E_FAIL,"cleanup-exception");}
   if(!transaction.cleanupOK){report["stage"]=transaction.cleanupStage;report["code"]=static_cast<unsigned long>(transaction.cleanupCode);completed=false;}
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
