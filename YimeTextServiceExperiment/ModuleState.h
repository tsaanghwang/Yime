#pragma once

#include <windows.h>

void YimeModuleAddRef() noexcept;
void YimeModuleRelease() noexcept;
long YimeModuleRefCount() noexcept;
