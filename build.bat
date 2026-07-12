@echo off
setlocal

if /I not "%~1"=="--sanitized" (
	powershell -NoProfile -ExecutionPolicy Bypass -Command ^
		"$path = [System.Environment]::GetEnvironmentVariable('Path', 'Process'); $script = '%~f0'; Remove-Item Env:PATH -ErrorAction SilentlyContinue; $env:Path = $path; & $script --sanitized; exit $LASTEXITCODE"
	if errorlevel 1 exit /b 1
	exit /b 0
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
set "SKIP_ARM64=1"
call :detect_arm64_toolchain

where cmake >nul 2>&1
if errorlevel 1 (
	call :find_vs_cmake
	if errorlevel 1 (
		echo CMake was not found. Install CMake or add it to PATH.
		exit /b 1
	)
)
:cmake_found

call "%VS_DEV_CMD%" -arch=x86 -host_arch=x64 >nul || exit /b 1
"%CMAKE_EXE%" . -Bbuild -G "Visual Studio 17 2022" -A Win32 -DCMAKE_POLICY_VERSION_MINIMUM=3.5 || exit /b 1
"%CMAKE_EXE%" --build build --config Release --target PIMETextService || exit /b 1
call :build_pimelauncher || exit /b 1

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

echo "Refresh test install command files"
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\tools\refresh-dev-test-cmds.ps1" -RepoRoot "%ROOT_DIR%" || exit /b 1

goto :eof

:detect_arm64_toolchain
rem vswhere may report the ARM64 component even when cl.exe for arm64 is not installed.
rem Only enable the ARM64 build when the compiler binary is actually present.
set "_ARM64_CL="
if defined VS_INSTALL_ROOT (
	for /d %%M in ("%VS_INSTALL_ROOT%VC\Tools\MSVC\*") do (
		if exist "%%~fM\bin\Hostx64\arm64\cl.exe" set "_ARM64_CL=%%~fM\bin\Hostx64\arm64\cl.exe"
	)
)
if not defined _ARM64_CL if exist "C:\BuildTools\VC\Tools\MSVC" (
	for /d %%M in ("C:\BuildTools\VC\Tools\MSVC\*") do (
		if exist "%%~fM\bin\Hostx64\arm64\cl.exe" set "_ARM64_CL=%%~fM\bin\Hostx64\arm64\cl.exe"
	)
)
if not defined _ARM64_CL (
	for %%Y in (2022 2019) do (
		for %%E in (BuildTools Enterprise Community Professional) do (
			for /d %%M in ("%ProgramFiles(x86)%\Microsoft Visual Studio\%%Y\%%E\VC\Tools\MSVC\*") do (
				if exist "%%~fM\bin\Hostx64\arm64\cl.exe" set "_ARM64_CL=%%~fM\bin\Hostx64\arm64\cl.exe"
			)
			for /d %%M in ("%ProgramFiles%\Microsoft Visual Studio\%%Y\%%E\VC\Tools\MSVC\*") do (
				if exist "%%~fM\bin\Hostx64\arm64\cl.exe" set "_ARM64_CL=%%~fM\bin\Hostx64\arm64\cl.exe"
			)
		)
	)
)
if defined _ARM64_CL set "SKIP_ARM64="
exit /b 0

:build_pimelauncher
rem Corrosion builds under build\Win32\Release\cargo\ and Windows Application Control
rem (Smart App Control / WDAC, os error 4551) may block those ephemeral build-script exes.
rem cargo build in PIMELauncher\target\ is not affected; stage the output for installer/dev-install.
echo "Start building PIMELauncher"
set "CARGO_TARGET_DIR="
pushd "%ROOT_DIR%\PIMELauncher" || exit /b 1
cargo build --release --target i686-pc-windows-msvc || (
	popd
	exit /b 1
)
popd
if not exist "%ROOT_DIR%\build\PIMELauncher" mkdir "%ROOT_DIR%\build\PIMELauncher" >nul 2>&1
copy /Y "%ROOT_DIR%\PIMELauncher\target\i686-pc-windows-msvc\release\PIMELauncher.exe" "%ROOT_DIR%\build\PIMELauncher\PIMELauncher.exe" >nul || exit /b 1
exit /b 0

:find_vs_cmake
set "CMAKE_EXE="
call :set_cmake_from_vs_root "%VS_INSTALL_ROOT%"
if defined CMAKE_EXE exit /b 0

for %%Y in (2022 2019) do (
	for %%E in (BuildTools Enterprise Community Professional) do (
		if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\%%Y\%%E\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" (
			set "CMAKE_EXE=%ProgramFiles(x86)%\Microsoft Visual Studio\%%Y\%%E\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
			exit /b 0
		)
		if exist "%ProgramFiles%\Microsoft Visual Studio\%%Y\%%E\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" (
			set "CMAKE_EXE=%ProgramFiles%\Microsoft Visual Studio\%%Y\%%E\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
			exit /b 0
		)
	)
)
exit /b 1

