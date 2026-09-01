#include "CompositionEditSession.h"

#include <atomic>
#include <new>
#include <string>

namespace yime::experiment {

HRESULT ValidateCompositionRangeResult(HRESULT result, ITfRange* range) noexcept {
	if (FAILED(result)) return result;
	return range ? result : E_UNEXPECTED;
}

namespace {

std::wstring widen(const std::string& value) {
    if (value.empty()) return {};
    const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                                           static_cast<int>(value.size()), nullptr, 0);
    if (length <= 0) return {};
    std::wstring result(static_cast<size_t>(length), L'\0');
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()),
                            result.data(), length) != length) return {};
    return result;
}

class EditSession final : public ITfEditSession {
public:
    EditSession(ITfContext* context, ITfCompositionSink* sink, ITfComposition** composition,
                bool* plannedTermination, const BrokerUpdate& update, RECT* compositionRect,
                bool* compositionRectValid, BrokerEditCompletionHandler completionHandler,
                void* completionContext)
        : context_(context), sink_(sink), composition_(composition),
          plannedTermination_(plannedTermination), update_(update), compositionRect_(compositionRect),
            compositionRectValid_(compositionRectValid), completionHandler_(completionHandler),
            completionContext_(completionContext) {
        context_->AddRef();
        sink_->AddRef();
    }
    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) return E_POINTER;
        *object = nullptr;
        if (!IsEqualIID(iid, IID_IUnknown) && !IsEqualIID(iid, __uuidof(ITfEditSession))) return E_NOINTERFACE;
        *object = static_cast<ITfEditSession*>(this);
        AddRef();
        return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
    STDMETHODIMP_(ULONG) Release() override {
        const ULONG remaining = --references_;
        if (remaining == 0) delete this;
        return remaining;
    }
    STDMETHODIMP DoEditSession(TfEditCookie cookie) override {
        const std::wstring raw = widen(update_.rawInput);
        const std::wstring commit = widen(update_.commit);
        HRESULT result = E_INVALIDARG;
        if ((!update_.rawInput.empty() && raw.empty()) ||
            (!update_.commit.empty() && commit.empty())) {
            result = E_INVALIDARG;
        } else if (!commit.empty()) {
            result = Commit(cookie, commit);
        } else if (!raw.empty()) {
            result = SetComposition(cookie, raw);
            if (SUCCEEDED(result)) CaptureCompositionRect(cookie);
        } else {
            result = EndComposition(cookie, L"");
        }
        if (completionHandler_) {
            completionHandler_(completionContext_, context_, update_, result);
        }
        return result;
    }

