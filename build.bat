@echo off
setlocal

if /I not "%~1"=="--sanitized" (
	powershell -NoProfile -ExecutionPolicy Bypass -Command ^
		"$path = [System.Environment]::GetEnvironmentVariable('Path', 'Process'); $script = '%~f0'; Remove-Item Env:PATH -ErrorAction SilentlyContinue; $env:Path = $path; & $script --sanitized" 
	exit /b %errorlevel%
)

set "ROOT_DIR=%~dp0"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"

if not defined GOCACHE set "GOCACHE=%ROOT_DIR%\.tmp\gocache"
if not defined GOMODCACHE set "GOMODCACHE=%ROOT_DIR%\.tmp\gomodcache"
if not exist "%GOCACHE%" mkdir "%GOCACHE%" >nul 2>&1
if not exist "%GOMODCACHE%" mkdir "%GOMODCACHE%" >nul 2>&1

call :find_vsdevcmd
if errorlevel 1 exit /b 1

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

call "%VS_DEV_CMD%" -arch=x86 -host_arch=x64 >nul || exit /b 1
"%CMAKE_EXE%" . -Bbuild -G "Visual Studio 17 2022" -A Win32 -DCMAKE_POLICY_VERSION_MINIMUM=3.5 || exit /b 1
"%CMAKE_EXE%" --build build --config Release || exit /b 1

call "%VS_DEV_CMD%" -arch=x64 -host_arch=x64 >nul || exit /b 1
"%CMAKE_EXE%" . -Bbuild64 -G "Visual Studio 17 2022" -A x64 -DCMAKE_POLICY_VERSION_MINIMUM=3.5 || exit /b 1
"%CMAKE_EXE%" --build build64 --config Release --target PIMETextService || exit /b 1

if defined SKIP_ARM64 (
	echo Skipping ARM64 build. Install VS2022 ARM64 C++ build tools to enable it.
) else (
	call "%VS_DEV_CMD%" -arch=arm64 -host_arch=x64 >nul || exit /b 1
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

goto :eof

:find_vsdevcmd
set "VS_DEV_CMD="
if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" (
	set "VS_DEV_CMD=%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat"
) else if exist "%ProgramFiles%\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" (
	set "VS_DEV_CMD=%ProgramFiles%\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat"
) else if exist "C:\BuildTools\Common7\Tools\VsDevCmd.bat" (
	set "VS_DEV_CMD=C:\BuildTools\Common7\Tools\VsDevCmd.bat"
) else (
	echo Visual Studio Build Tools environment script was not found.
	exit /b 1
)
exit /b 0
