@echo off
setlocal

set "CMAKE_EXE=cmake"
if not exist "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools\MSBuild\Microsoft\VC\v170\Platforms\ARM64" set "SKIP_ARM64=1"
dir /b /s "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\*\bin\Hostx64\arm64\cl.exe" >nul 2>&1 || set "SKIP_ARM64=1"

where cmake >nul 2>&1
if errorlevel 1 (
	if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" (
		set "CMAKE_EXE=%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
	) else if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\2019\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" (
		set "CMAKE_EXE=%ProgramFiles(x86)%\Microsoft Visual Studio\2019\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
	) else (
		echo CMake was not found. Install CMake or add it to PATH.
		exit /b 1
	)
)

"%CMAKE_EXE%" . -Bbuild -G "Visual Studio 17 2022" -A Win32 -DCMAKE_POLICY_VERSION_MINIMUM=3.5 || exit /b 1
"%CMAKE_EXE%" --build build --config Release || exit /b 1

"%CMAKE_EXE%" . -Bbuild64 -G "Visual Studio 17 2022" -A x64 -DCMAKE_POLICY_VERSION_MINIMUM=3.5 || exit /b 1
"%CMAKE_EXE%" --build build64 --config Release --target PIMETextService || exit /b 1

if defined SKIP_ARM64 (
	echo Skipping ARM64 build. Install VS2022 ARM64 C++ build tools to enable it.
) else (
	"%CMAKE_EXE%" . -Bbuild_arm64 -G "Visual Studio 17 2022" -A ARM64 -DCMAKE_POLICY_VERSION_MINIMUM=3.5 || exit /b 1
	"%CMAKE_EXE%" --build build_arm64 --config Release --target PIMETextService || exit /b 1
)

echo "Start building go-backend"
pushd go-backend || exit /b 1
cmd /C build.bat || exit /b 1
popd

echo "Start building McBopomofo"
pushd McBopomofoWeb || exit /b 1
cmd /C npm install || exit /b 1
cmd /C npm run build:pime || exit /b 1
popd

echo "Copy McBopomofo to node\input_methods\McBopomofo"
cmd /C rd /s /q node\input_methods\McBopomofo
cmd /C mkdir node\input_methods\McBopomofo || exit /b 1
cmd /C xcopy /s /q /y /f McBopomofoWeb\output\pime node\input_methods\McBopomofo\. || exit /b 1
