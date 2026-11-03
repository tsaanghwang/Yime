cmake_minimum_required(VERSION 3.25)
project(YimeArm64HandleProbe LANGUAGES CXX)

if(NOT WIN32 OR NOT MSVC OR NOT CMAKE_GENERATOR_PLATFORM STREQUAL "ARM64")
    message(FATAL_ERROR "This isolated probe requires the native MSVC ARM64 target")
endif()

function(probe_target name source marker)
    add_executable(${name} ${source})
    target_compile_features(${name} PRIVATE cxx_std_17)
    target_compile_options(${name} PRIVATE /W4 /WX /EHsc /utf-8)
    target_compile_definitions(${name} PRIVATE SYNTHETIC_MARKER=${marker})
    target_link_libraries(${name} PRIVATE psapi)
endfunction()

add_executable(YimeArm64HandleProbe Probe.cpp)
target_compile_features(YimeArm64HandleProbe PRIVATE cxx_std_17)
target_compile_options(YimeArm64HandleProbe PRIVATE /W4 /WX /EHsc /utf-8)
target_link_libraries(YimeArm64HandleProbe PRIVATE bcrypt)

probe_target(YimeSyntheticToolA SyntheticTool.cpp A)
probe_target(YimeSyntheticToolB SyntheticTool.cpp B)

foreach(marker IN ITEMS A B)
    add_library(YimeSyntheticModule${marker} SHARED SyntheticModule.cpp)
    target_compile_features(YimeSyntheticModule${marker} PRIVATE cxx_std_17)
    target_compile_options(YimeSyntheticModule${marker} PRIVATE /W4 /WX /EHsc /utf-8)
    target_compile_definitions(YimeSyntheticModule${marker} PRIVATE SYNTHETIC_MARKER=${marker})
endforeach()
