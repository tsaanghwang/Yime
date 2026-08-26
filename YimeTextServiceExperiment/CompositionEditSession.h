#pragma once

#include <msctf.h>

#include "BrokerClient.h"

namespace yime::experiment {

HRESULT ApplyBrokerUpdateToContext(ITfContext* context, TfClientId clientId,
                                   ITfCompositionSink* sink, ITfComposition** composition,
                                   bool* plannedTermination, const BrokerUpdate& update,
                                   RECT* compositionRect = nullptr,
                                   bool* compositionRectValid = nullptr,
                                   bool asynchronous = false) noexcept;

}  // namespace yime::experiment
