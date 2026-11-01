// S3b opt-in isolated-Windows developer demo, NOT a user-PC deployment.
// Only a parent-created pipe and an own visible read-only text window/context.
// No registration, external HWND or SendInput. ActivateEx flags do NOT guarantee
// permanent TIP suppression: focus/message pumping can activate installed TIPs.
// This risk remains a separate gate before any user-machine delivery.
// Synchronous edits here; prior S2b/S3a fixtures remain unchanged.
#include <windows.h>
#include <msctf.h>
#include <wrl/client.h>
#include <nlohmann/json.hpp>
#include <atomic>
#include <cstdint>
#include <iostream>
#include <set>
#include <stdexcept>
#include <string>
#include "CompositionEditSession.h"
using Microsoft::WRL::ComPtr;
using nlohmann::json;
using namespace yime::experiment;
namespace {
std::string utf8(const std::wstring& value){
    if(value.empty())return {};
    const int n=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),nullptr,0,nullptr,nullptr);
    if(n<=0)throw std::runtime_error("invalid readback UTF-16");
    std::string out(static_cast<size_t>(n),'\0');
    if(WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),out.data(),n,nullptr,nullptr)!=n)
        throw std::runtime_error("readback conversion failed");
    return out;
}
void require(HRESULT hr,const char* what){if(FAILED(hr))throw std::runtime_error(what);}
std::wstring widen(const std::string& value){
    const int n=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),nullptr,0);
    if(n<=0)throw std::runtime_error("invalid UTF-8");
    std::wstring result(static_cast<size_t>(n),L'\0');
    if(MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),result.data(),n)!=n)
        throw std::runtime_error("UTF-8 conversion failed");
    return result;
}
class Sink final : public ITfCompositionSink {
    std::atomic<ULONG> refs_{1};
public:
    STDMETHODIMP QueryInterface(REFIID iid, void** out) override {
        if (!out) return E_POINTER; *out = nullptr;
        if (iid != IID_IUnknown && iid != __uuidof(ITfCompositionSink)) return E_NOINTERFACE;
        *out = static_cast<ITfCompositionSink*>(this); AddRef(); return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++refs_; }
    STDMETHODIMP_(ULONG) Release() override { const ULONG n=--refs_; if (!n) delete this; return n; }
    STDMETHODIMP OnCompositionTerminated(TfEditCookie, ITfComposition*) override { return S_OK; }
};
class Reader final : public ITfEditSession {
    std::atomic<ULONG> refs_{1};
    ComPtr<ITfContext> context_;
public:
    std::wstring text;
    bool completed=false;
    explicit Reader(ITfContext* context):context_(context){}
    STDMETHODIMP QueryInterface(REFIID iid, void** out) override {
        if (!out) return E_POINTER; *out=nullptr;
        if (iid!=IID_IUnknown && iid!=__uuidof(ITfEditSession)) return E_NOINTERFACE;
        *out=static_cast<ITfEditSession*>(this);AddRef();return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override{return ++refs_;}
    STDMETHODIMP_(ULONG) Release() override{const ULONG n=--refs_;if(!n)delete this;return n;}
    STDMETHODIMP DoEditSession(TfEditCookie cookie) override {
        completed=true;
        ComPtr<ITfRange> begin,end;
        HRESULT hr=context_->GetStart(cookie,&begin);
        if(SUCCEEDED(hr))hr=context_->GetEnd(cookie,&end);
        if(SUCCEEDED(hr))hr=begin->ShiftEndToRange(cookie,end.Get(),TF_ANCHOR_END);
        wchar_t buffer[1025]{};ULONG n=0;
        if(SUCCEEDED(hr))hr=begin->GetText(cookie,0,buffer,1025,&n);
        if(SUCCEEDED(hr) && n>1024)return E_BOUNDS;
        if(SUCCEEDED(hr))text.assign(buffer,n);
        return hr;
    }
};
std::wstring read(ITfContext* context,TfClientId client){
    ComPtr<Reader> reader;reader.Attach(new Reader(context));HRESULT edit=E_FAIL;
    require(context->RequestEditSession(client,reader.Get(),TF_ES_SYNC|TF_ES_READ,&edit),"request read");
    require(edit,"read edit");if(!reader->completed)throw std::runtime_error("read not completed");
    return reader->text;
}

struct Apartment {
    Apartment(){require(CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED),"initialize COM");}
    ~Apartment(){CoUninitialize();}
};
struct Host final : IBrokerEditExecutionGuard {
    std::atomic<ULONG> refs{1};
    ComPtr<ITfThreadMgr> manager;
    ComPtr<ITfDocumentMgr> document,other;
    ComPtr<ITfContext> context,otherContext;
    ComPtr<Sink> sink;
    TfClientId client=TF_CLIENTID_NULL;
    bool active=false,bound=false,completed=false,windowClosed=false;
    HWND window=nullptr;
    std::wstring visible;
    uint64_t epoch=1,requestEpoch=0;
    HRESULT completionResult=E_FAIL;
    unsigned checks=0,callbacks=0,edits=0;
    std::wstring expected;
    std::set<std::string> ids;
    void initialize(){
        require(CoCreateInstance(CLSID_TF_ThreadMgr,nullptr,CLSCTX_INPROC_SERVER,
            __uuidof(ITfThreadMgr),reinterpret_cast<void**>(manager.GetAddressOf())),"create thread manager");
        ComPtr<ITfThreadMgrEx> extended;require(manager.As(&extended),"extended manager");
        require(extended->ActivateEx(&client,TF_TMAE_NOACTIVATETIP|TF_TMAE_NOACTIVATEKEYBOARDLAYOUT),"activate own manager");active=true;
        create(document,context);create(other,otherContext);
        require(manager->SetFocus(other.Get()),"initial inactive focus");sink.Attach(new Sink);
        WNDCLASSW cls{};cls.lpfnWndProc=windowProc;cls.hInstance=GetModuleHandleW(nullptr);
        cls.lpszClassName=L"YimeOwnTSFDemoReadback";cls.hCursor=LoadCursorW(nullptr,IDC_ARROW);
        cls.hbrBackground=reinterpret_cast<HBRUSH>(COLOR_WINDOW+1);
        if(!RegisterClassW(&cls))throw std::runtime_error("register own window class");
        window=CreateWindowExW(0,cls.lpszClassName,L"Yime isolated TSF demo — actual readback (read-only)",
            WS_OVERLAPPEDWINDOW,CW_USEDEFAULT,CW_USEDEFAULT,700,320,nullptr,nullptr,cls.hInstance,this);
        if(!window)throw std::runtime_error("create own window");
        ShowWindow(window,SW_SHOWNOACTIVATE);UpdateWindow(window);
    }
    void create(ComPtr<ITfDocumentMgr>& doc,ComPtr<ITfContext>& ctx){
        TfEditCookie cookie=0;require(manager->CreateDocumentMgr(&doc),"create own document");
        require(doc->CreateContext(client,0,nullptr,&ctx,&cookie),"create own context");
        require(doc->Push(ctx.Get()),"push own context");
    }
    ~Host(){if(window && IsWindow(window))DestroyWindow(window);if(active)manager->Deactivate();}
    static LRESULT CALLBACK windowProc(HWND hwnd,UINT message,WPARAM wparam,LPARAM lparam){
        auto* self=reinterpret_cast<Host*>(GetWindowLongPtrW(hwnd,GWLP_USERDATA));
        if(message==WM_NCCREATE){
            self=static_cast<Host*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
            SetWindowLongPtrW(hwnd,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(self));
        }
        if(self){
            if(message==WM_ACTIVATE && LOWORD(wparam)==WA_INACTIVE)self->bound=false;
            if(message==WM_PAINT){
                PAINTSTRUCT paint{};HDC dc=BeginPaint(hwnd,&paint);RECT rect{};GetClientRect(hwnd,&rect);
                rect.left+=16;rect.top+=16;rect.right-=16;rect.bottom-=16;
                SetBkMode(dc,TRANSPARENT);
                DrawTextW(dc,self->visible.data(),static_cast<int>(self->visible.size()),&rect,DT_LEFT|DT_TOP|DT_WORDBREAK|DT_NOPREFIX);
                EndPaint(hwnd,&paint);return 0;
            }
            if(message==WM_CLOSE){self->bound=false;self->windowClosed=true;DestroyWindow(hwnd);return 0;}
            if(message==WM_DESTROY){self->bound=false;self->windowClosed=true;return 0;}
        }
        return DefWindowProcW(hwnd,message,wparam,lparam);
    }
    void observeFocus(){if(!window || GetForegroundWindow()!=window)bound=false;}
    bool hasFocus(){observeFocus();return bound && window && GetForegroundWindow()==window;}
    void rebind(){
        observeFocus();
        if(bound)throw std::runtime_error("invalidate before rebind");
        if(!window || windowClosed || !SetForegroundWindow(window) || GetForegroundWindow()!=window)
            throw std::runtime_error("own window could not acquire foreground");
        require(manager->SetFocus(document.Get()),"restore own TSF focus");
        ++epoch;bound=true;
    }
    STDMETHODIMP QueryInterface(REFIID iid,void** out) override{
        if(!out)return E_POINTER;*out=nullptr;
        if(iid!=IID_IUnknown)return E_NOINTERFACE;
        *out=static_cast<IBrokerEditExecutionGuard*>(this);AddRef();return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override{return ++refs;}
    STDMETHODIMP_(ULONG) Release() override{ULONG n=--refs;if(!n)delete this;return n;}
    HRESULT ValidateExecution(ITfContext* actual) noexcept override{
        ++checks;ComPtr<ITfDocumentMgr> focus;
        if(!hasFocus() || requestEpoch!=epoch || actual!=context.Get() ||
           FAILED(manager->GetFocus(&focus)) || focus.Get()!=document.Get())return E_ABORT;
        return S_OK;
    }
    static void completion(void* opaque,ITfContext* actual,const BrokerUpdate&,HRESULT result) noexcept{
        auto* h=static_cast<Host*>(opaque);++h->callbacks;h->completed=true;
        h->completionResult=actual==h->context.Get()?result:E_UNEXPECTED;
    }
    void verify(){
        const auto actual=read(context.Get(),client);
        if(actual!=expected || !read(otherContext.Get(),client).empty())
            throw std::runtime_error("independent readback mismatch; stop without replay");
        visible=actual; // Never display the expected/input accumulator as host text.
        if(window && IsWindow(window)){InvalidateRect(window,nullptr,TRUE);UpdateWindow(window);}
    }
    bool commit(const std::string& id,const std::string& text){
        if(id.empty() || id.size()>256 || text.empty() || text.size()>1024 || edits>=16 || !ids.insert(id).second)
            throw std::runtime_error("invalid or duplicate commit");
        const auto wide=widen(text);
        if(expected.size()+wide.size()>1024)throw std::runtime_error("own text limit");
        completed=false;
        if(!hasFocus()){verify();return false;} // Confirmed no edit request, not Unknown.
        requestEpoch=epoch;completed=false;completionResult=E_FAIL;checks=callbacks=0;
        BrokerUpdate update;update.commit=text;
        ITfComposition* composition=nullptr;bool ending=false;
        ++edits;
        const HRESULT hr=ApplyBrokerUpdateToContext(context.Get(),client,sink.Get(),&composition,&ending,
            update,nullptr,nullptr,false,completion,this,this);
        if(composition)composition->Release();
        if(hr==E_ABORT && completed && completionResult==E_ABORT && callbacks==1 && checks==1){bound=false;verify();return false;}
        if(hr!=S_OK || !completed || completionResult!=S_OK || callbacks!=1 || checks!=1)
            throw std::runtime_error("commit outcome unknown; stop without replay");
        expected+=wide;verify();return true;
    }
    void close(){
        verify();require(document->Pop(TF_POPF_ALL),"pop own context");
        require(other->Pop(TF_POPF_ALL),"pop other context");
        require(manager->Deactivate(),"deactivate manager");active=false;
        if(window && IsWindow(window))DestroyWindow(window);
    }
};
bool frame(Host* host,std::string& line){
    // No blocking getline on the COM/window STA. Read only bytes already in
    // this pipe; pump only this process's normal window messages while idle.
    static std::string buffered;
    for(;;){
        MSG message{};
        for(unsigned n=0;n<64 && PeekMessageW(&message,nullptr,0,0,PM_REMOVE);++n){
            TranslateMessage(&message);DispatchMessageW(&message);
        }
        if(host){host->observeFocus();if(host->windowClosed)return false;}
        const auto newline=buffered.find('\n');
        if(newline!=std::string::npos){line=buffered.substr(0,newline);buffered.erase(0,newline+1);return true;}
        DWORD available=0;
        if(!PeekNamedPipe(GetStdHandle(STD_INPUT_HANDLE),nullptr,0,nullptr,&available,nullptr)){
            if(GetLastError()==ERROR_BROKEN_PIPE)return false;
            throw std::runtime_error("input pipe query failed");
        }
        if(available){
            char bytes[4096];DWORD count=0;const DWORD wanted=available<sizeof(bytes)?available:static_cast<DWORD>(sizeof(bytes));
            if(!ReadFile(GetStdHandle(STD_INPUT_HANDLE),bytes,wanted,&count,nullptr) || count==0)return false;
            buffered.append(bytes,count);
            const auto boundary=buffered.find('\n');
            if((boundary==std::string::npos && buffered.size()>16384) || (boundary!=std::string::npos && boundary>16384))
                throw std::runtime_error("request frame limit");
        }else MsgWaitForMultipleObjects(0,nullptr,FALSE,10,QS_ALLINPUT);
    }
}

void nativeGate(){
    using Query=BOOL(WINAPI*)(HANDLE,USHORT*,USHORT*);
    auto query=reinterpret_cast<Query>(GetProcAddress(GetModuleHandleW(L"kernel32.dll"),"IsWow64Process2"));
    USHORT process=0,native=0;
    if(!query || !query(GetCurrentProcess(),&process,&native) || process!=IMAGE_FILE_MACHINE_UNKNOWN || native!=IMAGE_FILE_MACHINE_AMD64)
        throw std::runtime_error("native Windows x64 required");
    // PIPE type rejects consoles/files, but does not authenticate the parent or
    // prove anonymity. Trust here comes from the verified demo parent creating both pipes
    // and launching this exact fixture; this is not a public IPC security gate.
    if(GetFileType(GetStdHandle(STD_INPUT_HANDLE))!=FILE_TYPE_PIPE || GetFileType(GetStdHandle(STD_OUTPUT_HANDLE))!=FILE_TYPE_PIPE)
        throw std::runtime_error("pipe handles required");
}
}
bool validIdentity(const json& identity){
    if(!identity.is_object() || identity.size()!=4)return false;
    for(const auto* name:{"layoutSHA256","dictionarySHA256"}){
        if(!identity.contains(name) || !identity.at(name).is_string())return false;
        const auto hash=identity.at(name).get<std::string>();
        if(hash.size()!=64 || hash.find_first_not_of("0123456789abcdef")!=std::string::npos)return false;
    }
    return identity.value("mode",std::string{})=="variable" && identity.contains("sessionPolicy") &&
        identity.at("sessionPolicy").is_string() && !identity.at("sessionPolicy").get<std::string>().empty() &&
        identity.at("sessionPolicy").get<std::string>().size()<=256;
}
int main(){
    try{
        nativeGate();Apartment apartment;ComPtr<Host> host;json identity;unsigned mutations=0;
        for(uint64_t sequence=1;;++sequence){
            if(sequence==UINT64_MAX)throw std::runtime_error("sequence exhausted");
            std::string line;
            if(!frame(host.Get(),line)){if(host)host->close();return 0;}
            const auto request=json::parse(line);
            if(!request.is_object() || !request.contains("version") || !request.at("version").is_number_unsigned() ||
               request.at("version").get<uint64_t>()!=2 ||
               !request.contains("seq") || !request.at("seq").is_number_unsigned() || request.at("seq").get<uint64_t>()!=sequence ||
               !request.contains("epoch") || !request.at("epoch").is_number_unsigned() ||
               !request.contains("op") || !request.at("op").is_string() || !request.contains("identity"))
                throw std::runtime_error("invalid demo envelope");
            const auto op=request.at("op").get<std::string>();
            // Status polling must not consume the bounded interactive action budget.
            if(op!="read" && ++mutations>128)throw std::runtime_error("demo action limit");
            const auto epoch=request.at("epoch").get<uint64_t>();
            if(request.size()!=(op=="commit"?7u:5u))throw std::runtime_error("unexpected demo fields");
            bool callback=false,ok=true;std::string outcome;
            if(!host){
                if(op!="init" || epoch!=0 || sequence!=1 || !validIdentity(request.at("identity")))throw std::runtime_error("invalid demo init");
                identity=request.at("identity"); // Parent verified resources; this is binding, NOT native provenance verification.
                host.Attach(new Host);host->initialize();host->verify();
            }else{
                if(epoch!=host->epoch || request.at("identity")!=identity)throw std::runtime_error("stale epoch or identity");
                if(op=="commit"){
                    ok=host->commit(request.at("id").get<std::string>(),request.at("text").get<std::string>());
                    callback=host->completed;outcome=ok?"applied":"failed";
                }else if(op=="invalidate"){
                    host->bound=false;require(host->manager->SetFocus(host->other.Get()),"invalidate own TSF focus");host->verify();
                }else if(op=="rebind"){host->rebind();host->verify();}
                else if(op=="read")host->verify();
                else if(op=="close")host->close();
                else throw std::runtime_error("unsupported demo operation");
            }
            host->observeFocus();
            std::cout<<json{{"version",2},{"seq",sequence},{"op",op},{"epoch",host->epoch},{"identity",identity},
                {"context","own-demo-host"},{"ok",ok},{"outcome",outcome},{"readbackMatch",true},
                {"totalUTF16Units",host->visible.size()},{"callbackSeen",callback},{"active",host->bound},
                {"readbackText",utf8(host->visible)}}.dump()<<std::endl;
            if(!std::cout)throw std::runtime_error("response pipe failed; no replay");
            if(op=="close")return 0;
        }
    }catch(const json::exception&){std::cerr<<"own TSF demo failed: invalid JSON protocol\n";return 1;}
    catch(const std::exception& e){std::cerr<<"own TSF demo failed: "<<e.what()<<'\n';return 1;}
}
