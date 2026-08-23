#pragma once

#include <msctf.h>

#include "BrokerClient.h"

namespace yime::experiment {

HRESULT ApplyBrokerUpdateToContext(ITfContext* context, TfClientId clientId,
                                   ITfCompositionSink* sink, ITfComposition** composition,
                                   bool* plannedTermination, const BrokerUpdate& update) noexcept;

}  // namespace yime::experiment
