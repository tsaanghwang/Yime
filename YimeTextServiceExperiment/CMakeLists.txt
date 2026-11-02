cmake_minimum_required(VERSION 3.20)
project(YimeTextServiceExperiment LANGUAGES CXX)

set(YIME_ARM64X_STAGE "" CACHE STRING "Opt-in Release ARM64X stage: ARM64 or ARM64EC")
set_property(CACHE YIME_ARM64X_STAGE PROPERTY STRINGS "" ARM64 ARM64EC)
if(YIME_ARM64X_STAGE)
    if(NOT YIME_ARM64X_STAGE STREQUAL "ARM64" AND NOT YIME_ARM64X_STAGE STREQUAL "ARM64EC")
        message(FATAL_ERROR "YIME_ARM64X_STAGE must be ARM64 or ARM64EC")
    endif()
    if(NOT CMAKE_GENERATOR_PLATFORM STREQUAL YIME_ARM64X_STAGE)
        message(FATAL_ERROR "ARM64X stage must match the generator platform")
    endif()
    # A native input response file belongs to one configuration. Do not silently
    # combine Release native objects with a Debug EC runtime.
    set(CMAKE_CONFIGURATION_TYPES Release CACHE STRING "ARM64X build configuration" FORCE)
endif()

option(YIME_LOCAL_PRODUCT "Build the current-PC independent product display identity" OFF)
if(YIME_LOCAL_PRODUCT)
    if(NOT CMAKE_GENERATOR_PLATFORM STREQUAL "x64" AND
       NOT CMAKE_GENERATOR_PLATFORM STREQUAL "Win32" AND
       NOT CMAKE_GENERATOR_PLATFORM STREQUAL "ARM64" AND
       NOT (CMAKE_GENERATOR_PLATFORM STREQUAL "ARM64EC" AND YIME_ARM64X_STAGE STREQUAL "ARM64EC"))
        message(FATAL_ERROR "Current-identity TSF builds support x64, Win32 and ARM64; installation requires target-specific acceptance")
    endif()
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/../tools/yimecore/local-product.json" YIME_PRODUCT_JSON)
    string(JSON YIME_LOCAL_PRODUCT_NAME GET "${YIME_PRODUCT_JSON}" display_name)
    string(JSON YIME_LOCAL_PRODUCT_CLSID GET "${YIME_PRODUCT_JSON}" identity clsid)
    string(JSON YIME_LOCAL_PRODUCT_PROFILE GET "${YIME_PRODUCT_JSON}" identity profile)
    function(yime_split_guid PREFIX VALUE)
        string(REGEX REPLACE "[{}-]" "" COMPACT "${VALUE}")
        string(LENGTH "${COMPACT}" COMPACT_LENGTH)
        if(NOT COMPACT_LENGTH EQUAL 32 OR NOT COMPACT MATCHES "^[0-9A-Fa-f]+$")
            message(FATAL_ERROR "Invalid local product GUID: ${VALUE}")
        endif()
        foreach(PAIR IN ITEMS D1:0:8 D2:8:4 D3:12:4 B0:16:2 B1:18:2 B2:20:2 B3:22:2 B4:24:2 B5:26:2 B6:28:2 B7:30:2)
            string(REPLACE ":" ";" PARTS "${PAIR}")
            list(GET PARTS 0 NAME)
            list(GET PARTS 1 OFFSET)
            list(GET PARTS 2 LENGTH)
            string(SUBSTRING "${COMPACT}" ${OFFSET} ${LENGTH} FIELD)
            set(${PREFIX}_${NAME} "${FIELD}" PARENT_SCOPE)
        endforeach()
    endfunction()
    yime_split_guid(YIME_LOCAL_CLSID "${YIME_LOCAL_PRODUCT_CLSID}")
    yime_split_guid(YIME_LOCAL_PROFILE "${YIME_LOCAL_PRODUCT_PROFILE}")
    configure_file(LocalProductIdentity.h.in LocalProductIdentity.h @ONLY)
    add_compile_definitions(YIME_LOCAL_PRODUCT=1)
    include_directories("${CMAKE_CURRENT_BINARY_DIR}")
endif()