:find_vsdevcmd
set "VS_DEV_CMD="
set "VS_INSTALL_ROOT="

if defined VSINSTALLDIR (
	if exist "%VSINSTALLDIR%Common7\Tools\VsDevCmd.bat" (
		set "VS_DEV_CMD=%VSINSTALLDIR%Common7\Tools\VsDevCmd.bat"
		set "VS_INSTALL_ROOT=%VSINSTALLDIR%"
		goto :vsdevcmd_found
	)
)

rem vswhere.exe is the canonical locator for VS 2017+ installations.
rem Try the environment-variable path first, then the hard-coded fallback.
set "_VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%_VSWHERE%" set "_VSWHERE=C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
if exist "%_VSWHERE%" (
	for /f "usebackq delims=" %%I in (`"%_VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2^>nul`) do (
		if exist "%%~I\Common7\Tools\VsDevCmd.bat" (
			set "VS_DEV_CMD=%%~I\Common7\Tools\VsDevCmd.bat"
			set "VS_INSTALL_ROOT=%%~I\"
			goto :vsdevcmd_found
		)
	)
	for /f "usebackq delims=" %%I in (`"%_VSWHERE%" -latest -products * -property installationPath 2^>nul`) do (
		if exist "%%~I\Common7\Tools\VsDevCmd.bat" (
			set "VS_DEV_CMD=%%~I\Common7\Tools\VsDevCmd.bat"
			set "VS_INSTALL_ROOT=%%~I\"
			goto :vsdevcmd_found
		)
	)
)

rem Fall back to well-known fixed paths.
for %%Y in (2022 2019) do (
	for %%E in (Enterprise Community Professional BuildTools) do (
		if exist "%ProgramFiles%\Microsoft Visual Studio\%%Y\%%E\Common7\Tools\VsDevCmd.bat" (
			set "VS_DEV_CMD=%ProgramFiles%\Microsoft Visual Studio\%%Y\%%E\Common7\Tools\VsDevCmd.bat"
			set "VS_INSTALL_ROOT=%ProgramFiles%\Microsoft Visual Studio\%%Y\%%E\"
			goto :vsdevcmd_found
		)
		if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\%%Y\%%E\Common7\Tools\VsDevCmd.bat" (
			set "VS_DEV_CMD=%ProgramFiles(x86)%\Microsoft Visual Studio\%%Y\%%E\Common7\Tools\VsDevCmd.bat"
			set "VS_INSTALL_ROOT=%ProgramFiles(x86)%\Microsoft Visual Studio\%%Y\%%E\"
			goto :vsdevcmd_found
		)
	)
)
if exist "C:\BuildTools\Common7\Tools\VsDevCmd.bat" (
	set "VS_DEV_CMD=C:\BuildTools\Common7\Tools\VsDevCmd.bat"
	set "VS_INSTALL_ROOT=C:\BuildTools\"
	goto :vsdevcmd_found
)
echo Visual Studio environment script was not found.
echo   vswhere path: %_VSWHERE%
echo   ProgramFiles: %ProgramFiles%
echo   ProgramFiles(x86): %ProgramFiles(x86)%
exit /b 1

:set_cmake_from_vs_root
set "_VS_ROOT=%~1"
if not defined _VS_ROOT exit /b 1
if exist "%_VS_ROOT%Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" (
	set "CMAKE_EXE=%_VS_ROOT%Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
	exit /b 0
)
exit /b 1

:vsdevcmd_found
exit /b 0

