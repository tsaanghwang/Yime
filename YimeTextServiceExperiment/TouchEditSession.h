#pragma once
#include "CompositionEditSession.h"
#include <string>

struct TouchHostEdit { std::string key; bool shift=false,ctrl=false; };
struct TouchSelectionPlan { size_t start=0,end=0; bool activeStart=false,replace=false; std::wstring text; };
TouchSelectionPlan PlanTouchSelection(const std::wstring& text,size_t start,size_t end,bool activeStart,const TouchHostEdit& edit);
HRESULT ApplyTouchEditToContext(ITfContext*,TfClientId,ITfCompositionSink*,const TouchHostEdit&,
    yime::experiment::BrokerEditCompletionHandler,void*,yime::experiment::IBrokerEditExecutionGuard*) noexcept;
