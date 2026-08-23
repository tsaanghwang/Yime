cmake_minimum_required(VERSION 3.20)
project(YimeTextServiceExperiment LANGUAGES CXX)

add_library(YimeTextServiceExperiment SHARED
    DllEntry.cpp
    KeyContract.cpp
    TextService.cpp
    YimeTextServiceExperiment.def
)
target_compile_features(YimeTextServiceExperiment PRIVATE cxx_std_17)
target_compile_definitions(YimeTextServiceExperiment PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(YimeTextServiceExperiment PRIVATE /utf-8 /W4 /EHsc)
target_link_libraries(YimeTextServiceExperiment PRIVATE ole32)
set_property(TARGET YimeTextServiceExperiment PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

add_executable(YimeTextServiceContractTests
    tests/ContractTests.cpp
    KeyContract.cpp
)
target_compile_features(YimeTextServiceContractTests PRIVATE cxx_std_17)
target_compile_definitions(YimeTextServiceContractTests PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(YimeTextServiceContractTests PRIVATE /utf-8 /W4 /EHsc)
target_include_directories(YimeTextServiceContractTests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(YimeTextServiceContractTests PRIVATE ole32)
set_property(TARGET YimeTextServiceContractTests PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

enable_testing()
add_test(NAME YimeTextServiceContractTests
    COMMAND YimeTextServiceContractTests $<TARGET_FILE:YimeTextServiceExperiment>)
