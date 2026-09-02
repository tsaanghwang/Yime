cmake_minimum_required(VERSION 3.20)
project(YimeTextServiceExperiment LANGUAGES CXX)

option(YIME_LOCAL_PRODUCT "Build the current-PC independent product display identity" OFF)
if(YIME_LOCAL_PRODUCT)
    if(NOT CMAKE_GENERATOR_PLATFORM STREQUAL "x64")
        message(FATAL_ERROR "Local product builds are native x64 only")
    endif()
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/../tools/yimecore/local-product.json" YIME_PRODUCT_JSON)
    string(JSON YIME_LOCAL_PRODUCT_NAME GET "${YIME_PRODUCT_JSON}" display_name)
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
