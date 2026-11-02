#pragma once
#include <array>
#include <cstdint>
#include <optional>
namespace yime::profile_observation {
struct Guid {
 std::uint32_t data1=0;std::uint16_t data2=0,data3=0;std::array<std::uint8_t,8> data4{};
 bool operator==(const Guid& other)const noexcept{return data1==other.data1&&data2==other.data2&&data3==other.data3&&data4==other.data4;}
};
struct Profile {
 std::uint32_t type=0;std::uint16_t language=0;Guid clsid,profile;
 bool operator==(const Profile& other)const noexcept{return type==other.type&&language==other.language&&clsid==other.clsid&&profile==other.profile;}
};
struct Observation {std::uint32_t hresult;Profile expected;std::optional<Profile> actual;};
template<class ReadActual> Observation Observe(std::uint32_t hr,const Profile& expected,ReadActual&& readActual){
 Observation result{hr,expected,std::nullopt};
 if(hr==0)result.actual=readActual(); // Non-S_OK output must never be interpreted.
 return result;
}
struct Failure {const char* stage;const char* kind;std::uint32_t code;};
// Values only; no allocation, formatting or sink calls decide the primary error.
inline std::optional<Failure> Decide(const Observation& value) noexcept {
 if(value.hresult&0x80000000U)return Failure{"registered active profile","hresult",value.hresult};
 if(value.hresult==1)return Failure{"registered active profile unavailable","hresult",1};
 if(value.hresult!=0)return Failure{"registered active profile incomplete","hresult",value.hresult};
 if(!value.actual||!(*value.actual==value.expected))return Failure{"registered profile mismatch","assertion",0};
 return std::nullopt;
}
template<class Sink> void EmitFailureBestEffort(const Observation& observation,const Failure& failure,Sink&& sink) noexcept {
 try{sink(observation,failure);}catch(...){/* Evidence loss cannot replace the primary failure. */}
}
template<class Primary,class Sink> [[noreturn]] void Reject(const Observation& observation,const Failure& failure,const Primary& primary,Sink&& sink){
 EmitFailureBestEffort(observation,failure,static_cast<Sink&&>(sink));
 throw primary;
}
// The native adapter supplies no actual value unless GetActiveProfile returned S_OK.
template<class Sink> void Require(const Observation& observation,Sink&& sink){
 const auto failure=Decide(observation);
 if(!failure)return;
 const Failure primary=*failure;
 Reject(observation,primary,primary,static_cast<Sink&&>(sink));
}
}
