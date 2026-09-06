#pragma once

#include <msctf.h>

#include "BrokerClient.h"

namespace yime::experiment {

HRESULT ValidateCompositionRangeResult(HRESULT result, ITfRange* range) noexcept;

// The caller already owns a write cookie (for example OnCompositionTerminated).
// Only the unconfirmed composition range is cleared; no selection or other text.
HRESULT ClearCompositionText(TfEditCookie cookie, ITfComposition* composition) noexcept;

using BrokerEditCompletionHandler = void (*)(void* context, ITfContext* editContext,
                                              const BrokerUpdate& update,
                                              HRESULT result) noexcept;
using CompositionCancellationCompletionHandler = void (*)(void* context,
    ITfComposition* expectedComposition, HRESULT result) noexcept;

HRESULT ApplyBrokerUpdateToContext(ITfContext* context, TfClientId clientId,
                                   ITfCompositionSink* sink, ITfComposition** composition,
                                   bool* plannedTermination, const BrokerUpdate& update,
                                   RECT* compositionRect = nullptr,
                                   bool* compositionRectValid = nullptr,
                                   bool asynchronous = false,
                                   BrokerEditCompletionHandler completionHandler = nullptr,
                                   void* completionContext = nullptr) noexcept;

HRESULT CancelCompositionInContext(ITfContext* context, TfClientId clientId,
                                    ITfCompositionSink* sink, ITfComposition** composition,
                                    bool* plannedTermination,
                                    CompositionCancellationCompletionHandler completionHandler,
                                    void* completionContext) noexcept;

}  // namespace yime::experiment
