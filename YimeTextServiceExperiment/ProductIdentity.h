#pragma once
#ifdef YIME_LOCAL_PRODUCT
#include "LocalProductIdentity.h"
#else
// Historical trial builds keep their existing label and stable identifiers.
#define YIME_PRODUCT_NAME L"Yime 自研栈试验版"
#endif
