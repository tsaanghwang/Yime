#pragma once
// Diagnostic-only fixed vocabulary. Never accepts text, paths, request bytes or exception.what().
#include <cstdint>
#include <initializer_list>
#include <cstdio>
#include <string_view>
namespace yime::abortdiag {
enum class Stage { ServiceConnect, ServiceAction, ServicePoll, RouteCheck, RouteAction, RoutePoll, RouteConnect, RouteFailed, Target, Transport, Lifecycle };
enum class Reason { Unknown,
AbsoluteLocalImageRequired,
ActionEnvelope,
ActionLimit,
BrokerIdentityOrFocusMismatch,
BrokerOkFalse,
BrokerRejectedOrMalformedResponse,
Busy,
CommitBounds,
ContextChanged,
ContextLease,
ContextQueryFailed,
ContextRevoked,
DedicatedLocalPipeRequired,
Disconnect,
DocumentChanged,
DocumentQueryFailed,
ExecutionGuardDenied,
ExpectedBrokerPidRequired,
Failed,
FocusRevoked,
ForbiddenActionField,
ForegroundChanged,
ForeignCommitFocus,
ForeignSession,
ImagePath,
InvalidDedicatedPipeSuffix,
JsonException,
KeyFocusMissing,
LeaseEncoding,
MissingOutput,
NoManager,
NoPhase,
NoRoute,
ReceiptMismatch,
RequestLimit,
ResponseAllocation,
ResponseEncoding,
ResponseSize,
RevokedTarget,
RouteInactive,
SessionMissing,
StaleTarget,
StandardException,
TargetStateMissing,
TipHasNoOwnFocusedContext,
TipHostMustOwnActualForegroundThreadWindow,
TransportAlreadyRunning,
TransportCancellation,
TransportCancelled,
TransportConnectTimeout,
TransportEvent,
TransportFailedNoReplay,
TransportFrameFailure,
TransportIOError,
TransportImageMismatch,
TransportImageQuery,
TransportModulePin,
TransportMultipleFrames,
TransportNoDetail,
TransportOpenProcess,
TransportOversize,
TransportOwnerLogon,
TransportOwnerSID,
TransportOwnerSession,
TransportOwnerToken,
TransportPID,
TransportPipeOpen,
TransportPipePID,
TransportProcessExited,
TransportReadTimeout,
TransportTokenSize,
TransportTokenStatistics,
TransportTokenUser,
TransportUnavailable,
TransportWorkerCreation,
TransportWriteTimeout,
UnknownException,
UnsupportedAction,
WrongThread
};
inline const char* Name(Stage value) noexcept {
    switch(value) {
    case Stage::ServiceConnect: return "ServiceConnect";
    case Stage::ServiceAction: return "ServiceAction";
    case Stage::ServicePoll: return "ServicePoll";
    case Stage::RouteCheck: return "RouteCheck";
    case Stage::RouteAction: return "RouteAction";
    case Stage::RoutePoll: return "RoutePoll";
    case Stage::RouteConnect: return "RouteConnect";
    case Stage::RouteFailed: return "RouteFailed";
    case Stage::Target: return "Target";
    case Stage::Transport: return "Transport";
    case Stage::Lifecycle: return "Lifecycle";
    } return "Unknown";
}
inline const char* Name(Reason value) noexcept {
    switch(value) {
    case Reason::Unknown: return "Unknown";
    case Reason::AbsoluteLocalImageRequired: return "AbsoluteLocalImageRequired";
    case Reason::ActionEnvelope: return "ActionEnvelope";
    case Reason::ActionLimit: return "ActionLimit";
    case Reason::BrokerIdentityOrFocusMismatch: return "BrokerIdentityOrFocusMismatch";
    case Reason::BrokerOkFalse: return "BrokerOkFalse";
    case Reason::BrokerRejectedOrMalformedResponse: return "BrokerRejectedOrMalformedResponse";
    case Reason::Busy: return "Busy";
    case Reason::CommitBounds: return "CommitBounds";
    case Reason::ContextChanged: return "ContextChanged";
    case Reason::ContextLease: return "ContextLease";
    case Reason::ContextQueryFailed: return "ContextQueryFailed";
    case Reason::ContextRevoked: return "ContextRevoked";
    case Reason::DedicatedLocalPipeRequired: return "DedicatedLocalPipeRequired";
    case Reason::Disconnect: return "Disconnect";
    case Reason::DocumentChanged: return "DocumentChanged";
    case Reason::DocumentQueryFailed: return "DocumentQueryFailed";
    case Reason::ExecutionGuardDenied: return "ExecutionGuardDenied";
    case Reason::ExpectedBrokerPidRequired: return "ExpectedBrokerPidRequired";
    case Reason::Failed: return "Failed";
    case Reason::FocusRevoked: return "FocusRevoked";
    case Reason::ForbiddenActionField: return "ForbiddenActionField";
    case Reason::ForegroundChanged: return "ForegroundChanged";
    case Reason::ForeignCommitFocus: return "ForeignCommitFocus";
    case Reason::ForeignSession: return "ForeignSession";
    case Reason::ImagePath: return "ImagePath";
    case Reason::InvalidDedicatedPipeSuffix: return "InvalidDedicatedPipeSuffix";
    case Reason::JsonException: return "JsonException";
    case Reason::KeyFocusMissing: return "KeyFocusMissing";
    case Reason::LeaseEncoding: return "LeaseEncoding";
    case Reason::MissingOutput: return "MissingOutput";
    case Reason::NoManager: return "NoManager";
    case Reason::NoPhase: return "NoPhase";
    case Reason::NoRoute: return "NoRoute";
    case Reason::ReceiptMismatch: return "ReceiptMismatch";
    case Reason::RequestLimit: return "RequestLimit";
    case Reason::ResponseAllocation: return "ResponseAllocation";
    case Reason::ResponseEncoding: return "ResponseEncoding";
    case Reason::ResponseSize: return "ResponseSize";
    case Reason::RevokedTarget: return "RevokedTarget";
    case Reason::RouteInactive: return "RouteInactive";
    case Reason::SessionMissing: return "SessionMissing";
    case Reason::StaleTarget: return "StaleTarget";
    case Reason::StandardException: return "StandardException";
    case Reason::TargetStateMissing: return "TargetStateMissing";
    case Reason::TipHasNoOwnFocusedContext: return "TipHasNoOwnFocusedContext";
    case Reason::TipHostMustOwnActualForegroundThreadWindow: return "TipHostMustOwnActualForegroundThreadWindow";
    case Reason::TransportAlreadyRunning: return "TransportAlreadyRunning";
    case Reason::TransportCancellation: return "TransportCancellation";
    case Reason::TransportCancelled: return "TransportCancelled";
    case Reason::TransportConnectTimeout: return "TransportConnectTimeout";
    case Reason::TransportEvent: return "TransportEvent";
    case Reason::TransportFailedNoReplay: return "TransportFailedNoReplay";
    case Reason::TransportFrameFailure: return "TransportFrameFailure";
    case Reason::TransportIOError: return "TransportIOError";
    case Reason::TransportImageMismatch: return "TransportImageMismatch";
    case Reason::TransportImageQuery: return "TransportImageQuery";
    case Reason::TransportModulePin: return "TransportModulePin";
    case Reason::TransportMultipleFrames: return "TransportMultipleFrames";
    case Reason::TransportNoDetail: return "TransportNoDetail";
    case Reason::TransportOpenProcess: return "TransportOpenProcess";
    case Reason::TransportOversize: return "TransportOversize";
    case Reason::TransportOwnerLogon: return "TransportOwnerLogon";
    case Reason::TransportOwnerSID: return "TransportOwnerSID";
    case Reason::TransportOwnerSession: return "TransportOwnerSession";
    case Reason::TransportOwnerToken: return "TransportOwnerToken";
    case Reason::TransportPID: return "TransportPID";
    case Reason::TransportPipeOpen: return "TransportPipeOpen";
    case Reason::TransportPipePID: return "TransportPipePID";
    case Reason::TransportProcessExited: return "TransportProcessExited";
    case Reason::TransportReadTimeout: return "TransportReadTimeout";
    case Reason::TransportTokenSize: return "TransportTokenSize";
    case Reason::TransportTokenStatistics: return "TransportTokenStatistics";
    case Reason::TransportTokenUser: return "TransportTokenUser";
    case Reason::TransportUnavailable: return "TransportUnavailable";
    case Reason::TransportWorkerCreation: return "TransportWorkerCreation";
    case Reason::TransportWriteTimeout: return "TransportWriteTimeout";
    case Reason::UnknownException: return "UnknownException";
    case Reason::UnsupportedAction: return "UnsupportedAction";
    case Reason::WrongThread: return "WrongThread";
    } return "Unknown";
}
struct State {
    uint64_t epoch=0,pendingEpoch=0,editEpoch=0;
    unsigned phase=0;
    bool active=false,bound=false,editOutstanding=false,route=false,manager=false,keyFocus=false;
};
using Sink=void(*)(const char*,size_t);
inline void Stderr(const char* bytes,size_t size) { (void)std::fwrite(bytes,1,size,stderr); }
inline void Emit(Stage stage,Reason reason,uint32_t result=0,const State& s={},Sink sink=Stderr) noexcept {
    // One bounded write; no flush/retry, allocation, dynamic exception or package content.
    char line[768];
    const int n=std::snprintf(line,sizeof(line),
        "{\"schema\":\"18u-input-abort-diagnostic-v1\",\"stage\":\"%s\",\"reason\":\"%s\",\"result\":%u,\"resultKnown\":%s,"
        "\"epoch\":%llu,\"pendingEpoch\":%llu,\"editEpoch\":%llu,\"phase\":%u,"
        "\"active\":%s,\"bound\":%s,\"editOutstanding\":%s,\"route\":%s,\"manager\":%s,\"keyFocus\":%s}\n",
        Name(stage),Name(reason),static_cast<unsigned>(result),result?"true":"false",
        static_cast<unsigned long long>(s.epoch),static_cast<unsigned long long>(s.pendingEpoch),static_cast<unsigned long long>(s.editEpoch),s.phase,
        s.active?"true":"false",s.bound?"true":"false",s.editOutstanding?"true":"false",s.route?"true":"false",s.manager?"true":"false",s.keyFocus?"true":"false");
    if(n<=0 || static_cast<size_t>(n)>=sizeof(line) || !sink)return;
    try {sink(line,static_cast<size_t>(n));}catch(...){} // Never replace the original result.
}
inline Reason ClassifyTransportError(std::string_view error) noexcept {
    if(error.empty())return Reason::TransportNoDetail;
    if(error=="Broker transport cancelled")return Reason::TransportCancelled;
    if(error=="Broker ReadFile timeout")return Reason::TransportReadTimeout;
    if(error=="Broker WriteFile timeout")return Reason::TransportWriteTimeout;
    if(error=="Broker response exceeds protocol limit")return Reason::TransportOversize;
    if(error=="multiple unframed Broker responses")return Reason::TransportMultipleFrames;
    for(const auto prefix:{std::string_view("ReadFile failed with Windows error "),std::string_view("WriteFile failed with Windows error "),std::string_view("CreateEventW failed with Windows error "),std::string_view("WaitForSingleObject failed with Windows error ")}) {
        if(error.substr(0,prefix.size())!=prefix)continue;
        const auto digits=error.substr(prefix.size());if(digits.empty()||digits.size()>10)continue;
        bool numeric=true;for(char c:digits)if(c<'0'||c>'9')numeric=false;
        if(numeric)return Reason::TransportIOError;
    }
    return Reason::TransportFrameFailure;
}
}
