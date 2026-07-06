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
set "SKIP_ARM64=1"
set "_VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if exist "%_VSWHERE%" (
	"%_VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.ARM64 -property installationPath >nul 2>&1 && set "SKIP_ARM64="
)

where cmake >nul 2>&1
if errorlevel 1 (
	for %%Y in (2022 2019) do (
		for %%E in (BuildTools Enterprise Community Professional) do (
			if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\%%Y\%%E\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" (
				set "CMAKE_EXE=%ProgramFiles(x86)%\Microsoft Visual Studio\%%Y\%%E\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
				goto :cmake_found
			)
			if exist "%ProgramFiles%\Microsoft Visual Studio\%%Y\%%E\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" (
				set "CMAKE_EXE=%ProgramFiles%\Microsoft Visual Studio\%%Y\%%E\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
				goto :cmake_found
			)
		)
	)
	echo CMake was not found. Install CMake or add it to PATH.
	exit /b 1
)
:cmake_found

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

echo "Refresh test install command files"
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\tools\refresh-dev-test-cmds.ps1" -RepoRoot "%ROOT_DIR%" || exit /b 1

goto :eof

:find_vsdevcmd
set "VS_DEV_CMD="

rem vswhere.exe is the canonical locator for VS 2017+ installations.
set "_VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if exist "%_VSWHERE%" (
	for /f "usebackq delims=" %%I in (`"%_VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2^>nul`) do (
		if exist "%%I\Common7\Tools\VsDevCmd.bat" (
			set "VS_DEV_CMD=%%I\Common7\Tools\VsDevCmd.bat"
			goto :vsdevcmd_found
		)
	)
)

rem Fall back to well-known fixed paths.
for %%Y in (2022 2019) do (
	for %%E in (Enterprise Community Professional BuildTools) do (
		if exist "%ProgramFiles%\Microsoft Visual Studio\%%Y\%%E\Common7\Tools\VsDevCmd.bat" (
			set "VS_DEV_CMD=%ProgramFiles%\Microsoft Visual Studio\%%Y\%%E\Common7\Tools\VsDevCmd.bat"
			goto :vsdevcmd_found
		)
		if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\%%Y\%%E\Common7\Tools\VsDevCmd.bat" (
			set "VS_DEV_CMD=%ProgramFiles(x86)%\Microsoft Visual Studio\%%Y\%%E\Common7\Tools\VsDevCmd.bat"
			goto :vsdevcmd_found
		)
	)
)
if exist "C:\BuildTools\Common7\Tools\VsDevCmd.bat" (
	set "VS_DEV_CMD=C:\BuildTools\Common7\Tools\VsDevCmd.bat"
	goto :vsdevcmd_found
)
echo Visual Studio environment script was not found.
exit /b 1

:vsdevcmd_found
exit /b 0