add_library(YimeTextServiceExperiment SHARED
    BrokerEndpoint.cpp
    BrokerClient.cpp
    CandidateListUIElement.cpp
    CandidatePopup.cpp
    CompositionEditSession.cpp
    DllEntry.cpp
    ExperimentSettings.cpp
    KeyContract.cpp
    LanguageBarItem.cpp
    LanguageBarResources.rc
    OutputTransform.cpp
    PunctuationPalette.cpp
    SurfaceSession.cpp
    TextService.cpp
    YimeTextServiceExperiment.def
)
target_compile_features(YimeTextServiceExperiment PRIVATE cxx_std_17)
target_compile_definitions(YimeTextServiceExperiment PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(YimeTextServiceExperiment PRIVATE /utf-8 /W4 /EHsc)
target_include_directories(YimeTextServiceExperiment PRIVATE "${CMAKE_CURRENT_LIST_DIR}/../json/single_include")
target_link_libraries(YimeTextServiceExperiment PRIVATE advapi32 ole32 oleaut32 user32 gdi32)
set_property(TARGET YimeTextServiceExperiment PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

add_executable(YimeTextServiceContractTests
    tests/ContractTests.cpp
    BrokerClient.cpp
    BrokerEndpoint.cpp
    CandidateListUIElement.cpp
    CandidatePopup.cpp
	CompositionEditSession.cpp
    ExperimentSettings.cpp
    KeyContract.cpp
    LanguageBarItem.cpp
    LanguageBarResources.rc
    OutputTransform.cpp
    PunctuationPalette.cpp
)
target_compile_features(YimeTextServiceContractTests PRIVATE cxx_std_17)
target_compile_definitions(YimeTextServiceContractTests PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(YimeTextServiceContractTests PRIVATE /utf-8 /W4 /EHsc)
target_include_directories(YimeTextServiceContractTests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} "${CMAKE_CURRENT_LIST_DIR}/../json/single_include")
target_link_libraries(YimeTextServiceContractTests PRIVATE advapi32 ole32 oleaut32 user32 gdi32)
set_property(TARGET YimeTextServiceContractTests PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

enable_testing()
add_test(NAME YimeTextServiceContractTests
    COMMAND YimeTextServiceContractTests $<TARGET_FILE:YimeTextServiceExperiment>)

add_executable(YimeFocusCancellationTests
    tests/FocusCancellationTests.cpp
    CompositionEditSession.cpp
)
target_compile_features(YimeFocusCancellationTests PRIVATE cxx_std_17)
target_compile_definitions(YimeFocusCancellationTests PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(YimeFocusCancellationTests PRIVATE /utf-8 /W4 /EHsc)
target_include_directories(YimeFocusCancellationTests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}
    "${CMAKE_CURRENT_LIST_DIR}/../json/single_include")
target_link_libraries(YimeFocusCancellationTests PRIVATE ole32)
set_property(TARGET YimeFocusCancellationTests PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
add_test(NAME YimeFocusCancellationTests COMMAND YimeFocusCancellationTests)

add_executable(YimeBrokerBridgeTests
    tests/BrokerBridgeTests.cpp
    BrokerClient.cpp
    ExperimentSettings.cpp
    KeyContract.cpp
    SurfaceSession.cpp
)
target_compile_features(YimeBrokerBridgeTests PRIVATE cxx_std_17)
target_compile_definitions(YimeBrokerBridgeTests PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(YimeBrokerBridgeTests PRIVATE /utf-8 /W4 /EHsc)
target_include_directories(YimeBrokerBridgeTests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} "${CMAKE_CURRENT_LIST_DIR}/../json/single_include")
target_link_libraries(YimeBrokerBridgeTests PRIVATE ole32)
set_property(TARGET YimeBrokerBridgeTests PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

add_executable(YimeTsfCompositionTests
    tests/TsfCompositionTests.cpp
    ExperimentSettings.cpp
)
target_compile_features(YimeTsfCompositionTests PRIVATE cxx_std_17)
target_compile_definitions(YimeTsfCompositionTests PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(YimeTsfCompositionTests PRIVATE /utf-8 /W4 /EHsc)
target_include_directories(YimeTsfCompositionTests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} "${CMAKE_CURRENT_LIST_DIR}/../json/single_include")
target_link_libraries(YimeTsfCompositionTests PRIVATE ole32 oleaut32)
set_property(TARGET YimeTsfCompositionTests PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

add_executable(YimeTextServiceRegistration RegistrationTool.cpp)
target_compile_features(YimeTextServiceRegistration PRIVATE cxx_std_17)
target_compile_definitions(YimeTextServiceRegistration PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(YimeTextServiceRegistration PRIVATE /utf-8 /W4 /EHsc)
target_include_directories(YimeTextServiceRegistration PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(YimeTextServiceRegistration PRIVATE advapi32 ole32)
set_property(TARGET YimeTextServiceRegistration PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

add_executable(YimeRegistrationQueryTests tests/RegistrationQueryTests.cpp)
target_compile_features(YimeRegistrationQueryTests PRIVATE cxx_std_17)
target_compile_definitions(YimeRegistrationQueryTests PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(YimeRegistrationQueryTests PRIVATE /utf-8 /W4 /EHsc)
target_include_directories(YimeRegistrationQueryTests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(YimeRegistrationQueryTests PRIVATE advapi32 ole32)
set_property(TARGET YimeRegistrationQueryTests PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
add_test(NAME YimeRegistrationQueryTests COMMAND YimeRegistrationQueryTests)

add_executable(YimeRegisteredHostTests
    tests/RegisteredHostTests.cpp
    ExperimentSettings.cpp
)
target_compile_features(YimeRegisteredHostTests PRIVATE cxx_std_17)
target_compile_definitions(YimeRegisteredHostTests PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(YimeRegisteredHostTests PRIVATE /utf-8 /W4 /EHsc)
target_include_directories(YimeRegisteredHostTests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}
    "${CMAKE_CURRENT_LIST_DIR}/../json/single_include")
target_link_libraries(YimeRegisteredHostTests PRIVATE ole32 oleaut32 user32)
set_property(TARGET YimeRegisteredHostTests PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

if(YIME_ARM64X_STAGE)
    include("${CMAKE_CURRENT_LIST_DIR}/cmake/Arm64X.cmake")
endif()

# Explicit S2 own-context harness; not an installed product or registration test.
# Opt in on native x64 Windows. No test is auto-registered because its paired Go
# test supplies a real dedicated-layout engine commit over bounded test stdin.
option(YIME_TOUCH_BRIDGE_OWN_HOST "Build isolated dedicated-touch TSF host harness" OFF)
if(YIME_TOUCH_BRIDGE_OWN_HOST)
    if(NOT CMAKE_GENERATOR_PLATFORM STREQUAL "x64")
        message(FATAL_ERROR "Touch bridge own-host S2 currently requires native x64")
    endif()
    add_executable(YimeTouchBridgeOwnHost tests/TouchBridgeOwnHost.cpp CompositionEditSession.cpp)
    target_compile_features(YimeTouchBridgeOwnHost PRIVATE cxx_std_17)
    target_compile_definitions(YimeTouchBridgeOwnHost PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_compile_options(YimeTouchBridgeOwnHost PRIVATE /utf-8 /W4 /EHsc)
    target_include_directories(YimeTouchBridgeOwnHost PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} "${CMAKE_CURRENT_LIST_DIR}/../json/single_include")
    target_link_libraries(YimeTouchBridgeOwnHost PRIVATE ole32 oleaut32 user32)
    set_property(TARGET YimeTouchBridgeOwnHost PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

# S3a persistent CI-only own context; no installation or product activation.
option(YIME_TOUCH_BRIDGE_PERSISTENT_HOST "Build isolated persistent UI TSF test host" OFF)
if(YIME_TOUCH_BRIDGE_PERSISTENT_HOST)
    if(NOT CMAKE_GENERATOR_PLATFORM STREQUAL "x64")
        message(FATAL_ERROR "Persistent touch bridge own-host requires native x64")
    endif()
    add_executable(YimeTouchBridgePersistentHost tests/TouchBridgePersistentHost.cpp CompositionEditSession.cpp)
    target_compile_features(YimeTouchBridgePersistentHost PRIVATE cxx_std_17)
    target_compile_definitions(YimeTouchBridgePersistentHost PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_compile_options(YimeTouchBridgePersistentHost PRIVATE /utf-8 /W4 /EHsc)
    target_include_directories(YimeTouchBridgePersistentHost PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} "${CMAKE_CURRENT_LIST_DIR}/../json/single_include")
    target_link_libraries(YimeTouchBridgePersistentHost PRIVATE ole32 oleaut32 user32)
    set_property(TARGET YimeTouchBridgePersistentHost PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

# S3b visible own-text demonstration; isolated Windows developer environments only.
option(YIME_TOUCH_BRIDGE_DEMO_HOST "Build opt-in isolated own TSF demo host" OFF)
if(YIME_TOUCH_BRIDGE_DEMO_HOST)
    if(NOT CMAKE_GENERATOR_PLATFORM STREQUAL "x64")
        message(FATAL_ERROR "Own TSF demo requires native x64")
    endif()
    add_executable(YimeTouchBridgeDemoHost tests/OwnHostDemo.cpp CompositionEditSession.cpp)
    target_compile_features(YimeTouchBridgeDemoHost PRIVATE cxx_std_17)
    target_compile_definitions(YimeTouchBridgeDemoHost PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_compile_options(YimeTouchBridgeDemoHost PRIVATE /utf-8 /W4 /EHsc)
    target_include_directories(YimeTouchBridgeDemoHost PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} "${CMAKE_CURRENT_LIST_DIR}/../json/single_include")
    target_link_libraries(YimeTouchBridgeDemoHost PRIVATE ole32 oleaut32 user32 gdi32)
    set_property(TARGET YimeTouchBridgeDemoHost PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

# S3c actual dedicated TextService DLL, direct-load validation only. No registrar.
option(YIME_TOUCH_PRODUCT "Build independent 18u CN-variable TextService slice" OFF)
option(YIME_TOUCH_REGISTRATION_PROBE "Build one-transaction isolated registration gate" OFF)
option(YIME_TOUCH_REGISTERED_FORMAL_HOST "Build host for an explicitly provisioned isolated 18u profile (does not register)" OFF)
if(YIME_TOUCH_REGISTERED_FORMAL_HOST AND NOT YIME_TOUCH_PRODUCT)
    message(FATAL_ERROR "18u registered host requires YIME_TOUCH_PRODUCT")
endif()
if(YIME_TOUCH_REGISTRATION_PROBE AND NOT YIME_TOUCH_PRODUCT)
    message(FATAL_ERROR "18u registration probe requires YIME_TOUCH_PRODUCT")
endif()
option(YIME_TOUCH_ACTIVATION_DIAGNOSTICS "Emit fixed activation-failure stages for isolated 18u CI" OFF)
if(YIME_TOUCH_ACTIVATION_DIAGNOSTICS AND NOT YIME_TOUCH_PRODUCT)
    message(FATAL_ERROR "18u activation diagnostics require YIME_TOUCH_PRODUCT")
endif()
if(YIME_TOUCH_PRODUCT)
    if(YIME_LOCAL_PRODUCT OR NOT CMAKE_GENERATOR_PLATFORM STREQUAL "x64")
        message(FATAL_ERROR "18u direct-load slice requires separate native x64 configuration")
    endif()
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/../tools/yimecore/18u-touch-product.json" TOUCH_JSON)
    string(JSON TOUCH_NAME GET "${TOUCH_JSON}" display_name)
    string(JSON TOUCH_CLSID GET "${TOUCH_JSON}" identity clsid)
    string(JSON TOUCH_PROFILE GET "${TOUCH_JSON}" identity profile)
    string(JSON TOUCH_LAYOUT GET "${TOUCH_JSON}" data layout_sha256)
    string(JSON TOUCH_DICTIONARY GET "${TOUCH_JSON}" data dictionary_sha256)
    function(touch_guid PREFIX VALUE)
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
    touch_guid(TOUCH_CLSID "${TOUCH_CLSID}")
    touch_guid(TOUCH_PROFILE "${TOUCH_PROFILE}")
    configure_file(TouchProductIdentity.h.in TouchProductIdentity.h @ONLY)
    get_target_property(TOUCH_SOURCES YimeTextServiceExperiment SOURCES)
    list(REMOVE_ITEM TOUCH_SOURCES YimeTextServiceExperiment.def)
    add_library(YimeTextService18u SHARED ${TOUCH_SOURCES} DedicatedTouchRoute.cpp DedicatedBrokerTransport.cpp YimeTextService18u.def)
    target_compile_features(YimeTextService18u PRIVATE cxx_std_17)
    target_compile_definitions(YimeTextService18u PRIVATE YIME_TOUCH_PRODUCT=1 UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
    if(YIME_TOUCH_ACTIVATION_DIAGNOSTICS)
        target_compile_definitions(YimeTextService18u PRIVATE YIME_TOUCH_ACTIVATION_DIAGNOSTICS=1)
    endif()
    target_compile_options(YimeTextService18u PRIVATE /utf-8 /W4 /EHsc)
    target_include_directories(YimeTextService18u PRIVATE "${CMAKE_CURRENT_BINARY_DIR}" "${CMAKE_CURRENT_LIST_DIR}/../json/single_include")
    target_link_libraries(YimeTextService18u PRIVATE advapi32 ole32 oleaut32 user32 gdi32)
    set_property(TARGET YimeTextService18u PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    add_executable(YimeTouchFormalHostTests tests/Formal18uHost.cpp)
    target_compile_features(YimeTouchFormalHostTests PRIVATE cxx_std_17)
    target_compile_definitions(YimeTouchFormalHostTests PRIVATE YIME_TOUCH_PRODUCT=1 UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_compile_options(YimeTouchFormalHostTests PRIVATE /utf-8 /W4 /EHsc)
    target_include_directories(YimeTouchFormalHostTests PRIVATE "${CMAKE_CURRENT_BINARY_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}" "${CMAKE_CURRENT_LIST_DIR}/../json/single_include")
    target_link_libraries(YimeTouchFormalHostTests PRIVATE advapi32 ole32 oleaut32 user32)
    set_property(TARGET YimeTouchFormalHostTests PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    add_executable(YimeDedicatedActivationTests tests/DedicatedActivationTests.cpp)
    target_compile_features(YimeDedicatedActivationTests PRIVATE cxx_std_17)
    target_compile_definitions(YimeDedicatedActivationTests PRIVATE YIME_TOUCH_PRODUCT=1 UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_compile_options(YimeDedicatedActivationTests PRIVATE /utf-8 /W4 /EHsc)
    target_include_directories(YimeDedicatedActivationTests PRIVATE "${CMAKE_CURRENT_BINARY_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}")
    target_link_libraries(YimeDedicatedActivationTests PRIVATE ole32 oleaut32 user32)
    set_property(TARGET YimeDedicatedActivationTests PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    add_executable(YimeDedicatedAsyncTests tests/DedicatedAsyncTests.cpp DedicatedTouchRoute.cpp DedicatedBrokerTransport.cpp BrokerClient.cpp CompositionEditSession.cpp)
    target_compile_features(YimeDedicatedAsyncTests PRIVATE cxx_std_17)
    target_compile_definitions(YimeDedicatedAsyncTests PRIVATE YIME_TOUCH_PRODUCT=1 UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_compile_options(YimeDedicatedAsyncTests PRIVATE /utf-8 /W4 /EHsc)
    target_include_directories(YimeDedicatedAsyncTests PRIVATE "${CMAKE_CURRENT_BINARY_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}" "${CMAKE_CURRENT_LIST_DIR}/../json/single_include")
    target_link_libraries(YimeDedicatedAsyncTests PRIVATE advapi32 ole32 oleaut32 user32)
    set_property(TARGET YimeDedicatedAsyncTests PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    add_executable(YimeActivationFailureTraceTests tests/ActivationFailureTraceTests.cpp)
    target_compile_features(YimeActivationFailureTraceTests PRIVATE cxx_std_17)
    target_compile_options(YimeActivationFailureTraceTests PRIVATE /utf-8 /W4 /EHsc)
    target_include_directories(YimeActivationFailureTraceTests PRIVATE "${CMAKE_CURRENT_LIST_DIR}/../json/single_include")
    if(YIME_TOUCH_REGISTERED_FORMAL_HOST)
        add_executable(YimeTouchRegisteredFormalHostTests tests/Formal18uHost.cpp)
        target_compile_features(YimeTouchRegisteredFormalHostTests PRIVATE cxx_std_17)
        target_compile_definitions(YimeTouchRegisteredFormalHostTests PRIVATE YIME_TOUCH_PRODUCT=1 YIME_TOUCH_REGISTERED_FORMAL_HOST=1 UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
        target_compile_options(YimeTouchRegisteredFormalHostTests PRIVATE /utf-8 /W4 /EHsc)
        target_include_directories(YimeTouchRegisteredFormalHostTests PRIVATE "${CMAKE_CURRENT_BINARY_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}" "${CMAKE_CURRENT_LIST_DIR}/../json/single_include")
        target_link_libraries(YimeTouchRegisteredFormalHostTests PRIVATE advapi32 ole32 oleaut32 user32)
        set_property(TARGET YimeTouchRegisteredFormalHostTests PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    endif()
endif()

if(YIME_TOUCH_REGISTRATION_PROBE)
    target_compile_definitions(YimeTextService18u PRIVATE YIME_TOUCH_REGISTRATION_PROBE=1)
    add_executable(Yime18uRegistrationProbe tests/RegistrationProbe.cpp)
    target_compile_features(Yime18uRegistrationProbe PRIVATE cxx_std_17)
    target_compile_definitions(Yime18uRegistrationProbe PRIVATE YIME_TOUCH_PRODUCT=1 UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_compile_options(Yime18uRegistrationProbe PRIVATE /utf-8 /W4 /EHsc)
    target_include_directories(Yime18uRegistrationProbe PRIVATE "${CMAKE_CURRENT_BINARY_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}" "${CMAKE_CURRENT_LIST_DIR}/../json/single_include")
    target_link_libraries(Yime18uRegistrationProbe PRIVATE advapi32 ole32 oleaut32 user32)
    set_property(TARGET Yime18uRegistrationProbe PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

# Read-only inventory is independent from all product/registration switches.
option(YIME_INPUT_LANGUAGE_INVENTORY "Build bounded query-only loaded input language inventory" OFF)
if(YIME_INPUT_LANGUAGE_INVENTORY)
    add_executable(YimeInputLanguageInventory tests/InputLanguageInventory.cpp)
    target_compile_features(YimeInputLanguageInventory PRIVATE cxx_std_17)
    target_compile_definitions(YimeInputLanguageInventory PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_compile_options(YimeInputLanguageInventory PRIVATE /utf-8 /W4 /EHsc)
    target_include_directories(YimeInputLanguageInventory PRIVATE "${CMAKE_CURRENT_LIST_DIR}/../json/single_include")
    target_link_libraries(YimeInputLanguageInventory PRIVATE ole32 user32)
    set_property(TARGET YimeInputLanguageInventory PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()


# Query-only installed Microsoft Pinyin proof; no product activation/registration.
option(YIME_CHINESE_INPUT_COMPONENT_QUERY "Build existing-system Chinese input component query" OFF)
if(YIME_CHINESE_INPUT_COMPONENT_QUERY)
    add_executable(YimeChineseInputComponentQuery tests/ChineseInputComponentQuery.cpp)
    target_compile_features(YimeChineseInputComponentQuery PRIVATE cxx_std_17)
    target_compile_definitions(YimeChineseInputComponentQuery PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_compile_options(YimeChineseInputComponentQuery PRIVATE /utf-8 /W4 /EHsc)
    target_include_directories(YimeChineseInputComponentQuery PRIVATE "${CMAKE_CURRENT_LIST_DIR}/../json/single_include")
    target_link_libraries(YimeChineseInputComponentQuery PRIVATE advapi32 ole32 user32)
    set_property(TARGET YimeChineseInputComponentQuery PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

# Stage 1 developer-only local tool. Default invocation is read-only; this is not
# a signed delivery package or permission to execute it on a user's machine.
option(YIME_MYCOMPUTER_ACTIVATION_STAGE1 "Build isolated MyComputer activation-stage1 tool" OFF)
if(YIME_MYCOMPUTER_ACTIVATION_STAGE1)
    if(NOT YIME_TOUCH_PRODUCT OR NOT CMAKE_GENERATOR_PLATFORM STREQUAL "x64")
        message(FATAL_ERROR "MyComputer stage1 requires the independent native x64 product target")
    endif()
    target_compile_definitions(YimeTextService18u PRIVATE YIME_TOUCH_REGISTRATION_PROBE=1)
    add_executable(YimeMyComputerActivationStage1 tests/RegistrationProbe.cpp)
    target_compile_features(YimeMyComputerActivationStage1 PRIVATE cxx_std_17)
    target_compile_definitions(YimeMyComputerActivationStage1 PRIVATE YIME_TOUCH_PRODUCT=1 YIME_MYCOMPUTER_ACTIVATION_STAGE1=1 UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_compile_options(YimeMyComputerActivationStage1 PRIVATE /utf-8 /W4 /EHsc)
    target_include_directories(YimeMyComputerActivationStage1 PRIVATE "${CMAKE_CURRENT_BINARY_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}" "${CMAKE_CURRENT_LIST_DIR}/../json/single_include")
    target_link_libraries(YimeMyComputerActivationStage1 PRIVATE advapi32 bcrypt crypt32 ole32 oleaut32 user32)
    set_property(TARGET YimeMyComputerActivationStage1 PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    add_executable(MyComputerActivationPolicyTests tests/MyComputerActivationPolicyTests.cpp)
    target_compile_features(MyComputerActivationPolicyTests PRIVATE cxx_std_17)
    # CI-only drill of residue classification/removal/snapshot on synthetic keys under
    # the 18u CLSID; no MyComputer entry point, no registration, refuses real residue.
    add_executable(YimeResidueFixtureTests tests/ResidueFixtureTests.cpp)
    target_compile_features(YimeResidueFixtureTests PRIVATE cxx_std_17)
    target_compile_definitions(YimeResidueFixtureTests PRIVATE YIME_TOUCH_PRODUCT=1 YIME_MYCOMPUTER_ACTIVATION_STAGE1=1 UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_compile_options(YimeResidueFixtureTests PRIVATE /utf-8 /W4 /EHsc)
    target_include_directories(YimeResidueFixtureTests PRIVATE "${CMAKE_CURRENT_BINARY_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}/tests" "${CMAKE_CURRENT_LIST_DIR}/../json/single_include")
    target_link_libraries(YimeResidueFixtureTests PRIVATE advapi32 bcrypt crypt32 ole32 oleaut32 user32)
    set_property(TARGET YimeResidueFixtureTests PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

# Persistent 18u installer helper; no automatic test/registration execution.
option(YIME_18U_PRODUCT_REGISTRATION "Build independent x64 18u product maintenance" OFF)
if(YIME_18U_PRODUCT_REGISTRATION)
    if(NOT YIME_TOUCH_PRODUCT OR NOT CMAKE_GENERATOR_PLATFORM STREQUAL "x64")
        message(FATAL_ERROR "18u product registration requires YIME_TOUCH_PRODUCT and x64")
    endif()
    add_executable(Yime18uProductRegistration RegistrationTool.cpp)
    target_compile_features(Yime18uProductRegistration PRIVATE cxx_std_17)
    target_compile_definitions(Yime18uProductRegistration PRIVATE YIME_TOUCH_PRODUCT=1 YIME_18U_PRODUCT_REGISTRATION=1 UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_compile_options(Yime18uProductRegistration PRIVATE /utf-8 /W4 /EHsc)
    target_include_directories(Yime18uProductRegistration PRIVATE "${CMAKE_CURRENT_BINARY_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}")
    target_link_libraries(Yime18uProductRegistration PRIVATE advapi32 ole32)
    set_property(TARGET Yime18uProductRegistration PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    add_executable(Yime18uProductRegistrationPolicyTests tests/ProductRegistrationPolicyTests.cpp)
    target_compile_features(Yime18uProductRegistrationPolicyTests PRIVATE cxx_std_17)
endif()
