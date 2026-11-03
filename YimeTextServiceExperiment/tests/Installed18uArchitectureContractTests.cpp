#include <string_view>
#define IMAGE_FILE_MACHINE_ARM64 0xaa64
#define IMAGE_FILE_MACHINE_AMD64 0x8664
#include "../Installed18uArchitecture.h"
#ifdef _M_ARM64
static_assert(kInstalled18uMachine == 0xaa64);
static_assert(std::string_view(kInstalled18uTarget)=="windows-arm64");
static_assert(std::string_view(kInstalled18uDescriptorArchitecture)=="native-arm64");
static_assert(std::string_view(kInstalled18uDllMember)=="arm64/YimeTextService18u.dll");
#else
static_assert(kInstalled18uMachine == 0x8664);
static_assert(std::string_view(kInstalled18uTarget)=="windows-amd64");
static_assert(std::string_view(kInstalled18uDescriptorArchitecture)=="native-x64");
static_assert(std::string_view(kInstalled18uDllMember)=="x64/YimeTextService18u.dll");
#endif
int main() {}
