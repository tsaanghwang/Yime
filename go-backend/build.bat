@echo off
setlocal

echo ============================================
echo  YIME Go Backend Build Script
echo ============================================
echo.

set "ROOT_DIR=%~dp0"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"
for %%I in ("%ROOT_DIR%\..") do set "PIME_ROOT=%%~fI"
set "BUILD_ROOT=%ROOT_DIR%\build"
set "PACKAGE_DIR=%BUILD_ROOT%\go-backend"
set "SERVER_EXE=%PACKAGE_DIR%\server.exe"
set "REVERSE_LOOKUP_EXE=%PACKAGE_DIR%\reverse-lookup.exe"
set "TOOL_HUB_EXE=%PACKAGE_DIR%\tool-hub.exe"
set "LEXICON_MANAGER_EXE=%PACKAGE_DIR%\lexicon-manager.exe"
set "SYSTEM_LEXICON_AUDIT_EXE=%PACKAGE_DIR%\system-lexicon-audit.exe"
set "BLOCKLIST_MANAGER_EXE=%PACKAGE_DIR%\blocklist-manager.exe"
set "SETTINGS_TOOL_EXE=%PACKAGE_DIR%\settings-tool.exe"
set "DIAGNOSTICS_TOOL_EXE=%PACKAGE_DIR%\diagnostics-tool.exe"
set "LAYOUT_DESIGNER_EXE=%PACKAGE_DIR%\yime-layout-designer.exe"
set "BACKEND_SNIPPET=%BUILD_ROOT%\backends.go-backend.json"
set "RIME_DIR=%ROOT_DIR%\input_methods\yime"
set "RIME_DATA_DIR=%RIME_DIR%\data"
set "RIME_RUNTIME_LOCK=%RIME_DIR%\rime_runtime.lock.json"
set "PACKAGE_RIME_DIR=%PACKAGE_DIR%\input_methods\yime"
set "PACKAGE_RIME_DATA_DIR=%PACKAGE_RIME_DIR%\data"

if not defined GOCACHE set "GOCACHE=%PIME_ROOT%\.tmp\go-cache"
if not defined GOTMPDIR set "GOTMPDIR=%PIME_ROOT%\.tmp\go-tmp"
if not exist "%GOCACHE%" mkdir "%GOCACHE%" >nul 2>&1
if not exist "%GOTMPDIR%" mkdir "%GOTMPDIR%" >nul 2>&1
echo [INFO] Go cache: "%GOCACHE%"
echo [INFO] Go temp:  "%GOTMPDIR%"

REM Check Go environment
where go >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Go was not found in PATH.
    echo Install Go from: https://golang.org/dl/
    exit /b 1
)

for /f "tokens=3" %%i in ('go version') do (
    echo [INFO] Go version: %%i
)

echo.
echo ============================================
echo Step 1: Prepare output directory
echo ============================================
echo.

if exist "%PACKAGE_DIR%" (
    echo [INFO] Removing old build output: "%PACKAGE_DIR%"
    rmdir /s /q "%PACKAGE_DIR%"
)

mkdir "%PACKAGE_DIR%"
if errorlevel 1 (
    echo [ERROR] Failed to create output directory: "%PACKAGE_DIR%"
    exit /b 1
)

echo [INFO] Output directory: "%PACKAGE_DIR%"

