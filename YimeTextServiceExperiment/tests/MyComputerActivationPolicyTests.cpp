// Portable tests of the production decision policy, not Windows registration evidence.
#include "MyComputerActivationPolicy.h"
#include <iostream>
#include <stdexcept>
#include <vector>

using namespace yime::stage1;
namespace {
void check(bool condition, const char* name) {
 if (!condition) throw std::runtime_error(name);
}
void commandPolicy() {
 check(ParseArguments({}).mode == Mode::Preflight, "no arguments must only preflight");
 check(ParseArguments({L"--preflight"}).mode == Mode::Preflight, "explicit preflight");
 check(ParseArguments({L"--verify"}).mode == Mode::Verify, "verify only");
 const std::wstring hash(64, L'a');
 const std::wstring dll=L"C:\\stage1\\YimeTextService18u.dll", ledger=L"C:\\stage1\\registration-ledger.json";
 auto preflight=ParseArguments({L"--preflight",L"--dll",dll,L"--sha256",hash});
 check(preflight.mode==Mode::Preflight && preflight.dll==dll && preflight.sha256==hash, "preflight binding");
 auto run=ParseArguments({L"--register-once",L"--dll",dll,L"--sha256",hash,L"--ledger",ledger});
 check(run.mode==Mode::RegisterOnce && run.dll==dll && run.sha256==hash && run.ledger==ledger, "explicit registration only");
 auto recover=ParseArguments({L"--recover",L"--ledger",ledger});
 check(recover.mode==Mode::Recover && recover.ledger==ledger, "explicit recovery only");
 for(const auto& args: std::vector<std::vector<std::wstring>>{
  {L"--register-once"},{L"--recover"},{L"--unknown"},{L"--verify",L"--register-once"},
  {L"--dll",dll,L"--sha256",hash,L"--ledger",ledger},
  {L"--register-once",L"--dll",dll,L"--sha256",hash},
  {L"--register-once",L"--dll",dll,L"--sha256",hash,L"--ledger",ledger,L"--retry"},
  {L"--recover",L"--ledger",ledger,L"--register-once"},
  {L"--preflight",L"--dll",dll,L"--sha256",L"bad"}})
  check(ParseArguments(args).mode==Mode::Invalid,"unknown/incomplete/combined commands must reject");
 check(GoodHash(hash),"valid lowercase hash");
 for(const auto& bad: std::vector<std::wstring>{L"",std::wstring(63,L'a'),std::wstring(65,L'a'),std::wstring(64,L'A'),std::wstring(64,L'g')})
  check(!GoodHash(bad),"invalid hash rejected");
}
void preflightPolicy() {
 PreflightFacts good{true,true,true,true,true,true,true,true};
 check(CanRegister(good),"all preconditions permit explicit register gate");
 const std::vector<bool PreflightFacts::*> fields={&PreflightFacts::nativeX64,&PreflightFacts::hostMatches,
  &PreflightFacts::hkl0804,&PreflightFacts::tsf0804,&PreflightFacts::elevated,
  &PreflightFacts::identityAbsent,&PreflightFacts::dllVerified,&PreflightFacts::directTestAbsent};
 for(auto field:fields) {auto bad=good;bad.*field=false;check(!CanRegister(bad),"each missing/unknown fact must block");}
 check(!CanRegister(PreflightFacts{}),"unknown facts cannot permit registration");
 // nativeX64=false represents ARM64, x86, emulation or unknown; detecting which
 // requires Windows APIs and is deliberately not claimed by these bool tests.
}
void ledgerPolicy() {
 const std::vector<bool LedgerFlags::*> fields={&LedgerFlags::preflightAbsent,&LedgerFlags::comAttempted,
  &LedgerFlags::comOwned,&LedgerFlags::profileAttempted,&LedgerFlags::categoryAttempted,
  &LedgerFlags::enableAttempted,&LedgerFlags::activationAttempted,&LedgerFlags::cleanupVerified};
 // Exhaust all flag combinations: no child attempt is valid without its prior
 // durable ownership/attempt facts. cleanupVerified is independent evidence.
 for(unsigned mask=0;mask<256;++mask) {
  LedgerFlags f{};for(unsigned i=0;i<fields.size();++i)f.*fields[i]=(mask&(1u<<i))!=0;
  const bool ordered=(!f.comAttempted||f.preflightAbsent)&&(!f.comOwned||f.comAttempted)&&
   (!f.profileAttempted||f.comOwned)&&(!f.categoryAttempted||f.profileAttempted)&&
   (!f.enableAttempted||f.categoryAttempted)&&(!f.activationAttempted||f.enableAttempted);
  check(ValidLedgerOrder(f)==ordered,"ledger dependency order");
  check(!CanRecover(f,OwnerState::Alive,true),"live owner forbids cleanup");
  check(!CanRecover(f,OwnerState::Unknown,true),"unknown owner never guessed dead");
  check(!CanRecover(f,OwnerState::DeadVerified,false),"unauthenticated binding cannot recover");
  check(CanRecover(f,OwnerState::DeadVerified,true)==(ordered&&(!f.comAttempted||f.comOwned)),"recovery ownership policy");
 }
}
}
int main() {
 try {commandPolicy();preflightPolicy();ledgerPolicy();std::cout<<"3 portable policy groups passed; Windows APIs not exercised\n";return 0;}
 catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}
}
