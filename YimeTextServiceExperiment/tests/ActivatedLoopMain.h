#pragma once
#include "ActivatedLoopConfig.h"
// Separate opt-in entry. No recovery, no registration mode on the old tool changes.
namespace {
struct LoopHandle {HANDLE value=nullptr;~LoopHandle(){if(value&&value!=INVALID_HANDLE_VALUE)CloseHandle(value);}};
std::wstring loopWide(const std::string& value){
 int size=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),nullptr,0);
 require(size>0,"loop-utf8");std::wstring result(size,L'\0');
 require(MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),result.data(),size)==size,"loop-utf8");return result;
}
struct LoopBroker {
 LoopHandle process,file;DWORD session=0;unsigned long long made=0;
 void alive(){require(WaitForSingleObject(process.value,0)==WAIT_TIMEOUT,"loop-broker-not-alive");}
 void open(const json& config){
  const DWORD pid=config.at("brokerPID").get<DWORD>();require(pid!=GetCurrentProcessId(),"loop-broker-self");
  process.value=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION|SYNCHRONIZE,FALSE,pid);require(process.value!=nullptr,"loop-broker-process");alive();made=Ledger::creation(process.value);
  DWORD mine=0;require(ProcessIdToSessionId(pid,&session)&&ProcessIdToSessionId(GetCurrentProcessId(),&mine)&&session==mine,"loop-broker-session");
  LoopHandle otherToken,ownToken;
  require(OpenProcessToken(process.value,TOKEN_QUERY,&otherToken.value)&&OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&ownToken.value),"loop-broker-token");
  auto user=[](HANDLE token){DWORD size=0;GetTokenInformation(token,TokenUser,nullptr,0,&size);require(size>0&&size<=65536,"loop-token-bound");std::vector<BYTE> data(size);require(GetTokenInformation(token,TokenUser,data.data(),size,&size)!=FALSE,"loop-token-user");return data;};
  auto a=user(otherToken.value),b=user(ownToken.value);require(EqualSid(reinterpret_cast<TOKEN_USER*>(a.data())->User.Sid,reinterpret_cast<TOKEN_USER*>(b.data())->User.Sid)!=FALSE,"loop-broker-sid");
  TOKEN_STATISTICS first{},second{};DWORD bytes=0;
  require(GetTokenInformation(otherToken.value,TokenStatistics,&first,sizeof(first),&bytes)&&GetTokenInformation(ownToken.value,TokenStatistics,&second,sizeof(second),&bytes),"loop-token-statistics");
  require(first.AuthenticationId.LowPart==second.AuthenticationId.LowPart&&first.AuthenticationId.HighPart==second.AuthenticationId.HighPart,"loop-broker-logon");
  std::wstring image(32768,L'\0');DWORD chars=static_cast<DWORD>(image.size());require(QueryFullProcessImageNameW(process.value,0,image.data(),&chars)!=FALSE,"loop-broker-image");image.resize(chars);
  const auto expected=loopWide(config.at("brokerImage").get<std::string>());require(image.size()==expected.size()&&_wcsicmp(image.c_str(),expected.c_str())==0,"loop-broker-image-mismatch");
  file.value=CreateFileW(image.c_str(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);require(file.value!=INVALID_HANDLE_VALUE,"loop-broker-file-lock");
  LARGE_INTEGER size{};require(GetFileSizeEx(file.value,&size)&&size.QuadPart>0&&size.QuadPart<=128*1024*1024,"loop-broker-size");
  std::vector<BYTE> data(static_cast<size_t>(size.QuadPart));DWORD read=0;
  require(ReadFile(file.value,data.data(),static_cast<DWORD>(data.size()),&read,nullptr)&&read==data.size(),"loop-broker-read");
  BCRYPT_ALG_HANDLE algorithm=nullptr;struct Free{BCRYPT_ALG_HANDLE& value;~Free(){if(value)BCryptCloseAlgorithmProvider(value,0);}}free{algorithm};
  require(BCryptOpenAlgorithmProvider(&algorithm,BCRYPT_SHA256_ALGORITHM,nullptr,0)==0,"loop-broker-hash-provider");BYTE digest[32]{};
  require(BCryptHash(algorithm,nullptr,0,data.data(),static_cast<ULONG>(data.size()),digest,sizeof(digest))==0,"loop-broker-hash");
  constexpr char digits[]="0123456789abcdef";std::string hash;for(BYTE byte:digest){hash.push_back(digits[byte>>4]);hash.push_back(digits[byte&15]);}
  require(hash==config.at("brokerSHA256").get<std::string>(),"loop-broker-hash-mismatch");alive();
 }
};
std::string loopInput(){std::string line;char c;bool ended=false;while(std::cin.get(c)){if(c=='\n'){ended=true;break;}require(line.size()<16384,"loop-config-bound");line+=c;}require(ended&&!line.empty(),"loop-config-frame");return line;}
json loopFailure(const char* stage,const char* kind,unsigned long code){return {{"stage",stage},{"kind",kind},{"code",code}};}
}
int wmain(int argc,wchar_t** argv){
 json report={{"schema","activated-loop-result-v1"},{"status","blocked"},{"writesStarted",false},{"cleanupVerified",false},{"operationFailure",nullptr},{"cleanupFailure",nullptr},{"hostResult",nullptr},{"hostPID",GetCurrentProcessId()},{"brokerPID",nullptr},{"windowsSessionID",nullptr},{"brokerCreationTime",nullptr},{"ledgerOwnerPID",nullptr},{"ledgerOwnerCreationTime",nullptr},{"publisherTrust","not-established"}};
 std::vector<std::wstring> arguments;for(int i=1;i<argc;++i)arguments.emplace_back(argv[i]);
 if(arguments.size()!=7||arguments[0]!=L"--register-edit-once"){
  report["operationFailure"]=loopFailure("loop-arguments","hresult",static_cast<unsigned long>(E_INVALIDARG));std::cout<<report.dump()<<std::endl;return 3;
 }
 arguments[0]=L"--register-once";const auto args=yime::stage1::ParseArguments(arguments);
 if(args.mode!=yime::stage1::Mode::RegisterOnce){report["operationFailure"]=loopFailure("loop-arguments","hresult",static_cast<unsigned long>(E_INVALIDARG));std::cout<<report.dump()<<std::endl;return 3;}
 HRESULT initialized=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);if(FAILED(initialized)){report["operationFailure"]=loopFailure("loop-com-initialize","hresult",static_cast<unsigned long>(initialized));std::cout<<report.dump()<<std::endl;return 3;}
 bool complete=false;int result=1;
 {
  Transaction transaction;Ledger ledger;transaction.ledger=&ledger;LoopBroker broker;
  try{
   json config;try{config=yime::activated::ParseConfig(loopInput());}catch(const Failure&){throw;}catch(...){throw Failure{"loop-config-invalid",E_INVALIDARG};}
   require(config.at("hostPID").get<DWORD>()==GetCurrentProcessId(),"loop-host-pid");broker.open(config);
   report["brokerPID"]=config.at("brokerPID");report["windowsSessionID"]=broker.session;report["brokerCreationTime"]=broker.made;
   auto preflight=localReport("preflight");const auto facts=inspectLocal(transaction,ledger,args,preflight);
   if(preflight.at("stage")!="completed")report["operationFailure"]={{"stage",preflight.at("stage")},{"kind","hresult"},{"code",preflight.at("code")}};
   require(yime::stage1::CanRegister(facts)&&report["operationFailure"].is_null(),"loop-registration-preconditions");
   broker.alive();ledger.create(args.ledger,ledger.dllLock.canonical);report["ledgerOwnerPID"]=ledger.data.at("pid");report["ledgerOwnerCreationTime"]=ledger.data.at("creation");
   transaction.run(ledger.dllLock.canonical,[&]{
    broker.alive();auto host=RunActivatedRegisteredHost(config.dump(),ledger.dllLock.canonical);
    if(!host.completed){report["operationFailure"]=loopFailure(host.stage,host.kind,host.code);throw Failure{"loop-registered-host-failed",E_FAIL};}
    report["hostResult"]=json::parse(host.hostResult);complete=true;
   });
  }catch(const Failure& f){if(report["operationFailure"].is_null())report["operationFailure"]=loopFailure(f.stage,"hresult",static_cast<unsigned long>(f.code));}
   catch(...){if(report["operationFailure"].is_null())report["operationFailure"]=loopFailure("loop-exception","exception",0);}
  if(transaction.writes){
   try{transaction.cleanup();if(transaction.cleanupOK){ledger.mark("cleanupVerified");report["cleanupVerified"]=true;}}
   catch(const Failure& f){transaction.cleanupCheck(f.code,f.stage);}catch(...){transaction.cleanupCheck(E_FAIL,"loop-cleanup-exception");}
   if(!transaction.cleanupOK)report["cleanupFailure"]=loopFailure(transaction.cleanupStage,"hresult",static_cast<unsigned long>(transaction.cleanupCode));
  }
  report["writesStarted"]=transaction.writes;
  const bool passed=complete&&report["operationFailure"].is_null()&&report["cleanupFailure"].is_null()&&report["cleanupVerified"]==true;
  report["status"]=passed?"passed":transaction.writes?"failed":"blocked";result=passed?0:transaction.writes?1:3;
 }
 CoUninitialize();std::cout<<report.dump()<<std::endl;return result;
}