for %%F in (
    default.yaml
    symbols.yaml
    essay.txt
    luna_pinyin.dict.yaml
    luna_pinyin.schema.yaml
    cangjie5.dict.yaml
    cangjie5.schema.yaml
) do (
    if not exist "%RIME_DATA_DIR%\%%F" (
        echo [ERROR] Missing pinned Rime shared data: "%RIME_DATA_DIR%\%%F"
        exit /b 1
    )
)
if not exist "%RIME_DATA_DIR%\opencc\t2s.json" (
    echo [ERROR] Missing pinned OpenCC shared data: "%RIME_DATA_DIR%\opencc"
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PIME_ROOT%\tools\verify-rime-runtime.ps1" -RuntimeDir "%RIME_DIR%" -LockFile "%RIME_RUNTIME_LOCK%"
if errorlevel 1 (
    echo [ERROR] Pinned Rime runtime verification failed.
    exit /b 1
)

echo.
echo ============================================
echo Step 2: Sync Go dependencies
echo ============================================
echo.

pushd "%ROOT_DIR%"
go mod tidy
if errorlevel 1 (
    echo [WARN] go mod tidy failed, continuing...
)

echo.
echo ============================================
echo Step 3: Build go-backend server
echo ============================================
echo.

set "GOOS=windows"
set "GOARCH=amd64"
set "CGO_ENABLED=0"

set "APP_VERSION=1.0.0"
if exist "%PIME_ROOT%\version.txt" set /p APP_VERSION=<"%PIME_ROOT%\version.txt"
set "GO_REPRO_FLAGS=-trimpath -buildvcs=false"

REM Prefer go-winres from PATH, then fall back to the standard GOPATH bin.
REM Some launchers provide a malformed or incomplete user PATH even though the
REM installed Go tool remains available under GOPATH\bin.
set "GO_WINRES="
for /f "delims=" %%I in ('where.exe go-winres.exe 2^>nul') do if not defined GO_WINRES set "GO_WINRES=%%~fI"
if not defined GO_WINRES (
    for /f "usebackq delims=" %%I in (`go env GOPATH`) do (
        if exist "%%~fI\bin\go-winres.exe" set "GO_WINRES=%%~fI\bin\go-winres.exe"
    )
)
if not defined GO_WINRES set "GO_WINRES=go-winres"

echo [INFO] App version: %APP_VERSION%
echo [INFO] go-winres: "%GO_WINRES%"

echo [INFO] Generating Windows VERSIONINFO resources ...
"%GO_WINRES%" simply --arch amd64 --product-version "%APP_VERSION%" --file-version "%APP_VERSION%" --product-name "YIME" --copyright "Copyright (C) 2026 Yime contributors" --file-description "YIME Go Backend Server" --original-filename "server.exe" --icon input_methods\yime\icon.ico --manifest cli --out rsrc_server
if errorlevel 1 (
    echo [WARN] go-winres failed for server.exe, building without VERSIONINFO
    if exist rsrc_server_windows_amd64.syso del rsrc_server_windows_amd64.syso
)

echo [INFO] Building server.exe with dynamic DLL loading ...
go build %GO_REPRO_FLAGS% -ldflags "-s -w -X main.version=%APP_VERSION%" -o "%SERVER_EXE%" .
if errorlevel 1 (
    echo [ERROR] Failed to build server.exe
    if exist rsrc_server_windows_amd64.syso del rsrc_server_windows_amd64.syso
    popd
    exit /b 1
)

if exist rsrc_server_windows_amd64.syso del rsrc_server_windows_amd64.syso

echo [INFO] Built: "%SERVER_EXE%"

echo [INFO] Generating Windows VERSIONINFO resources for reverse-lookup ...
"%GO_WINRES%" simply --arch amd64 --product-version "%APP_VERSION%" --file-version "%APP_VERSION%" --product-name "YIME" --copyright "Copyright (C) 2026 Yime contributors" --file-description "Yime Reverse Lookup Tool" --original-filename "reverse-lookup.exe" --icon input_methods\yime\icon.ico --manifest gui --out cmd\reverse-lookup-tool\rsrc_reverse
if errorlevel 1 (
    echo [WARN] go-winres failed for reverse-lookup.exe, building without VERSIONINFO
    if exist cmd\reverse-lookup-tool\rsrc_reverse_windows_amd64.syso del cmd\reverse-lookup-tool\rsrc_reverse_windows_amd64.syso
)

echo [INFO] Building reverse-lookup.exe ...
go build %GO_REPRO_FLAGS% -ldflags "-s -w -H=windowsgui -X main.version=%APP_VERSION%" -o "%REVERSE_LOOKUP_EXE%" .\cmd\reverse-lookup-tool
if errorlevel 1 (
    echo [ERROR] Failed to build reverse-lookup.exe
    if exist cmd\reverse-lookup-tool\rsrc_reverse_windows_amd64.syso del cmd\reverse-lookup-tool\rsrc_reverse_windows_amd64.syso
    popd
    exit /b 1
)

if exist cmd\reverse-lookup-tool\rsrc_reverse_windows_amd64.syso del cmd\reverse-lookup-tool\rsrc_reverse_windows_amd64.syso

echo [INFO] Built: "%REVERSE_LOOKUP_EXE%"

echo [INFO] Generating Windows VERSIONINFO resources for tool-hub ...
"%GO_WINRES%" simply --arch amd64 --product-version "%APP_VERSION%" --file-version "%APP_VERSION%" --product-name "YIME" --copyright "Copyright (C) 2026 Yime contributors" --file-description "Yime Tool Hub" --original-filename "tool-hub.exe" --icon input_methods\yime\icon.ico --manifest gui --out cmd\tool-hub\rsrc_hub
if errorlevel 1 (
    echo [WARN] go-winres failed for tool-hub.exe, building without VERSIONINFO
    if exist cmd\tool-hub\rsrc_hub_windows_amd64.syso del cmd\tool-hub\rsrc_hub_windows_amd64.syso
)

echo [INFO] Building tool-hub.exe ...
go build %GO_REPRO_FLAGS% -ldflags "-s -w -H=windowsgui -X main.version=%APP_VERSION%" -o "%TOOL_HUB_EXE%" .\cmd\tool-hub
if errorlevel 1 (
    echo [ERROR] Failed to build tool-hub.exe
    if exist cmd\tool-hub\rsrc_hub_windows_amd64.syso del cmd\tool-hub\rsrc_hub_windows_amd64.syso
    popd
    exit /b 1
)

if exist cmd\tool-hub\rsrc_hub_windows_amd64.syso del cmd\tool-hub\rsrc_hub_windows_amd64.syso

echo [INFO] Built: "%TOOL_HUB_EXE%"

echo [INFO] Generating Windows VERSIONINFO resources for lexicon-manager ...
"%GO_WINRES%" simply --arch amd64 --product-version "%APP_VERSION%" --file-version "%APP_VERSION%" --product-name "YIME" --copyright "Copyright (C) 2026 Yime contributors" --file-description "Yime Lexicon Manager" --original-filename "lexicon-manager.exe" --icon input_methods\yime\icon.ico --manifest gui --out cmd\lexicon-manager\rsrc_lexicon
if errorlevel 1 (
    echo [WARN] go-winres failed for lexicon-manager.exe, building without VERSIONINFO
    if exist cmd\lexicon-manager\rsrc_lexicon_windows_amd64.syso del cmd\lexicon-manager\rsrc_lexicon_windows_amd64.syso
)

echo [INFO] Building lexicon-manager.exe ...
go build %GO_REPRO_FLAGS% -ldflags "-s -w -H=windowsgui -X main.version=%APP_VERSION%" -o "%LEXICON_MANAGER_EXE%" .\cmd\lexicon-manager
if errorlevel 1 (
    echo [ERROR] Failed to build lexicon-manager.exe
    if exist cmd\lexicon-manager\rsrc_lexicon_windows_amd64.syso del cmd\lexicon-manager\rsrc_lexicon_windows_amd64.syso
    popd
    exit /b 1
)

if exist cmd\lexicon-manager\rsrc_lexicon_windows_amd64.syso del cmd\lexicon-manager\rsrc_lexicon_windows_amd64.syso

echo [INFO] Built: "%LEXICON_MANAGER_EXE%"

echo [INFO] Generating Windows VERSIONINFO resources for system-lexicon-audit ...
"%GO_WINRES%" simply --arch amd64 --product-version "%APP_VERSION%" --file-version "%APP_VERSION%" --product-name "YIME" --copyright "Copyright (C) 2026 Yime contributors" --file-description "Yime System Lexicon Audit" --original-filename "system-lexicon-audit.exe" --icon input_methods\yime\icon.ico --manifest gui --out cmd\system-lexicon-audit\rsrc_audit
if errorlevel 1 (
    echo [WARN] go-winres failed for system-lexicon-audit.exe, building without VERSIONINFO
    if exist cmd\system-lexicon-audit\rsrc_audit_windows_amd64.syso del cmd\system-lexicon-audit\rsrc_audit_windows_amd64.syso
)

echo [INFO] Building system-lexicon-audit.exe ...
go build %GO_REPRO_FLAGS% -ldflags "-s -w -H=windowsgui -X main.version=%APP_VERSION%" -o "%SYSTEM_LEXICON_AUDIT_EXE%" .\cmd\system-lexicon-audit
if errorlevel 1 (
    echo [ERROR] Failed to build system-lexicon-audit.exe
    if exist cmd\system-lexicon-audit\rsrc_audit_windows_amd64.syso del cmd\system-lexicon-audit\rsrc_audit_windows_amd64.syso
    popd
    exit /b 1
)

if exist cmd\system-lexicon-audit\rsrc_audit_windows_amd64.syso del cmd\system-lexicon-audit\rsrc_audit_windows_amd64.syso

echo [INFO] Built: "%SYSTEM_LEXICON_AUDIT_EXE%"

echo [INFO] Generating Windows VERSIONINFO resources for blocklist-manager ...
"%GO_WINRES%" simply --arch amd64 --product-version "%APP_VERSION%" --file-version "%APP_VERSION%" --product-name "YIME" --copyright "Copyright (C) 2026 Yime contributors" --file-description "Yime User Blocklist Manager" --original-filename "blocklist-manager.exe" --icon input_methods\yime\icon.ico --manifest gui --out cmd\blocklist-manager\rsrc_blocklist
if errorlevel 1 (
    echo [WARN] go-winres failed for blocklist-manager.exe, building without VERSIONINFO
    if exist cmd\blocklist-manager\rsrc_blocklist_windows_amd64.syso del cmd\blocklist-manager\rsrc_blocklist_windows_amd64.syso
)

echo [INFO] Building blocklist-manager.exe ...
go build %GO_REPRO_FLAGS% -ldflags "-s -w -H=windowsgui -X main.version=%APP_VERSION%" -o "%BLOCKLIST_MANAGER_EXE%" .\cmd\blocklist-manager
if errorlevel 1 (
    echo [ERROR] Failed to build blocklist-manager.exe
    if exist cmd\blocklist-manager\rsrc_blocklist_windows_amd64.syso del cmd\blocklist-manager\rsrc_blocklist_windows_amd64.syso
    popd
    exit /b 1
)

if exist cmd\blocklist-manager\rsrc_blocklist_windows_amd64.syso del cmd\blocklist-manager\rsrc_blocklist_windows_amd64.syso

echo [INFO] Built: "%BLOCKLIST_MANAGER_EXE%"

echo [INFO] Generating Windows VERSIONINFO resources for settings-tool ...
"%GO_WINRES%" simply --arch amd64 --product-version "%APP_VERSION%" --file-version "%APP_VERSION%" --product-name "YIME" --copyright "Copyright (C) 2026 Yime contributors" --file-description "Yime Settings Tool" --original-filename "settings-tool.exe" --icon input_methods\yime\icon.ico --manifest gui --out cmd\settings-tool\rsrc_settings
if errorlevel 1 (
    echo [WARN] go-winres failed for settings-tool.exe, building without VERSIONINFO
    if exist cmd\settings-tool\rsrc_settings_windows_amd64.syso del cmd\settings-tool\rsrc_settings_windows_amd64.syso
)

echo [INFO] Building settings-tool.exe ...
go build %GO_REPRO_FLAGS% -ldflags "-s -w -H=windowsgui -X main.version=%APP_VERSION%" -o "%SETTINGS_TOOL_EXE%" .\cmd\settings-tool
if errorlevel 1 (
    echo [ERROR] Failed to build settings-tool.exe
    if exist cmd\settings-tool\rsrc_settings_windows_amd64.syso del cmd\settings-tool\rsrc_settings_windows_amd64.syso
    popd
    exit /b 1
)

if exist cmd\settings-tool\rsrc_settings_windows_amd64.syso del cmd\settings-tool\rsrc_settings_windows_amd64.syso

echo [INFO] Built: "%SETTINGS_TOOL_EXE%"

echo [INFO] Generating Windows VERSIONINFO resources for diagnostics-tool ...
"%GO_WINRES%" simply --arch amd64 --product-version "%APP_VERSION%" --file-version "%APP_VERSION%" --product-name "YIME" --copyright "Copyright (C) 2026 Yime contributors" --file-description "Yime Diagnostics Tool" --original-filename "diagnostics-tool.exe" --icon input_methods\yime\icon.ico --manifest gui --out cmd\diagnostics-tool\rsrc_diagnostics
if errorlevel 1 (
    echo [WARN] go-winres failed for diagnostics-tool.exe, building without VERSIONINFO
    if exist cmd\diagnostics-tool\rsrc_diagnostics_windows_amd64.syso del cmd\diagnostics-tool\rsrc_diagnostics_windows_amd64.syso
)

echo [INFO] Building diagnostics-tool.exe ...
go build %GO_REPRO_FLAGS% -ldflags "-s -w -H=windowsgui -X main.version=%APP_VERSION%" -o "%DIAGNOSTICS_TOOL_EXE%" .\cmd\diagnostics-tool
if errorlevel 1 (
    echo [ERROR] Failed to build diagnostics-tool.exe
    if exist cmd\diagnostics-tool\rsrc_diagnostics_windows_amd64.syso del cmd\diagnostics-tool\rsrc_diagnostics_windows_amd64.syso
    popd
    exit /b 1
)

if exist cmd\diagnostics-tool\rsrc_diagnostics_windows_amd64.syso del cmd\diagnostics-tool\rsrc_diagnostics_windows_amd64.syso

echo [INFO] Built: "%DIAGNOSTICS_TOOL_EXE%"

echo [INFO] Generating Windows VERSIONINFO resources for yime-layout-designer ...
"%GO_WINRES%" simply --arch amd64 --product-version "%APP_VERSION%" --file-version "%APP_VERSION%" --product-name "YIME" --copyright "Copyright (C) 2026 Yime contributors" --file-description "Yime Layout Designer" --original-filename "yime-layout-designer.exe" --icon input_methods\yime\icon.ico --manifest gui --out cmd\yime-layout-designer\rsrc_layout_designer
if errorlevel 1 (
    echo [WARN] go-winres failed for yime-layout-designer.exe, building without VERSIONINFO
    if exist cmd\yime-layout-designer\rsrc_layout_designer_windows_amd64.syso del cmd\yime-layout-designer\rsrc_layout_designer_windows_amd64.syso
)

echo [INFO] Building yime-layout-designer.exe (graphical and console maintenance tool) ...
go build %GO_REPRO_FLAGS% -ldflags "-s -w -X main.version=%APP_VERSION%" -o "%LAYOUT_DESIGNER_EXE%" .\cmd\yime-layout-designer
if errorlevel 1 (
    echo [ERROR] Failed to build yime-layout-designer.exe
    if exist cmd\yime-layout-designer\rsrc_layout_designer_windows_amd64.syso del cmd\yime-layout-designer\rsrc_layout_designer_windows_amd64.syso
    popd
    exit /b 1
)
if exist cmd\yime-layout-designer\rsrc_layout_designer_windows_amd64.syso del cmd\yime-layout-designer\rsrc_layout_designer_windows_amd64.syso
echo [INFO] Built: "%LAYOUT_DESIGNER_EXE%"

call :sign_go_binaries
if errorlevel 1 (
    popd
    exit /b 1
)

echo.
echo ============================================
echo Step 4: Copy input_methods
echo ============================================
echo.

if not exist "%ROOT_DIR%\input_methods" (
    echo [ERROR] Missing input_methods directory: "%ROOT_DIR%\input_methods"
    popd
    exit /b 1
)

if exist "%PACKAGE_DIR%\input_methods" rmdir /s /q "%PACKAGE_DIR%\input_methods"
mkdir "%PACKAGE_DIR%\input_methods"
for /d %%D in ("%ROOT_DIR%\input_methods\*") do (
    if exist "%%~fD\ime.json" (
        xcopy "%%~fD" "%PACKAGE_DIR%\input_methods\%%~nxD\" /E /I /Y >nul
        if errorlevel 1 (
            echo [ERROR] Failed to copy runtime input method "%%~nxD"
            popd
            exit /b 1
        )
    )
)
if not exist "%PACKAGE_DIR%\input_methods\yime\ime.json" (
    echo [ERROR] Packaged Yime ime.json is missing
    popd
    exit /b 1
)

echo [INFO] input_methods copied

echo.
echo ============================================
echo Step 5: Prepare packaged Rime shared data
echo ============================================
echo.

call :prepare_rime_data
if errorlevel 1 (
    echo [ERROR] Failed to prepare packaged Rime shared data
    popd
    exit /b 1
)

if exist "%PACKAGE_DIR%\input_methods\yime\brise" (
    rmdir /s /q "%PACKAGE_DIR%\input_methods\yime\brise"
    if errorlevel 1 (
        echo [ERROR] Failed to remove packaged yime\brise directory
        popd
        exit /b 1
    )
    echo [INFO] Removed yime\brise from package output
)

for /r "%PACKAGE_DIR%\input_methods" %%F in (*.go) do (
    if exist "%%~fF" del /q "%%~fF" >nul
    if errorlevel 1 (
        echo [ERROR] Failed to remove packaged Go source file "%%~fF"
        popd
        exit /b 1
    )
)
echo [INFO] Removed packaged Go source files recursively

if exist "%PACKAGE_DIR%\input_methods\yime\rime.dll.bak-32bit" (
    del /q "%PACKAGE_DIR%\input_methods\yime\rime.dll.bak-32bit" >nul
    if errorlevel 1 (
        echo [ERROR] Failed to remove packaged backup DLL
        popd
        exit /b 1
    )
    echo [INFO] Removed packaged backup DLL
)

if exist "%PACKAGE_DIR%\input_methods\yime\icons\icons" (
    rmdir /s /q "%PACKAGE_DIR%\input_methods\yime\icons\icons"
    if errorlevel 1 (
        echo [ERROR] Failed to remove nested icons directory
        popd
        exit /b 1
    )
    echo [INFO] Removed nested icons directory
)

if exist "%RIME_DIR%\rime.dll" (
    copy /Y "%RIME_DIR%\rime.dll" "%PACKAGE_DIR%\input_methods\yime\rime.dll" >nul
    echo [INFO] Copied rime.dll into package output
)

if exist "%RIME_DIR%\rime_deployer.exe" (
    copy /Y "%RIME_DIR%\rime_deployer.exe" "%PACKAGE_DIR%\input_methods\yime\rime_deployer.exe" >nul
    echo [INFO] Copied rime_deployer.exe into package output
)
if exist "%RIME_DIR%\rime_dict_manager.exe" (
    copy /Y "%RIME_DIR%\rime_dict_manager.exe" "%PACKAGE_DIR%\input_methods\yime\rime_dict_manager.exe" >nul
    echo [INFO] Copied rime_dict_manager.exe into package output
)

echo.
echo ============================================
echo Step 6: Generate backends.json snippet
echo ============================================
echo.

> "%BACKEND_SNIPPET%" echo [
>> "%BACKEND_SNIPPET%" echo   {
>> "%BACKEND_SNIPPET%" echo     "name": "go-backend",
>> "%BACKEND_SNIPPET%" echo     "command": "go-backend\\server.exe",
>> "%BACKEND_SNIPPET%" echo     "workingDir": "go-backend",
>> "%BACKEND_SNIPPET%" echo     "params": ""
>> "%BACKEND_SNIPPET%" echo   }
>> "%BACKEND_SNIPPET%" echo ]

echo [INFO] Generated: "%BACKEND_SNIPPET%"
popd

echo.
echo ============================================
echo Build completed
echo ============================================
echo.
echo Output directory:
echo   "%PACKAGE_DIR%"
echo.
echo Install target:
echo   C:\Program Files (x86)\YIME\go-backend
echo.
echo Notes:
echo 1. backends.json in this repo uses a top-level array.
echo 2. Ensure C:\Program Files (x86)\YIME\backends.json includes go-backend.
echo 3. Ensure C:\Program Files (x86)\YIME\go-backend\input_methods\*\ime.json exists.
echo 4. Re-register both PIMETextService.dll files after copying.
echo 5. Ensure C:\Program Files (x86)\YIME\go-backend\input_methods\yime contains rime.dll.
echo 6. Start or restart PIMELauncher.exe after install.
echo.
exit /b 0

:prepare_rime_data
if exist "%PACKAGE_RIME_DATA_DIR%" (
    rmdir /s /q "%PACKAGE_RIME_DATA_DIR%" 2>nul
    if exist "%PACKAGE_RIME_DATA_DIR%" (
        echo [WARN] Could not remove existing data directory, clearing contents instead.
        del /q "%PACKAGE_RIME_DATA_DIR%\*" 2>nul
        for /d %%d in ("%PACKAGE_RIME_DATA_DIR%\*") do (
            rmdir /s /q "%%d" 2>nul
        )
    )
)
if not exist "%PACKAGE_RIME_DATA_DIR%" mkdir "%PACKAGE_RIME_DATA_DIR%"
if not exist "%PACKAGE_RIME_DATA_DIR%" (
    echo [ERROR] Failed to create packaged Rime data directory: "%PACKAGE_RIME_DATA_DIR%"
    exit /b 1
)

echo [INFO] Copying pinned bundled Rime shared data ...
xcopy "%RIME_DATA_DIR%" "%PACKAGE_RIME_DATA_DIR%\" /E /I /Y >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy bundled Rime data from "%RIME_DATA_DIR%"
    exit /b 1
)

