// Included inside the DedicatedAsyncTests fixture namespace. Synthetic memory
// only; no TSF activation, registered product, document or clipboard operations.
class Context;
class Range final:public StackCom<ITfRange>{
public:
 Context& context;LONG first,last;TfGravity startGravity=TF_GRAVITY_BACKWARD,endGravity=TF_GRAVITY_FORWARD;
 Range(Context& c,LONG a,LONG b):context(c),first(a),last(b){}
 STDMETHODIMP SetText(TfEditCookie,DWORD,const WCHAR*,LONG)override;
 STDMETHODIMP GetText(TfEditCookie,DWORD,WCHAR*,ULONG,ULONG*)override;
 STDMETHODIMP Collapse(TfEditCookie,TfAnchor)override;
 STDMETHODIMP Clone(ITfRange**)override;
 STDMETHODIMP ShiftStart(TfEditCookie,LONG,LONG*,const TF_HALTCOND*)override;
 STDMETHODIMP ShiftEnd(TfEditCookie,LONG,LONG*,const TF_HALTCOND*)override;
 STDMETHODIMP ShiftStartToRange(TfEditCookie,ITfRange*,TfAnchor)override;
 STDMETHODIMP ShiftEndToRange(TfEditCookie,ITfRange*,TfAnchor)override;
 STDMETHODIMP SetGravity(TfEditCookie,TfGravity,TfGravity)override;
 STDMETHODIMP GetGravity(TfGravity*a,TfGravity*b)override{*a=startGravity;*b=endGravity;return S_OK;}
 STDMETHODIMP GetFormattedText(TfEditCookie,IDataObject**)override{return E_NOTIMPL;}
 STDMETHODIMP GetEmbedded(TfEditCookie,REFGUID,REFIID,IUnknown**)override{return E_NOTIMPL;}
 STDMETHODIMP InsertEmbedded(TfEditCookie,DWORD,IDataObject*)override{return E_NOTIMPL;}
 STDMETHODIMP ShiftStartRegion(TfEditCookie,TfShiftDir,BOOL*)override{return E_NOTIMPL;}
 STDMETHODIMP ShiftEndRegion(TfEditCookie,TfShiftDir,BOOL*)override{return E_NOTIMPL;}
 STDMETHODIMP IsEmpty(TfEditCookie,BOOL*v)override{*v=first==last;return S_OK;}
 STDMETHODIMP IsEqualStart(TfEditCookie,ITfRange*,TfAnchor,BOOL*)override{return E_NOTIMPL;}
 STDMETHODIMP IsEqualEnd(TfEditCookie,ITfRange*,TfAnchor,BOOL*)override{return E_NOTIMPL;}
 STDMETHODIMP CompareStart(TfEditCookie,ITfRange*,TfAnchor,LONG*)override{return E_NOTIMPL;}
 STDMETHODIMP CompareEnd(TfEditCookie,ITfRange*,TfAnchor,LONG*)override{return E_NOTIMPL;}
 STDMETHODIMP AdjustForInsert(TfEditCookie,ULONG,BOOL*)override{return E_NOTIMPL;}
 STDMETHODIMP GetContext(ITfContext**)override{return E_NOTIMPL;}
};
class Composition final:public StackCom<ITfComposition>{
 Range*range_;ITfCompositionSink*sink_;bool ended_=false;
public:
 Composition(Range*r,ITfCompositionSink*s):range_(r),sink_(s){sink_->AddRef();}
 ~Composition(){if(!ended_)sink_->Release();}
 STDMETHODIMP GetRange(ITfRange**out)override{return range_->Clone(out);}
 STDMETHODIMP ShiftStart(TfEditCookie,ITfRange*)override{return E_NOTIMPL;}
 STDMETHODIMP ShiftEnd(TfEditCookie,ITfRange*)override{return E_NOTIMPL;}
 STDMETHODIMP EndComposition(TfEditCookie cookie)override{if(ended_)return E_UNEXPECTED;const auto hr=sink_->OnCompositionTerminated(cookie,this);ended_=true;sink_->Release();return hr;}
};
class Context final:public StackCom<ITfContext>,public ITfInsertAtSelection,public ITfContextComposition{
public:
 ComPtr<ITfEditSession> pending;std::wstring text;
 unsigned writes=0,requests=0,cancelRequests=0,selections=0;
 HRESULT writeResult=S_OK,requestResult=S_OK,cancelRequestResult=S_OK,cancelWriteResult=S_OK,selectionResult=S_OK,collapseResult=S_OK,gravityResult=S_OK;
 DWORD owner=GetCurrentThreadId();bool pendingCancel=false,currentCancel=false;Range*selection=nullptr;TfActiveSelEnd active=TF_AE_NONE;
 std::vector<std::unique_ptr<Range>> ranges;std::vector<std::unique_ptr<Composition>> compositions;
 Range*makeRange(LONG a,LONG b){ranges.push_back(std::make_unique<Range>(*this,a,b));return ranges.back().get();}
 STDMETHODIMP QueryInterface(REFIID iid,void**out)override{
  if(!out)return E_POINTER;
  if(iid==__uuidof(ITfInsertAtSelection)){*out=static_cast<ITfInsertAtSelection*>(this);AddRef();return S_OK;}
  if(iid==__uuidof(ITfContextComposition)){*out=static_cast<ITfContextComposition*>(this);AddRef();return S_OK;}
  return StackCom::QueryInterface(iid,out);
 }
 STDMETHODIMP_(ULONG) AddRef()override{return StackCom::AddRef();}STDMETHODIMP_(ULONG) Release()override{return StackCom::Release();}
 STDMETHODIMP RequestEditSession(TfClientId,ITfEditSession*s,DWORD flags,HRESULT*result)override{
  check(GetCurrentThreadId()==owner,"TSF request left STA");
  check((flags==(TF_ES_ASYNC|TF_ES_READWRITE)||flags==(TF_ES_ASYNCDONTCARE|TF_ES_READWRITE))&&!pending,"unexpected edit scheduling");
  ++requests;const bool cancel=flags==(TF_ES_ASYNCDONTCARE|TF_ES_READWRITE);if(cancel)++cancelRequests;
  const auto hr=cancel?cancelRequestResult:requestResult;if(FAILED(hr))return hr;
  pending=s;pendingCancel=cancel;*result=TF_S_ASYNC;return S_OK;
 }
 HRESULT drain(){check(pending!=nullptr,"no pending TSF edit");auto s=pending;pending.Reset();currentCancel=pendingCancel;const auto hr=s->DoEditSession(73);currentCancel=false;return hr;}
 STDMETHODIMP InsertTextAtSelection(TfEditCookie cookie,DWORD flags,const WCHAR*value,LONG count,ITfRange**out)override{
  check(cookie==73&&GetCurrentThreadId()==owner,"invalid STA insert");
  Range*r=selection?makeRange(selection->first,selection->last):makeRange(static_cast<LONG>(text.size()),static_cast<LONG>(text.size()));
  *out=r;if(flags==TF_IAS_QUERYONLY)return S_OK;check(flags==0,"insert flags");return r->SetText(cookie,0,value,count);
 }
 STDMETHODIMP InsertEmbeddedAtSelection(TfEditCookie,DWORD,IDataObject*,ITfRange**)override{return E_NOTIMPL;}
 STDMETHODIMP StartComposition(TfEditCookie,ITfRange*r,ITfCompositionSink*s,ITfComposition**out)override{
  auto*range=static_cast<Range*>(r);auto*owned=makeRange(range->first,range->last);compositions.push_back(std::make_unique<Composition>(owned,s));*out=compositions.back().get();(*out)->AddRef();return S_OK;
 }
 STDMETHODIMP EnumCompositions(IEnumITfCompositionView**)override{return E_NOTIMPL;}
 STDMETHODIMP FindComposition(TfEditCookie,ITfRange*,IEnumITfCompositionView**)override{return E_NOTIMPL;}
 STDMETHODIMP TakeOwnership(TfEditCookie,ITfCompositionView*,ITfCompositionSink*,ITfComposition**)override{return E_NOTIMPL;}
 STDMETHODIMP GetSelection(TfEditCookie,ULONG,ULONG,TF_SELECTION*out,ULONG*count)override{
  if(!selection)selection=makeRange(static_cast<LONG>(text.size()),static_cast<LONG>(text.size()));selection->Clone(&out->range);out->style.ase=active;out->style.fInterimChar=FALSE;*count=1;return S_OK;
 }
 STDMETHODIMP SetSelection(TfEditCookie cookie,ULONG,const TF_SELECTION*s)override{
  if(cookie!=73)return TF_E_NOLOCK;++selections;if(FAILED(selectionResult))return selectionResult;
  auto*r=static_cast<Range*>(s->range);selection=makeRange(r->first,r->last);selection->startGravity=r->startGravity;selection->endGravity=r->endGravity;active=s->style.ase;return S_OK;
 }
 STDMETHODIMP GetStart(TfEditCookie,ITfRange**out)override{*out=makeRange(0,0);return S_OK;}
 STDMETHODIMP GetEnd(TfEditCookie,ITfRange**out)override{*out=makeRange(static_cast<LONG>(text.size()),static_cast<LONG>(text.size()));return S_OK;}
 STDMETHODIMP InWriteSession(TfClientId,BOOL*)override{return E_NOTIMPL;}
 STDMETHODIMP GetActiveView(ITfContextView**)override{return E_NOTIMPL;}
 STDMETHODIMP EnumViews(IEnumTfContextViews**)override{return E_NOTIMPL;}
 STDMETHODIMP GetStatus(TF_STATUS*)override{return E_NOTIMPL;}
 STDMETHODIMP GetProperty(REFGUID,ITfProperty**)override{return E_NOTIMPL;}
 STDMETHODIMP GetAppProperty(REFGUID,ITfReadOnlyProperty**)override{return E_NOTIMPL;}
 STDMETHODIMP TrackProperties(const GUID**,ULONG,const GUID**,ULONG,ITfReadOnlyProperty**)override{return E_NOTIMPL;}
 STDMETHODIMP EnumProperties(IEnumTfProperties**)override{return E_NOTIMPL;}
 STDMETHODIMP GetDocumentMgr(ITfDocumentMgr**)override{return E_NOTIMPL;}
 STDMETHODIMP CreateRangeBackup(TfEditCookie,ITfRange*,ITfRangeBackup**)override{return E_NOTIMPL;}
};
STDMETHODIMP Range::SetText(TfEditCookie cookie,DWORD,const WCHAR*value,LONG count){
 if(cookie!=73)return TF_E_NOLOCK;const auto hr=context.currentCancel?context.cancelWriteResult:context.writeResult;if(FAILED(hr))return hr;
 if(count<0||(!value&&count))return E_INVALIDARG;const LONG a=first,b=last,delta=count-(b-a);context.text.replace(a,b-a,value?value:L"",count);++context.writes;
 const auto adjust=[&](LONG v,TfGravity g){if(v<a)return v;if(v>b)return v+delta;if(v==b&&b>a)return a+count;return g==TF_GRAVITY_FORWARD?a+count:a;};
 for(auto&r:context.ranges){r->first=adjust(r->first,r->startGravity);r->last=adjust(r->last,r->endGravity);}
 first=a;last=a+count;return S_OK;
}
STDMETHODIMP Range::GetText(TfEditCookie cookie,DWORD flags,WCHAR*out,ULONG size,ULONG*count){if(cookie!=73)return TF_E_NOLOCK;*count=std::min(size,static_cast<ULONG>(last-first));std::copy_n(context.text.data()+first,*count,out);if(flags&TF_TF_MOVESTART)first+=*count;return S_OK;}
STDMETHODIMP Range::Clone(ITfRange**out){auto*r=context.makeRange(first,last);r->startGravity=startGravity;r->endGravity=endGravity;*out=r;return S_OK;}
STDMETHODIMP Range::Collapse(TfEditCookie,TfAnchor anchor){if(FAILED(context.collapseResult))return context.collapseResult;if(anchor==TF_ANCHOR_END)first=last;else last=first;return S_OK;}
STDMETHODIMP Range::ShiftStart(TfEditCookie,LONG n,LONG*m,const TF_HALTCOND*){const LONG old=first;first=std::clamp(first+n,0L,last);*m=first-old;return S_OK;}
STDMETHODIMP Range::ShiftEnd(TfEditCookie,LONG n,LONG*m,const TF_HALTCOND*){const LONG old=last;last=std::clamp(last+n,first,static_cast<LONG>(context.text.size()));*m=last-old;return S_OK;}
STDMETHODIMP Range::ShiftStartToRange(TfEditCookie,ITfRange*other,TfAnchor anchor){auto*r=static_cast<Range*>(other);first=anchor==TF_ANCHOR_START?r->first:r->last;last=std::max(first,last);return S_OK;}
STDMETHODIMP Range::ShiftEndToRange(TfEditCookie,ITfRange*other,TfAnchor anchor){auto*r=static_cast<Range*>(other);last=anchor==TF_ANCHOR_START?r->first:r->last;first=std::min(first,last);return S_OK;}
STDMETHODIMP Range::SetGravity(TfEditCookie,TfGravity a,TfGravity b){if(FAILED(context.gravityResult))return context.gravityResult;startGravity=a;endGravity=b;return S_OK;}
