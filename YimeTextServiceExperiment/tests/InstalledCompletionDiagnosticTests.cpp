#include "../InstalledCompletionDiagnostic.h"
#include "../InstalledDiscoveryDiagnostic.h"
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

using nlohmann::json;
using yime::installeddiag::CompletionResult;
void require(bool ok, const char* message) { if (!ok) throw std::runtime_error(message); }

void discoveryContracts() {
    using namespace yime::installeddiag;
    require(ForegroundRejection(true,true,10,10,20,20).reason==DiscoveryReason::Ready,"eligible foreground rejected");
    const DiscoveryRejection rejections[] = {
        ForegroundRejection(false,true,10,10,20,20),
        ForegroundRejection(true,false,0,10,0,20),
        ForegroundRejection(true,true,0,10,0,20),
        ForegroundRejection(true,true,11,10,20,20),
        ForegroundRejection(true,true,10,10,21,20),
    };
    for(unsigned i=0;i<5;++i)require(static_cast<unsigned>(rejections[i].reason)==i+1,"foreground rejection classification changed");
    require(!rejections[2].win32&&!rejections[2].hresult&&rejections[2].code==0,"foreground query borrowed a stale system code");
    DiscoveryDiagnostics queue;
    for(auto rejection:rejections)queue.Observe(rejection);
    for(auto focus: {ContextObservation{0x80070005u,false},ContextObservation{0x80070005u,true},ContextObservation{0,false},ContextObservation{0,true}}) {
        for(auto top:{ContextObservation{0x80004005u,false},ContextObservation{0,false},ContextObservation{0,true}}) {
            int focusCalls=0,topCalls=0;
            auto result=ContextRejection([&](){++focusCalls;return focus;},[&](){++topCalls;return top;});
            require(focusCalls==1&&topCalls==((focus.result&0x80000000u)||!focus.present?0:1),"context probe passed a failed/missing document");
            const auto expected=(focus.result&0x80000000u)?DiscoveryReason::GetFocusFailed:!focus.present?DiscoveryReason::NoDocument:
                (top.result&0x80000000u)?DiscoveryReason::GetTopFailed:!top.present?DiscoveryReason::NoContext:DiscoveryReason::Ready;
            require(result.reason==expected,"context rejection classification changed");
            if(result.hresult)require(result.code==((focus.result&0x80000000u)?focus.result:top.result),"original context HRESULT lost");
            queue.Observe(result);
        }
    }
    queue.Observe({DiscoveryReason::NoEndpoint,2,false,true});
    queue.Observe({static_cast<DiscoveryReason>(1000)});
    std::string frame;unsigned count=0;
    while(queue.Take(frame)) {
        const auto parsed=json::parse(frame);const auto diagnostic=parsed.at("diagnostic");
        require(parsed.size()==3&&parsed.at("operation")=="diagnostic"&&parsed.at("version")==1&&diagnostic.at("stage")=="tip-discovery","diagnostic frame version or fields changed");
        require(frame.size()<=320&&diagnostic.dump().size()<=256,"diagnostic bound exceeded");
        require(!parsed.contains("window")&&!parsed.contains("generation")&&!parsed.contains("ticket"),"target identity escaped");
        if(diagnostic.at("reason")=="foreground-query-failed")require(!diagnostic.contains("win32")&&!diagnostic.contains("hresult"),"foreground failure gained a stale error code");
        if(diagnostic.at("reason")=="tip-endpoint-unavailable")require(diagnostic.at("win32")==2&&!diagnostic.contains("hresult"),"endpoint failure lost its original Win32 error");
        ++count;
    }
    require(count==10,"missing or repeated discovery reason");
    // Model every attempted send failing/lost: observations on later ticks or
    // input-generation changes cannot requeue any consumed reason.
    for(unsigned tick=0;tick<100;++tick) {
        for(unsigned reason=1;reason<=10;++reason)queue.Observe({static_cast<DiscoveryReason>(reason),0x80004005u,true});
        require(!queue.Take(frame),"failed diagnostic was replayed");
    }
}

