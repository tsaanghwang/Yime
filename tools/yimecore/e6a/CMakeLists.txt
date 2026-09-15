cmake_minimum_required(VERSION 3.20)
project(YimeBrokerPipeProbe LANGUAGES CXX)

add_executable(YimeBrokerPipeProbe YimeBrokerPipeProbe.cpp)
target_compile_features(YimeBrokerPipeProbe PRIVATE cxx_std_17)
target_compile_definitions(YimeBrokerPipeProbe PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(YimeBrokerPipeProbe PRIVATE /utf-8 /W4 /EHsc)
target_include_directories(YimeBrokerPipeProbe PRIVATE "${CMAKE_CURRENT_LIST_DIR}/../../../json/single_include")
set_property(TARGET YimeBrokerPipeProbe PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
