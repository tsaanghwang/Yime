#include "../InputAbortDiagnostic.h"
#include <stdexcept>
#include <string>
#include <iostream>
namespace d=yime::abortdiag;
std::string captured;
void capture(const char* text,size_t size){captured.assign(text,size);}
void broken(const char*,size_t){throw std::runtime_error("SECRET exception path C:/secret body candidate code");}
void check(bool ok){if(!ok)throw std::runtime_error("diagnostic policy test failed");}
int main(){
    d::State state;state.epoch=7;state.pendingEpoch=6;state.phase=2;state.active=true;
    d::Emit(d::Stage::RouteAction,d::Reason::StaleTarget,0x80004004u,state,capture);
    check(captured.find("\"schema\":\"18u-input-abort-diagnostic-v1\"")!=std::string::npos);
    check(captured.find("\"epoch\":7")!=std::string::npos && captured.find("\"pendingEpoch\":6")!=std::string::npos);
    check(captured.find("\"result\":2147500036")!=std::string::npos);
    check(captured.find("\"resultKnown\":true")!=std::string::npos);
    check(captured.size()<768 && captured.back()=='\n' && captured.find('\n')==captured.size()-1);
    const auto previous=captured;
    d::Emit(d::Stage::RouteAction,d::Reason::UnknownException,123,state,broken);
    check(captured==previous); // Throwing output cannot escape or change caller evidence/result.
    d::Emit(d::Stage::RouteAction,d::Reason::UnknownException,123,state,nullptr);
    check(d::ClassifyTransportError("Broker ReadFile timeout")==d::Reason::TransportReadTimeout);
    check(d::ClassifyTransportError("Broker WriteFile timeout")==d::Reason::TransportWriteTimeout);
    check(d::ClassifyTransportError("Broker transport cancelled")==d::Reason::TransportCancelled);
    check(d::ClassifyTransportError("ReadFile failed with Windows error 109")==d::Reason::TransportIOError);
    check(d::ClassifyTransportError("ReadFile failed with Windows error SECRET")==d::Reason::TransportFrameFailure);
    check(d::ClassifyTransportError("")==d::Reason::TransportNoDetail);
    check(d::ClassifyTransportError("multiple unframed Broker responses")==d::Reason::TransportMultipleFrames);
    check(d::ClassifyTransportError("Broker response exceeds protocol limit")==d::Reason::TransportOversize);
    const std::string hostile="SECRET正文候选代码 C:/private/file\n{\"injected\":true}";
    d::Emit(d::Stage::Transport,d::ClassifyTransportError(hostile),0,{},capture);
    check(captured.find("\"resultKnown\":false")!=std::string::npos);
    check(captured.find("SECRET")==std::string::npos && captured.find("private")==std::string::npos && captured.find("injected")==std::string::npos);
    d::Emit(static_cast<d::Stage>(999),static_cast<d::Reason>(999),0,{},capture);
    check(captured.find("\"stage\":\"Unknown\"")!=std::string::npos && captured.find("\"reason\":\"Unknown\"")!=std::string::npos);
    std::cout<<"diagnostic helper: fixed vocabulary, redaction, bounded output, throwing sink passed\n";
}
