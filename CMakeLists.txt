cmake_minimum_required(VERSION 3.5...4.0)

# override default c/c++ flags, add /MT to link VC++ runtime statically.
# NOTE: these two lines should go before the project() command according to CMake FAQ:
# https://cmake.org/Wiki/CMake_FAQ#Make_Override_Files
set(CMAKE_USER_MAKE_RULES_OVERRIDE	${CMAKE_CURRENT_SOURCE_DIR}/cmake/c_flag_overrides.cmake)
set(CMAKE_USER_MAKE_RULES_OVERRIDE_CXX	${CMAKE_CURRENT_SOURCE_DIR}/cmake/cxx_flag_overrides.cmake)

project(PIME)

# load current number from file
file(READ "version.txt" PIME_VERSION)
# we use semantic versioning: <major>.<minor>.<patch>[-<some suffix>]
# convert the version string into a list (separated by ;)
string(REGEX MATCHALL "[0-9]+" PIME_VERSION_PARTS "${PIME_VERSION}")
list(GET PIME_VERSION_PARTS 0 PIME_VERSION_MAJOR)
list(GET PIME_VERSION_PARTS 1 PIME_VERSION_MINOR)
list(GET PIME_VERSION_PARTS 2 PIME_VERSION_PATCH)

# http://www.utf8everywhere.org/
add_definitions(
	/D_UNICODE=1 /DUNICODE=1 # do Unicode build
	/D_CRT_SECURE_NO_WARNINGS # disable warnings about old libc functions
	/GR- # turn off C++ RTTI
    -DWIN32_LEAN_AND_MEAN
    -D_WIN32_WINNT=0x0600
)

enable_testing()

# Generate PDB debug info for Release builds so the C++ TSF DLL/EXEs can be
# debugged without switching to a slower Debug config. Default ON for dev
# convenience; pass -DPIME_RELEASE_DEBUG_INFO=OFF for a lean release ship build.
# Flags are appended (not replaced) and guarded against duplicates so repeated
# reconfigures do not accumulate /Zi or /DEBUG.
option(PIME_RELEASE_DEBUG_INFO "Generate PDB debug info for Release builds" ON)
if(PIME_RELEASE_DEBUG_INFO AND MSVC)
    foreach(_lang C CXX)
        if(NOT CMAKE_${_lang}_FLAGS_RELEASE MATCHES "/Zi")
            set(CMAKE_${_lang}_FLAGS_RELEASE "${CMAKE_${_lang}_FLAGS_RELEASE} /Zi" CACHE STRING "Release ${_lang} flags" FORCE)
        endif()
    endforeach()
    foreach(_link SHARED_LINKER EXE_LINKER)
        if(NOT CMAKE_${_link}_FLAGS_RELEASE MATCHES "/DEBUG")
            set(CMAKE_${_link}_FLAGS_RELEASE "${CMAKE_${_link}_FLAGS_RELEASE} /DEBUG /OPT:REF /OPT:ICF" CACHE STRING "Release ${_link} flags" FORCE)
        endif()
    endforeach()
endif()

add_subdirectory(${PROJECT_SOURCE_DIR}/libIME2)

add_subdirectory(${PROJECT_SOURCE_DIR}/PIMETextService)

# only build the following components for 32-bit x86 platform
if("${CMAKE_SIZEOF_VOID_P}" EQUAL "4")
    include(FetchContent)

    # Pin the Rust toolchain to the 32-bit (i686) host so that host == target ==
    # i686-pc-windows-msvc (target set by PIMELauncher/.cargo/config.toml). This
    # AVOIDS cross-compilation: with an x86_64 host, Corrosion (even v0.6.1) leaks
    # the i686 target MSVC lib paths into the host-side build-scripts / proc-macros
    # (serde, getrandom, proc-macro2, ...), producing LNK4272 machine-type conflicts
    # and 145+ unresolved externals. With an i686 host there is no host/target split
    # and build-scripts link correctly. Requires: rustup toolchain install
    # stable-i686-pc-windows-msvc  (i686 binaries run on x64 Windows via WoW64).
    set(Rust_TOOLCHAIN "stable-i686-pc-windows-msvc" CACHE STRING "Rust toolchain for 32-bit PIMELauncher build")

    # Corrosion v0.6.1 (2026-01-17) fixes host linker detection for build-scripts
    # and proc-macros and adds CORROSION_HOST_TARGET_LINKER. v0.6.1 is the latest
    # release as of 2026-07.
    FetchContent_Declare(
        Corrosion
        GIT_REPOSITORY https://github.com/corrosion-rs/corrosion.git
        GIT_TAG v0.6.1
    )
    FetchContent_MakeAvailable(Corrosion)

    add_subdirectory(${PROJECT_SOURCE_DIR}/PIMELauncher)
endif("${CMAKE_SIZEOF_VOID_P}" EQUAL "4")