struct FakeDiscoveryWork {
    std::atomic<bool> done{false};
    bool ok=false;
};
struct FakeDiscoveryTransport {
    std::shared_ptr<FakeDiscoveryWork> work=std::make_shared<FakeDiscoveryWork>();
    std::vector<std::string> frames;
    uint32_t timeout=0;
    bool connect=false,failStart=false;
    unsigned cancellations=0;
    std::shared_ptr<FakeDiscoveryWork> Start(std::string frame,uint32_t value,bool opening) {
        timeout=value;connect=opening;frames.push_back(std::move(frame));
        if(failStart)throw std::runtime_error("injected worker start failure");
        return work;
    }
    void Cancel() noexcept { ++cancellations; }
};

void discoveryChannelContracts() {
    using namespace yime::installeddiag;
    using Channel=DiscoveryDiagnosticChannel<FakeDiscoveryTransport,FakeDiscoveryWork>;
    std::vector<std::shared_ptr<FakeDiscoveryTransport>> attempts;
    auto factory=[&](){auto transport=std::make_shared<FakeDiscoveryTransport>();attempts.push_back(transport);return transport;};
    Channel channel;
    channel.Observe({DiscoveryReason::OtherThread});
    channel.Observe({DiscoveryReason::OtherThread});
    channel.Observe({DiscoveryReason::NoDocument});
    channel.Drain(factory);
    require(attempts.size()==1&&attempts[0]->frames.size()==1,"first diagnostic attempt missing or duplicated");
    for(unsigned tick=0;tick<100;++tick)channel.Drain(factory);
    require(attempts.size()==1,"busy diagnostic slot started another worker");
    // A closed connection/lost response is terminal, even with ok==false.
    attempts[0]->work->done.store(true,std::memory_order_release);
    channel.Drain(factory);
    require(attempts.size()==2&&attempts[0]->frames.size()==1,"failed attempt replayed instead of draining the next reason");
    require(json::parse(attempts[1]->frames[0]).at("diagnostic").at("reason")=="tsf-document-missing","queued reason was lost or reordered");
    attempts[1]->work->ok=true;
    attempts[1]->work->done.store(true,std::memory_order_release);
    channel.Drain(factory);
    channel.Observe({DiscoveryReason::OtherThread});
    channel.Observe({DiscoveryReason::NoDocument});
    channel.Drain(factory);
    require(attempts.size()==2,"completed diagnostic reason was replayed");
    for(const auto& attempt:attempts) {
        const auto frame=json::parse(attempt->frames.at(0));
        require(attempt->timeout==1000&&attempt->connect,"diagnostic I/O is not one bounded independent connection");
        require(attempt->cancellations==0,"completed diagnostic was still treated as pending");
        require(frame.size()==3&&frame.at("version")==1&&frame.at("operation")=="diagnostic","diagnostic slot sent an input/session operation");
    }

    unsigned failedFactories=0;
    auto failFactory=[&]()->std::shared_ptr<FakeDiscoveryTransport>{++failedFactories;throw std::runtime_error("injected connection allocation failure");};
    channel.Observe({DiscoveryReason::NoEndpoint,2,false,true});
    channel.Drain(failFactory);
    channel.Observe({DiscoveryReason::NoEndpoint,2,false,true});
    channel.Drain(failFactory);
    require(failedFactories==1,"factory failure replayed its consumed reason");
    auto startFailure=std::make_shared<FakeDiscoveryTransport>();startFailure->failStart=true;
    channel.Observe({DiscoveryReason::NoContext});
    channel.Drain([&](){return startFailure;});
    channel.Observe({DiscoveryReason::NoContext});
    channel.Drain([&](){return startFailure;});
    require(startFailure->frames.size()==1&&startFailure->cancellations==1,"worker-start failure leaked or replayed its attempt");

    channel.Observe({DiscoveryReason::OtherProcess});
    channel.Observe({DiscoveryReason::NotFocused});
    channel.Drain(factory);
    require(attempts.size()==3,"slot did not recover for a different reason after start failure");
    auto pending=attempts.back();
    channel.Stop();
    channel.Observe({DiscoveryReason::NoForeground});
    channel.Drain(factory);
    pending->work->done.store(true,std::memory_order_release);
    channel.Drain(factory);
    channel.Stop();
    require(pending->cancellations==1&&attempts.size()==3,"shutdown drained queued work, replayed, or cancelled twice");

    auto lifetime=std::make_shared<FakeDiscoveryTransport>();
    {
        Channel retiring;
        retiring.Observe({DiscoveryReason::OtherThread});
        retiring.Drain([&](){return lifetime;});
    }
    require(lifetime->cancellations==1,"destruction did not cancel the independent pending worker");
    lifetime->work->done.store(true,std::memory_order_release);
    require(lifetime->frames.size()==1,"late completion replayed the destroyed adapter's diagnostic");
}

