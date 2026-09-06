cmake_minimum_required(VERSION 3.5...4.0)

project(PIMETextService)

# http://www.utf8everywhere.org/
add_definitions(/D_UNICODE=1 /DUNICODE=1)
set(CMAKE_CXX_STANDARD 14)

# generate the resource file containing version info
configure_file("PIMETextService.rc.in" "PIMETextService.rc" @ONLY)

include_directories(
    ${CMAKE_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/json/single_include
    ${CMAKE_CURRENT_SOURCE_DIR}
)

add_library(PIMETextService SHARED
    # core IME implementation
    PIMEImeModule.cpp
    PIMEImeModule.h
    PIMETextService.cpp
    PIMETextService.def
    PIMETextService.h
    PIMEClient.cpp
    PIMEClient.h
    PIMECandidateForgetRpc.h
    PIMECompositionSegmentRpc.h
    PIMEKeyRouting.h
    PIMELangBarButton.cpp
    PIMELangBarButton.h
	PIMEProcessValidation.h
    PIMERpcResponse.h
    DllEntry.cpp
    # resources
    ${CMAKE_CURRENT_BINARY_DIR}/PIMETextService.rc
)

target_link_libraries(PIMETextService
    libIME2_static
)

# Regression tests: RPC responses / menu JSON must never throw into the host.
add_executable(PIMERpcResponseTests
    tests/PIMERpcResponseTests.cpp
	PIMEKeyRouting.h
	PIMECandidateForgetRpc.h
	PIMECompositionSegmentRpc.h
	PIMEProcessValidation.h
    PIMERpcResponse.h
)
target_compile_options(PIMERpcResponseTests PRIVATE /utf-8)
add_test(NAME PIMERpcResponseTests COMMAND PIMERpcResponseTests)

# Read-only TSF registration convergence probe. The installer uses the
# architecture-matched copies for pre-mutation admission and for post-register
# or post-removal convergence; the probe never mutates a profile itself.
add_executable(PIMERegistrationStatus RegistrationStatus.cpp)
target_compile_definitions(PIMERegistrationStatus PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(PIMERegistrationStatus PRIVATE /utf-8 /W4 /EHsc)
target_link_libraries(PIMERegistrationStatus ole32 oleaut32)
if(MSVC)
    # The installed read-only probe must run before any VC redistributable can
    # be assumed present on a clean machine. Keep this target self-contained
    # even when PIMETextService is configured independently of the root flags.
    set_property(TARGET PIMERegistrationStatus PROPERTY
        MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"
    )
endif()
