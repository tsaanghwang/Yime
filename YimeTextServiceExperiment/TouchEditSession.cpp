#include "TouchEditSession.h"
#include <wrl/client.h>
#include <algorithm>
#include <atomic>
#include <cwctype>
#include <stdexcept>
#include <vector>
using Microsoft::WRL::ComPtr;
using namespace yime::experiment;
namespace {
size_t previous(const std::wstring&s,size_t p){if(!p)return 0;--p;if(p&&s[p]>=0xdc00&&s[p]<=0xdfff&&s[p-1]>=0xd800&&s[p-1]<=0xdbff)--p;return p;}
size_t next(const std::wstring&s,size_t p){if(p>=s.size())return s.size();if(s[p]>=0xd800&&s[p]<=0xdbff&&p+1<s.size()&&s[p+1]>=0xdc00&&s[p+1]<=0xdfff)return p+2;return p+1;}
size_t lineStart(const std::wstring&s,size_t p){while(p&&s[p-1]!=L'\n'&&s[p-1]!=L'\r')--p;return p;}
size_t lineEnd(const std::wstring&s,size_t p){while(p<s.size()&&s[p]!=L'\n'&&s[p]!=L'\r')++p;return p;}
void require(HRESULT hr){if(FAILED(hr))throw hr;}
std::wstring readRange(ITfRange* range,TfEditCookie cookie){
    ComPtr<ITfRange> copy;require(range->Clone(&copy));std::wstring result;wchar_t chunk[4096];
    for(;;){ULONG n=0;require(copy->GetText(cookie,TF_TF_MOVESTART,chunk,4096,&n));if(!n)return result;if(result.size()+n>1024*1024)throw HRESULT_FROM_WIN32(ERROR_BUFFER_OVERFLOW);result.append(chunk,n);}
}
void putClipboard(const std::wstring& value){
    if(!OpenClipboard(GetForegroundWindow()))throw HRESULT_FROM_WIN32(GetLastError());
    struct Close{~Close(){CloseClipboard();}} close;
    HGLOBAL memory=GlobalAlloc(GMEM_MOVEABLE,(value.size()+1)*sizeof(wchar_t));if(!memory)throw E_OUTOFMEMORY;
    void* data=GlobalLock(memory);if(!data){GlobalFree(memory);throw E_OUTOFMEMORY;}memcpy(data,value.c_str(),(value.size()+1)*sizeof(wchar_t));GlobalUnlock(memory);
    if(!EmptyClipboard()||!SetClipboardData(CF_UNICODETEXT,memory)){GlobalFree(memory);throw HRESULT_FROM_WIN32(GetLastError());}
}
std::wstring getClipboard(){
    if(!OpenClipboard(nullptr))throw HRESULT_FROM_WIN32(GetLastError());struct Close{~Close(){CloseClipboard();}} close;
    HANDLE memory=GetClipboardData(CF_UNICODETEXT);if(!memory)throw E_FAIL;const auto size=GlobalSize(memory)/sizeof(wchar_t);if(!size||size>1024*1024)throw E_INVALIDARG;
    const auto* data=static_cast<const wchar_t*>(GlobalLock(memory));if(!data)throw E_FAIL;
    const size_t n=wcsnlen(data,size);std::wstring value;if(n<size)value.assign(data,n);GlobalUnlock(memory);if(n==size)throw E_INVALIDARG;return value;
}
}
TouchSelectionPlan PlanTouchSelection(const std::wstring& s,size_t start,size_t end,bool activeStart,const TouchHostEdit& e){
    if(start>end||end>s.size())throw E_INVALIDARG;
    TouchSelectionPlan p{start,end,activeStart,false,{}};size_t cursor=activeStart?start:end,anchor=activeStart?end:start,target=cursor;
    if(e.key=="SelectAll"){p.start=0;p.end=s.size();p.activeStart=false;return p;}
    if(e.key=="Backspace"||e.key=="Delete"){
        if(start==end){
            if(e.ctrl){const auto move=PlanTouchSelection(s,start,end,false,TouchHostEdit{e.key=="Backspace"?"ArrowLeft":"ArrowRight",false,true});if(e.key=="Backspace")p.start=move.start;else p.end=move.end;}
            else if(e.key=="Backspace")p.start=previous(s,start);else p.end=next(s,end);
        }p.replace=true;return p;
    }
    if(e.key=="Enter"||e.key=="Tab"){p.replace=true;p.text=e.key=="Enter"?L"\r":L"\t";return p;}
    if(e.key=="ArrowLeft"||e.key=="ArrowRight"){
        const bool left=e.key=="ArrowLeft";
        if(!e.shift&&start!=end&&!e.ctrl)target=left?start:end;
        else if(e.ctrl){
            target=cursor;
            if(left){while(target&&iswspace(s[previous(s,target)]))target=previous(s,target);while(target&&!iswspace(s[previous(s,target)]))target=previous(s,target);}
            else {while(target<s.size()&&!iswspace(s[target]))target=next(s,target);while(target<s.size()&&iswspace(s[target]))target=next(s,target);}
        } else target=left?previous(s,cursor):next(s,cursor);
    } else if(e.key=="Home")target=e.ctrl?0:lineStart(s,cursor);
    else if(e.key=="End")target=e.ctrl?s.size():lineEnd(s,cursor);
    else if(e.key=="ArrowUp"||e.key=="ArrowDown"||e.key=="PageUp"||e.key=="PageDown"){
        const bool up=e.key=="ArrowUp"||e.key=="PageUp";const unsigned count=(e.key=="PageUp"||e.key=="PageDown")?10:1;
        const size_t column=cursor-lineStart(s,cursor);target=cursor;
        for(unsigned i=0;i<count;++i){const size_t a=lineStart(s,target),b=lineEnd(s,target);if(up){if(!a){target=0;break;}size_t prior=a-1;if(prior&&s[prior]==L'\n'&&s[prior-1]==L'\r')--prior;target=std::min(lineStart(s,prior)+column,prior);}else {if(b==s.size()){target=b;break;}size_t following=b+1;if(s[b]==L'\r'&&following<s.size()&&s[following]==L'\n')++following;target=std::min(following+column,lineEnd(s,following));}}
    }else throw E_INVALIDARG;
    if(target&&target<s.size()&&s[target]>=0xdc00&&s[target]<=0xdfff&&s[target-1]>=0xd800&&s[target-1]<=0xdbff)--target;
    if(e.shift){p.start=std::min(anchor,target);p.end=std::max(anchor,target);p.activeStart=target<anchor;}
    else {p.start=p.end=target;p.activeStart=false;}
    return p;
}