int main() {
    discoveryContracts();
    discoveryChannelContracts();
    const auto success = json{{"ok", true}, {"snapshot", {{"sessionId", "test"}, {"revision", 2}}}};
    require(CompletionResult(success.dump(), 0) == success, "success response changed");
    require(CompletionResult(success.dump(), 1) == success, "S_FALSE response changed");

    auto result = CompletionResult(success.dump(), 0x80004005u);
    require(!result["ok"].get<bool>(), "failed HRESULT must remain failure");
    require(result["snapshot"] == success["snapshot"], "normal response fields changed");
    require(result["diagnostic"] == json{{"stage", "tip-completion"}, {"reason", "operation-failed"}, {"hresult", 2147500037u}}, "HRESULT bits lost");
    result = CompletionResult("{\"ok\":false}", 0xffffffffu);
    require(result["diagnostic"]["hresult"].get<uint32_t>() == 0xffffffffu, "unsigned HRESULT truncated");

    for (uint32_t code : {0u, 1u}) {
        result = CompletionResult("{\"ok\":false,\"retryAllowed\":false}", code);
        require(result["diagnostic"] == json{{"stage", "tip-completion"}, {"reason", "completion-rejected"}}, "fabricated HRESULT on protocol rejection");
        require(result["retryAllowed"] == false, "retry policy changed");
    }
    for (const std::string raw : {"SECRET body candidates code", "null", "[]", "42", "{}", "{\"ok\":\"SECRET\"}"}) {
        result = CompletionResult(raw, 0);
        require(result == json{{"ok", false}, {"error", "TIP operation failed or completion unknown"}, {"retryAllowed", false},
            {"diagnostic", {{"stage", "tip-completion"}, {"reason", "invalid-response"}}}}, "malformed response leaked or accepted");
    }
    result = CompletionResult("SECRET", 0x80070005u);
    require(result["diagnostic"]["hresult"].get<uint32_t>() == 0x80070005u, "malformed response lost HRESULT");
    require(result["diagnostic"]["reason"] == "invalid-response", "malformed response stage lost");

    const std::string secret = "SECRET正文组码候选 C:/private/file\n{injected}";
    json hostile = {{"ok", false}, {"error", secret}, {"diagnostic", {{"stage", secret}, {"reason", secret}, {"hresult", secret}}}};
    result = CompletionResult(hostile.dump(), 0x80004004u);
    require(result["diagnostic"] == json{{"stage", "tip-completion"}, {"reason", "operation-failed"}, {"hresult", 0x80004004u}}, "untrusted diagnostic retained");
    require(result["diagnostic"].dump().find("SECRET") == std::string::npos, "private diagnostic text escaped");
    hostile["ok"] = true;
    result = CompletionResult(hostile.dump(), 0);
    require(!result.contains("diagnostic"), "success retained a stale diagnostic");
    std::cout << "installed completion diagnostics: success, rejection, malformed response, HRESULT and privacy passed\n";
}
