cmake_minimum_required(VERSION 3.20)

# Standalone configuration avoids the repository root's FetchContent and every
# product/registration target. With the option off it needs no C++ compiler.
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    project(YimeTouchFrontendNativeHostPhaseA LANGUAGES NONE)
endif()

option(YIME_TOUCH_FRONTEND_NATIVE_HOST_PHASE_A
    "Build explicit native x64 phase-A host and offline regression tests" OFF)
if(NOT YIME_TOUCH_FRONTEND_NATIVE_HOST_PHASE_A)
    return()
endif()

if(NOT CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows" OR
   NOT CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "^(AMD64|amd64|x86_64)$" OR
   CMAKE_CROSSCOMPILING)
    message(FATAL_ERROR "Phase A requires a native Windows x64 build host")
endif()

enable_language(CXX)
if(NOT WIN32 OR NOT MSVC OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8 OR
   NOT CMAKE_VS_PLATFORM_NAME STREQUAL "x64")
    message(FATAL_ERROR "Phase A requires the native MSVC x64 Visual Studio generator (-A x64)")
endif()

get_filename_component(YIME_NATIVE_HOST_PROJECT_DIR "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
set(YIME_NATIVE_HOST_TEST_DIR "${YIME_NATIVE_HOST_PROJECT_DIR}/tests")
set(YIME_NATIVE_HOST_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")

# Reuse the canonical product JSON and existing identity template. This only
# supplies constants to the host; it does not enable YIME_TOUCH_PRODUCT targets.
file(READ "${YIME_NATIVE_HOST_PROJECT_DIR}/../tools/yimecore/18u-touch-product.json" TOUCH_JSON)
string(JSON TOUCH_NAME GET "${TOUCH_JSON}" display_name)
string(JSON TOUCH_CLSID GET "${TOUCH_JSON}" identity clsid)
string(JSON TOUCH_PROFILE GET "${TOUCH_JSON}" identity profile)
string(JSON TOUCH_LAYOUT GET "${TOUCH_JSON}" data layout_sha256)
string(JSON TOUCH_DICTIONARY GET "${TOUCH_JSON}" data dictionary_sha256)
function(yime_native_host_guid PREFIX VALUE)
    string(REGEX REPLACE "[{}-]" "" VALUE "${VALUE}")
    string(LENGTH "${VALUE}" LENGTH)
    if(NOT LENGTH EQUAL 32 OR NOT VALUE MATCHES "^[0-9A-Fa-f]+$")
        message(FATAL_ERROR "Invalid dedicated identity GUID")
    endif()
    foreach(PAIR IN ITEMS D1:0:8 D2:8:4 D3:12:4 B0:16:2 B1:18:2 B2:20:2 B3:22:2 B4:24:2 B5:26:2 B6:28:2 B7:30:2)
        string(REPLACE ":" ";" PARTS "${PAIR}")
        list(GET PARTS 0 NAME)
        list(GET PARTS 1 OFFSET)
        list(GET PARTS 2 COUNT)
        string(SUBSTRING "${VALUE}" ${OFFSET} ${COUNT} FIELD)
        set(${PREFIX}_${NAME} "${FIELD}" PARENT_SCOPE)
    endforeach()
endfunction()
yime_native_host_guid(TOUCH_CLSID "${TOUCH_CLSID}")
yime_native_host_guid(TOUCH_PROFILE "${TOUCH_PROFILE}")
file(MAKE_DIRECTORY "${YIME_NATIVE_HOST_GENERATED_DIR}")
configure_file("${YIME_NATIVE_HOST_PROJECT_DIR}/TouchProductIdentity.h.in"
    "${YIME_NATIVE_HOST_GENERATED_DIR}/TouchProductIdentity.h" @ONLY)

function(yime_native_host_settings TARGET)
    target_compile_features(${TARGET} PRIVATE cxx_std_17)
    target_compile_definitions(${TARGET} PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_compile_options(${TARGET} PRIVATE /utf-8 /W4 /EHsc)
    target_include_directories(${TARGET} PRIVATE "${YIME_NATIVE_HOST_PROJECT_DIR}"
        "${YIME_NATIVE_HOST_TEST_DIR}" "${YIME_NATIVE_HOST_GENERATED_DIR}"
        "${YIME_NATIVE_HOST_PROJECT_DIR}/../json/single_include")
    set_property(TARGET ${TARGET} PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endfunction()

# All targets must be named explicitly at build time. No installer/package or
# registration helper is linked, generated, copied, or invoked here.
add_executable(YimeTouchFrontendNativeHost EXCLUDE_FROM_ALL
    "${YIME_NATIVE_HOST_TEST_DIR}/TouchFrontendNativeHost.cpp"
    "${YIME_NATIVE_HOST_TEST_DIR}/TouchFrontendNativeHostPaths.h"
    "${YIME_NATIVE_HOST_TEST_DIR}/TouchFrontendNativeHostRegistry.h"
    "${YIME_NATIVE_HOST_TEST_DIR}/TouchFrontendNativeHostSafety.h"
    "${YIME_NATIVE_HOST_TEST_DIR}/TouchFrontendNativeTextStore.h"
    "${YIME_NATIVE_HOST_TEST_DIR}/TouchFrontendNativeHostContract.h")
yime_native_host_settings(YimeTouchFrontendNativeHost)
target_compile_definitions(YimeTouchFrontendNativeHost PRIVATE YIME_TOUCH_PRODUCT=1)
target_link_libraries(YimeTouchFrontendNativeHost PRIVATE bcrypt advapi32 ole32 oleaut32 user32 uuid)

add_executable(YimeTouchFrontendNativeHostOfflineTests EXCLUDE_FROM_ALL
    "${YIME_NATIVE_HOST_TEST_DIR}/TouchFrontendNativeHostTests.cpp"
    "${YIME_NATIVE_HOST_TEST_DIR}/TouchFrontendNativeTextStore.h"
    "${YIME_NATIVE_HOST_TEST_DIR}/TouchFrontendNativeHostContract.h")
yime_native_host_settings(YimeTouchFrontendNativeHostOfflineTests)
target_link_libraries(YimeTouchFrontendNativeHostOfflineTests PRIVATE ole32 oleaut32 user32 uuid)

# Offline safety tests inject registry reads, clocks/sinks and evidence failures.
add_executable(YimeTouchFrontendNativeHostSafetyTests EXCLUDE_FROM_ALL
    "${YIME_NATIVE_HOST_TEST_DIR}/TouchFrontendNativeHostSafetyTests.cpp"
    "${YIME_NATIVE_HOST_TEST_DIR}/TouchFrontendNativeHostRegistry.h"
    "${YIME_NATIVE_HOST_TEST_DIR}/TouchFrontendNativeHostSafety.h")
yime_native_host_settings(YimeTouchFrontendNativeHostSafetyTests)
target_link_libraries(YimeTouchFrontendNativeHostSafetyTests PRIVATE ole32 oleaut32 user32 uuid)

# These tests only open/create directories inside an explicit isolated fixture.
add_executable(YimeTouchFrontendNativeHostPathTests EXCLUDE_FROM_ALL
    "${YIME_NATIVE_HOST_TEST_DIR}/TouchFrontendNativeHostPathTests.cpp"
    "${YIME_NATIVE_HOST_TEST_DIR}/TouchFrontendNativeHostPaths.h")
yime_native_host_settings(YimeTouchFrontendNativeHostPathTests)
set(YIME_NATIVE_HOST_PATH_TEST_ROOT "${CMAKE_CURRENT_BINARY_DIR}/path-fixtures" CACHE PATH
    "Isolated directory for offline path tests (never an installed product directory)")

# Only offline executables are tests. The native host has no
# CTest entry, custom run command, post-build execution, or default activation.
enable_testing()
add_test(NAME YimeTouchFrontendNativeHostOfflineTests
    COMMAND $<TARGET_FILE:YimeTouchFrontendNativeHostOfflineTests>)
add_test(NAME YimeTouchFrontendNativeHostSafetyTests
    COMMAND $<TARGET_FILE:YimeTouchFrontendNativeHostSafetyTests>)
add_test(NAME YimeTouchFrontendNativeHostPathTests
    COMMAND $<TARGET_FILE:YimeTouchFrontendNativeHostPathTests> "${YIME_NATIVE_HOST_PATH_TEST_ROOT}")