namespace {
class TouchEditSession final:public ITfEditSession {
public:
    TouchEditSession(ITfContext*c,ITfCompositionSink*owner,TouchHostEdit edit,BrokerEditCompletionHandler done,void* state,IBrokerEditExecutionGuard*guard):context_(c),owner_(owner),edit_(std::move(edit)),done_(done),state_(state),guard_(guard){}
    STDMETHODIMP QueryInterface(REFIID iid,void**out)override{if(!out)return E_POINTER;*out=nullptr;if(iid!=IID_IUnknown&&iid!=__uuidof(ITfEditSession))return E_NOINTERFACE;*out=static_cast<ITfEditSession*>(this);AddRef();return S_OK;}
    STDMETHODIMP_(ULONG) AddRef()override{return ++refs_;}
    STDMETHODIMP_(ULONG) Release()override{auto n=--refs_;if(!n)delete this;return n;}
    STDMETHODIMP DoEditSession(TfEditCookie cookie)override{
        HRESULT result=E_FAIL;
        try{
            require(guard_->ValidateExecution(context_.Get()));
            TF_SELECTION selection{};ULONG count=0;require(context_->GetSelection(cookie,TF_DEFAULT_SELECTION,1,&selection,&count));if(count!=1||!selection.range)throw E_FAIL;
            ComPtr<ITfRange> selected;selected.Attach(selection.range);
            ComPtr<ITfRange> all,end;require(context_->GetStart(cookie,&all));require(context_->GetEnd(cookie,&end));require(all->ShiftEndToRange(cookie,end.Get(),TF_ANCHOR_END));
            const auto text=readRange(all.Get(),cookie);
            ComPtr<ITfRange> prefix;require(all->Clone(&prefix));require(prefix->ShiftEndToRange(cookie,selected.Get(),TF_ANCHOR_START));const size_t start=readRange(prefix.Get(),cookie).size();
            require(prefix->ShiftEndToRange(cookie,selected.Get(),TF_ANCHOR_END));const size_t finish=readRange(prefix.Get(),cookie).size();
            TouchSelectionPlan plan;
            if(edit_.key=="Copy"||edit_.key=="Cut"){
                if(start==finish){result=S_OK;}else {putClipboard(text.substr(start,finish-start));if(edit_.key=="Copy")result=S_OK;else plan={start,finish,false,true,{}};}
            }else if(edit_.key=="Paste")plan={start,finish,false,true,getClipboard()};
            else plan=PlanTouchSelection(text,start,finish,selection.style.ase==TF_AE_START,edit_);
            if(result!=S_OK){
                ComPtr<ITfRange> range;require(context_->GetStart(cookie,&range));LONG moved=0;
                require(range->ShiftEnd(cookie,static_cast<LONG>(plan.end),&moved,nullptr));if(moved!=static_cast<LONG>(plan.end))throw E_FAIL;
                require(range->ShiftStart(cookie,static_cast<LONG>(plan.start),&moved,nullptr));if(moved!=static_cast<LONG>(plan.start))throw E_FAIL;
                ComPtr<ITfRange> caret;
                if(plan.replace){
                    // Prepare every fallible caret operation before changing
                    // text. Forward gravity keeps this empty range after the
                    // replacement without a second SetSelection after SetText.
                    require(range->Clone(&caret));require(caret->Collapse(cookie,TF_ANCHOR_END));
                    require(caret->SetGravity(cookie,TF_GRAVITY_FORWARD,TF_GRAVITY_FORWARD));
                }
                TF_SELECTION nextSelection{};nextSelection.range=plan.replace?caret.Get():range.Get();nextSelection.style.ase=plan.replace?TF_AE_NONE:plan.activeStart?TF_AE_START:TF_AE_END;
                require(context_->SetSelection(cookie,1,&nextSelection));
                if(plan.replace)require(range->SetText(cookie,0,plan.text.data(),static_cast<LONG>(plan.text.size())));
                result=S_OK;
            }
        }catch(HRESULT hr){result=hr;}catch(...){result=E_FAIL;}
        done_(state_,context_.Get(),BrokerUpdate{},result);return result;
    }
private:
    std::atomic<ULONG>refs_{1};ComPtr<ITfContext>context_;ComPtr<ITfCompositionSink>owner_;TouchHostEdit edit_;BrokerEditCompletionHandler done_;void*state_;ComPtr<IBrokerEditExecutionGuard>guard_;
};
}
HRESULT ApplyTouchEditToContext(ITfContext*c,TfClientId client,ITfCompositionSink*owner,const TouchHostEdit&e,BrokerEditCompletionHandler done,void*state,IBrokerEditExecutionGuard*guard)noexcept{
    if(!c||!owner||!done||!guard||client==TF_CLIENTID_NULL)return E_INVALIDARG;
    auto*session=new(std::nothrow)TouchEditSession(c,owner,e,done,state,guard);if(!session)return E_OUTOFMEMORY;
    HRESULT result=E_FAIL;const HRESULT request=c->RequestEditSession(client,session,TF_ES_ASYNC|TF_ES_READWRITE,&result);session->Release();return FAILED(request)?request:result;
}
