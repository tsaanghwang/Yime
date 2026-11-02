#pragma once
#include <cstdint>

namespace yime::registered_edit {
// Pure ordering contract used by the real registration-owning process.
// A queued edit is never a completed edit. Issuing selection consumes the one
// allowance even when completion is missing; cleanup cannot clear a failure.
class Evidence {
public:
    enum class Stage { Fresh, Registered, Attached, Connected, Issued, Applied, Readback, Revoked, Absent };
    bool registered(std::uint32_t owner,std::uint32_t brokerTarget) {
        if(!owner || owner!=brokerTarget)return reject();
        owner_=owner;target_=brokerTarget;return next(Stage::Fresh,Stage::Registered);
    }
    bool attached(bool windowsInstance){return windowsInstance?next(Stage::Registered,Stage::Attached):reject();}
    bool connected(){return next(Stage::Attached,Stage::Connected);}
    bool issue(){++attempts_;return attempts_==1?next(Stage::Connected,Stage::Issued):reject();}
    bool completed(bool applied){return applied?next(Stage::Issued,Stage::Applied):reject();}
    bool readback(bool exact){return exact?next(Stage::Applied,Stage::Readback):reject();}
    void fail() noexcept {failed_=true;}
    void revoked(bool confirmed) noexcept {
        revoked_=confirmed;
        if(!confirmed || stage_!=Stage::Readback)failed_=true;
        stage_=Stage::Revoked;
    }
    void absent(bool confirmed) noexcept {
        absent_=confirmed;
        if(!confirmed || stage_!=Stage::Revoked)failed_=true;
        stage_=Stage::Absent;
    }
    bool passed() const noexcept {return !failed_ && attempts_==1 && owner_ && owner_==target_ && revoked_ && absent_ && stage_==Stage::Absent;}
    unsigned attempts() const noexcept {return attempts_;}
private:
    bool reject() noexcept {failed_=true;return false;}
    bool next(Stage before,Stage after) noexcept {
        if(failed_ || stage_!=before)return reject();
        stage_=after;return true;
    }
    Stage stage_=Stage::Fresh;
    bool failed_=false,revoked_=false,absent_=false;
    std::uint32_t owner_=0,target_=0;
    unsigned attempts_=0;
};
}