for %%F in (default.yaml symbols.yaml essay.txt luna_pinyin.dict.yaml luna_pinyin.schema.yaml cangjie5.dict.yaml cangjie5.schema.yaml) do (
    if not exist "%PACKAGE_RIME_DATA_DIR%\%%F" (
        echo [ERROR] Packaged Rime shared data is incomplete: %%F
        exit /b 1
    )
)
for %%F in (t2s.json s2t.json TSCharacters.ocd2 STCharacters.ocd2) do (
    if not exist "%PACKAGE_RIME_DATA_DIR%\opencc\%%F" (
        echo [ERROR] Packaged OpenCC data is incomplete: opencc\%%F
        exit /b 1
    )
)

echo [INFO] Packaged Rime shared data prepared at "%PACKAGE_RIME_DATA_DIR%"
exit /b 0

:sign_go_binaries
if not defined YIME_SIGN_CERT_SHA1 (
    echo [WARN] Go executables are unsigned. Smart App Control may block new or unknown builds.
    echo [WARN] Set YIME_SIGN_CERT_SHA1 to a trusted RSA code-signing certificate thumbprint for release builds.
    exit /b 0
)

if not defined YIME_SIGNTOOL_EXE (
    for /f "delims=" %%S in ('where signtool.exe 2^>nul') do if not defined YIME_SIGNTOOL_EXE set "YIME_SIGNTOOL_EXE=%%S"
)
if not defined YIME_SIGNTOOL_EXE (
    echo [ERROR] YIME_SIGN_CERT_SHA1 is set, but signtool.exe was not found. Set YIME_SIGNTOOL_EXE explicitly.
    exit /b 1
)
if not defined YIME_TIMESTAMP_URL set "YIME_TIMESTAMP_URL=http://timestamp.digicert.com"

for %%F in (
    "%SERVER_EXE%"
    "%REVERSE_LOOKUP_EXE%"
    "%TOOL_HUB_EXE%"
    "%LEXICON_MANAGER_EXE%"
    "%SYSTEM_LEXICON_AUDIT_EXE%"
    "%BLOCKLIST_MANAGER_EXE%"
    "%SETTINGS_TOOL_EXE%"
    "%DIAGNOSTICS_TOOL_EXE%"
    "%LAYOUT_DESIGNER_EXE%"
) do (
    echo [INFO] Signing %%~nxF ...
    "%YIME_SIGNTOOL_EXE%" sign /sha1 "%YIME_SIGN_CERT_SHA1%" /fd SHA256 /tr "%YIME_TIMESTAMP_URL%" /td SHA256 "%%~fF"
    if errorlevel 1 (
        echo [ERROR] Failed to sign %%~fF
        exit /b 1
    )
)
exit /b 0