private:
    ~EditSession() {
        sink_->Release();
        context_->Release();
    }

    HRESULT StartComposition(TfEditCookie cookie) {
        ITfInsertAtSelection* insertion = nullptr;
        HRESULT result = context_->QueryInterface(__uuidof(ITfInsertAtSelection), reinterpret_cast<void**>(&insertion));
        if (FAILED(result)) return result;
        ITfRange* range = nullptr;
        result = insertion->InsertTextAtSelection(cookie, TF_IAS_QUERYONLY, nullptr, 0, &range);
        insertion->Release();
		result = ValidateCompositionRangeResult(result, range);
		if (FAILED(result)) {
			if (range) range->Release();
			return result;
		}
        ITfContextComposition* service = nullptr;
        result = context_->QueryInterface(__uuidof(ITfContextComposition), reinterpret_cast<void**>(&service));
        if (SUCCEEDED(result)) result = service->StartComposition(cookie, range, sink_, composition_);
        if (service) service->Release();
		if (SUCCEEDED(result) && !*composition_) result = E_UNEXPECTED;
        if (SUCCEEDED(result)) {
            TF_SELECTION selection{};
            selection.range = range;
            selection.style.ase = TF_AE_NONE;
            result = context_->SetSelection(cookie, 1, &selection);
        }
        range->Release();
        return result;
    }

    HRESULT SetComposition(TfEditCookie cookie, const std::wstring& text) {
        if (!*composition_) {
            const HRESULT start = StartComposition(cookie);
            if (FAILED(start)) return start;
        }
        ITfRange* range = nullptr;
        HRESULT result = (*composition_)->GetRange(&range);
		result = ValidateCompositionRangeResult(result, range);
        if (SUCCEEDED(result)) result = range->SetText(cookie, 0, text.data(), static_cast<LONG>(text.size()));
        if (SUCCEEDED(result)) {
            range->Collapse(cookie, TF_ANCHOR_END);
            TF_SELECTION selection{};
            selection.range = range;
            selection.style.ase = TF_AE_NONE;
            result = context_->SetSelection(cookie, 1, &selection);
        }
        if (range) range->Release();
        return result;
    }

    HRESULT Commit(TfEditCookie cookie, const std::wstring& text) {
        if (!*composition_) {
            ITfInsertAtSelection* insertion = nullptr;
            HRESULT result = context_->QueryInterface(__uuidof(ITfInsertAtSelection), reinterpret_cast<void**>(&insertion));
            if (FAILED(result)) return result;
            // Request the inserted range even though the one-shot commit does
            // not retain it. This is supported by both the TSF document-manager
            // context used by the regression and real Word text stores.
            ITfRange* inserted = nullptr;
            result = insertion->InsertTextAtSelection(cookie, 0, text.data(),
                                                      static_cast<LONG>(text.size()), &inserted);
            if (SUCCEEDED(result) && inserted) {
                result = inserted->Collapse(cookie, TF_ANCHOR_END);
                if (SUCCEEDED(result)) {
                    TF_SELECTION selection{};
                    selection.range = inserted;
                    selection.style.ase = TF_AE_NONE;
                    result = context_->SetSelection(cookie, 1, &selection);
                }
            }
            if (inserted) inserted->Release();
            insertion->Release();
            return result;
        }
        return EndComposition(cookie, text);
    }

    HRESULT EndComposition(TfEditCookie cookie, const std::wstring& replacement) {
        if (!*composition_) return S_OK;
        ITfComposition* active = *composition_;
        ITfRange* range = nullptr;
        HRESULT result = active->GetRange(&range);
		result = ValidateCompositionRangeResult(result, range);
        if (SUCCEEDED(result)) result = range->SetText(cookie, 0, replacement.data(), static_cast<LONG>(replacement.size()));
        if (SUCCEEDED(result)) {
            range->Collapse(cookie, TF_ANCHOR_END);
            TF_SELECTION selection{};
            selection.range = range;
            selection.style.ase = TF_AE_NONE;
            result = context_->SetSelection(cookie, 1, &selection);
        }
        if (range) range->Release();
        active->AddRef();
        if (SUCCEEDED(result)) {
            *plannedTermination_ = true;
            result = active->EndComposition(cookie);
            *plannedTermination_ = false;
        }
        if (SUCCEEDED(result)) {
            if (*composition_ == active) {
                active->Release();
                *composition_ = nullptr;
            }
        }
        active->Release();
        return result;
    }

    void CaptureCompositionRect(TfEditCookie cookie) noexcept {
        if (!compositionRect_ || !compositionRectValid_ || !*composition_) return;
        ITfRange* range = nullptr;
        ITfContextView* view = nullptr;
        BOOL clipped = FALSE;
        if (SUCCEEDED((*composition_)->GetRange(&range)) &&
            SUCCEEDED(context_->GetActiveView(&view)) &&
            SUCCEEDED(view->GetTextExt(cookie, range, compositionRect_, &clipped))) {
            *compositionRectValid_ = true;
        }
        if (view) view->Release();
        if (range) range->Release();
    }

    std::atomic<ULONG> references_{1};
    ITfContext* context_;
    ITfCompositionSink* sink_;
    ITfComposition** composition_;
    bool* plannedTermination_;
    BrokerUpdate update_;
    RECT* compositionRect_;
    bool* compositionRectValid_;
    BrokerEditCompletionHandler completionHandler_;
    void* completionContext_;
};

}  // namespace

HRESULT ApplyBrokerUpdateToContext(ITfContext* context, TfClientId clientId,
                                   ITfCompositionSink* sink, ITfComposition** composition,
                                   bool* plannedTermination, const BrokerUpdate& update,
                                   RECT* compositionRect, bool* compositionRectValid,
                                   bool asynchronous,
                                   BrokerEditCompletionHandler completionHandler,
                                   void* completionContext) noexcept {
    if (!context || clientId == TF_CLIENTID_NULL || !sink || !composition || !plannedTermination) return E_INVALIDARG;
    if (asynchronous && (compositionRect || compositionRectValid)) return E_INVALIDARG;
    if (compositionRectValid) *compositionRectValid = false;
    auto* session = new (std::nothrow) EditSession(context, sink, composition, plannedTermination,
                                                   update, compositionRect, compositionRectValid,
                                                   completionHandler, completionContext);
    if (!session) return E_OUTOFMEMORY;
    HRESULT sessionResult = E_FAIL;
    const DWORD flags = (asynchronous ? TF_ES_ASYNC : TF_ES_SYNC) | TF_ES_READWRITE;
    const HRESULT request = context->RequestEditSession(clientId, session, flags, &sessionResult);
    session->Release();
    return FAILED(request) ? request : sessionResult;
}

}  // namespace yime::experiment
