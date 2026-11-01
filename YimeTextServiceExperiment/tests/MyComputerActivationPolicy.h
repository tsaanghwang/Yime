#pragma once
#include <string>
#include <vector>
namespace yime::stage1 {
enum class Mode { Preflight, RegisterOnce, Recover, Verify, Invalid };
struct Arguments { Mode mode=Mode::Invalid; std::wstring dll,sha256,ledger; };
inline bool GoodHash(const std::wstring& value) {
 if(value.size()!=64)return false;
 for(wchar_t c:value)if(!((c>=L'0'&&c<=L'9')||(c>=L'a'&&c<=L'f')))return false;
 return true;
}
inline Arguments ParseArguments(const std::vector<std::wstring>& args) {
 Arguments result;
 if(args.empty() || (args.size()==1 && args[0]==L"--preflight")){result.mode=Mode::Preflight;return result;}
 if(args.size()==1 && args[0]==L"--verify"){result.mode=Mode::Verify;return result;}
 if(args.size()==3 && args[0]==L"--recover" && args[1]==L"--ledger" && !args[2].empty()){result.mode=Mode::Recover;result.ledger=args[2];return result;}
 const bool preflight=args.size()==5 && args[0]==L"--preflight";
 const bool registration=args.size()==7 && args[0]==L"--register-once" && args[5]==L"--ledger" && !args[6].empty();
 if((preflight||registration) && args[1]==L"--dll" && !args[2].empty() && args[3]==L"--sha256" && GoodHash(args[4])){
  result.mode=preflight?Mode::Preflight:Mode::RegisterOnce;result.dll=args[2];result.sha256=args[4];if(registration)result.ledger=args[6];
 }
 return result;
}
struct PreflightFacts { bool nativeX64=false,hostMatches=false,hkl0804=false,tsf0804=false,elevated=false,identityAbsent=false,dllVerified=false,directTestAbsent=false; };
inline bool CanRegister(const PreflightFacts& f){return f.nativeX64&&f.hostMatches&&f.hkl0804&&f.tsf0804&&f.elevated&&f.identityAbsent&&f.dllVerified&&f.directTestAbsent;}
struct LedgerFlags { bool preflightAbsent=false,comAttempted=false,comOwned=false,profileAttempted=false,categoryAttempted=false,enableAttempted=false,activationAttempted=false,cleanupVerified=false; };
inline bool ValidLedgerOrder(const LedgerFlags& f){return (!f.comAttempted||f.preflightAbsent)&&(!f.comOwned||f.comAttempted)&&(!f.profileAttempted||f.comOwned)&&(!f.categoryAttempted||f.profileAttempted)&&(!f.enableAttempted||f.categoryAttempted)&&(!f.activationAttempted||f.enableAttempted);}
enum class OwnerState { Alive, DeadVerified, Unknown };
inline bool CanRecover(const LedgerFlags& f,OwnerState owner,bool authenticatedBinding){return authenticatedBinding&&owner==OwnerState::DeadVerified&&ValidLedgerOrder(f)&&(!f.comAttempted||f.comOwned);}
} // namespace yime::stage1
