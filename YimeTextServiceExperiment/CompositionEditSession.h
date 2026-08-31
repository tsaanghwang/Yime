#pragma once

#include <msctf.h>

#include "BrokerClient.h"

namespace yime::experiment {

using BrokerEditCompletionHandler = void (*)(void* context, ITfContext* editContext,
                                              const BrokerUpdate& update,
                                              HRESULT result) noexcept;

HRESULT ApplyBrokerUpdateToContext(ITfContext* context, TfClientId clientId,
                                   ITfCompositionSink* sink, ITfComposition** composition,
                                   bool* plannedTermination, const BrokerUpdate& update,
                                   RECT* compositionRect = nullptr,
                                   bool* compositionRectValid = nullptr,
                                   bool asynchronous = false,
                                   BrokerEditCompletionHandler completionHandler = nullptr,
                                   void* completionContext = nullptr) noexcept;

}  // namespace yime::experiment
