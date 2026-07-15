;
;	Copyright (C) 2013 - 2016 Hong Jen Yee (PCMan) <pcman.tw@gmail.com>
;	Modifications Copyright (C) 2026 Yime contributors
;
;	This library is free software; you can redistribute it and/or
;	modify it under the terms of the GNU Library General Public
;	License as published by the Free Software Foundation; either
;	version 2 of the License, or (at your option) any later version.
;
;	This library is distributed in the hope that it will be useful,
;	but WITHOUT ANY WARRANTY; without even the implied warranty of
;	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;	Library General Public License for more details.
;
;	You should have received a copy of the GNU Library General Public
;	License along with this library; if not, write to the
;	Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
;	Boston, MA  02110-1301, USA.
;

!include "MUI2.nsh" ; modern UI
!include "x64.nsh" ; NSIS plugin used to detect 64 bit Windows
!include "Winver.nsh" ; Windows version detection
!include "LogicLib.nsh" ; for ${If}, ${Switch} commands

; We need the MD5 plugin
!addplugindir /x86-unicode "md5dll\UNICODE"

; We need the INetC (internet client) plugin
; https://nsis.sourceforge.io/Inetc_plug-in
!addplugindir /x86-unicode "inetc\Plugins\x86-unicode"

Unicode true ; turn on Unicode (This requires NSIS 3.0)
SetCompressor /SOLID lzma ; use LZMA for best compression ratio
SetCompressorDictSize 16 ; larger dictionary size for better compression ratio
AllowSkipFiles off ; cannot skip a file

; icons of the generated installer and uninstaller
!define MUI_ICON "${NSISDIR}\Contrib\Graphics\Icons\orange-install.ico"
!define MUI_UNICON "${NSISDIR}\Contrib\Graphics\Icons\orange-uninstall.ico"

!define /file PRODUCT_VERSION "..\version.txt"

!if /FileExists "..\build_arm64\PIMETextService\Release\PIMETextService.dll"
!define HAVE_ARM64_PIMETS
!endif

!define PRODUCT_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\YIME"
!define LEGACY_PRODUCT_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\PIME"
!define PRODUCT_INSTALL_KEY "Software\YIME"
!define LEGACY_PRODUCT_INSTALL_KEY "Software\PIME"
!define HOMEPAGE_URL "https://github.com/tsaanghwang/Yime"
!define YIME_TIP "0x0804:{35F67E9D-A54D-4177-9697-8B0AB71A9E04}{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}"

Name "$(PRODUCT_NAME)"
BrandingText "$(PRODUCT_NAME)"

OutFile "YIME-${PRODUCT_VERSION}-setup.exe" ; The generated installer file name
!finalize 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "..\tools\sign-file.ps1" -Path "%1"' = 0
!uninstfinalize 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "..\tools\sign-file.ps1" -Path "%1"' = 0

; We install everything to C:\Program Files (x86)
InstallDir "$PROGRAMFILES32\YIME"

;Request application privileges (need administrator to install)
RequestExecutionLevel admin
!define MUI_ABORTWARNING

;Pages
; license page
!insertmacro MUI_PAGE_LICENSE "..\LGPL-2.0.txt" ; for PIME

; installation progress page
!insertmacro MUI_PAGE_INSTFILES

; finish page
!define MUI_FINISHPAGE_LINK_LOCATION "${HOMEPAGE_URL}"
!define MUI_FINISHPAGE_LINK "$(PRODUCT_PAGE) ${MUI_FINISHPAGE_LINK_LOCATION}"
!insertmacro MUI_PAGE_FINISH

; uninstallation pages
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
;--------------------------------

!macro LANG_LOAD LANGLOAD
  !insertmacro MUI_LANGUAGE "${LANGLOAD}"
  !include "locale\${LANGLOAD}.nsh"
  !undef LANG
!macroend

!macro LANG_STRING NAME VALUE
  LangString "${NAME}" "${LANG_${LANG}}" "${VALUE}"
!macroend

!macro LANG_UNSTRING NAME VALUE
  !insertmacro LANG_STRING "un.${NAME}" "${VALUE}"
!macroend

!insertmacro LANG_LOAD "TradChinese" ; Traditional Chinese
!insertmacro LANG_LOAD "SimpChinese" ; Simplified Chinese
!insertmacro LANG_LOAD "English" ; English

var UPDATEX86DLL
var UPDATEX64DLL
var UPDATEARM64DLL

; Stop the installed host before writing payload files. This must run even when
; an interrupted or developer installation has no usable Uninstall.exe.
Function stopRunningBackend
	${If} ${FileExists} "$INSTDIR\PIMELauncher.exe"
		ExecWait '"$INSTDIR\PIMELauncher.exe" /quit'
		Sleep 1500
	${EndIf}
	; A stale launcher can retain both itself and the child Go server. The image
	; name is product-specific, and /T closes that child process as well.
	nsExec::ExecToLog '"$SYSDIR\taskkill.exe" /F /T /IM PIMELauncher.exe'
	Sleep 500
FunctionEnd

Function enableYimeProfile
	; Add the registered TSF profile to the current user's language list.
	; Zero flags enable the TIP without replacing the user's existing layouts.
	System::Call 'input.dll::InstallLayoutOrTip(w "${YIME_TIP}", i 0) i .r0'
	DetailPrint "InstallLayoutOrTip enable result: $0"
FunctionEnd

Function un.disableYimeProfile
	; ILOT_UNINSTALL (0x1) removes only this TIP from the user language list.
	System::Call 'input.dll::InstallLayoutOrTip(w "${YIME_TIP}", i 1) i .r0'
	DetailPrint "InstallLayoutOrTip disable result: $0"
FunctionEnd

; Uninstall old versions
Function uninstallOldVersion
	ClearErrors
	;  run uninstaller
	ReadRegStr $R0 HKLM "${PRODUCT_UNINST_KEY}" "UninstallString"
	${If} $R0 == ""
		ReadRegStr $R0 HKLM "${LEGACY_PRODUCT_UNINST_KEY}" "UninstallString"
	${EndIf}
	${If} $R0 != ""
		ClearErrors
		; Read into a temporary register so a stale uninstall entry cannot
		; erase the InstallDir default when the install-location key is gone.
		ReadRegStr $R1 HKLM "${PRODUCT_INSTALL_KEY}" ""
		${If} $R1 == ""
			ReadRegStr $R1 HKLM "${LEGACY_PRODUCT_INSTALL_KEY}" ""
		${EndIf}
		${If} $R1 != ""
			StrCpy $INSTDIR $R1
		${EndIf}
		${If} ${FileExists} "$INSTDIR\Uninstall.exe"
			MessageBox MB_OKCANCEL|MB_ICONQUESTION $(UNINSTALL_OLD) /SD IDOK IDOK +2
			Abort ; this is skipped if the user select OK

			; Remove the launcher from auto-start
			DeleteRegKey HKLM "${PRODUCT_UNINST_KEY}"
			DeleteRegKey HKLM "${LEGACY_PRODUCT_UNINST_KEY}"
			DeleteRegValue HKLM "Software\Microsoft\Windows\CurrentVersion\Run" "PIMELauncher"
			DeleteRegKey HKLM "${PRODUCT_INSTALL_KEY}"
			DeleteRegKey HKLM "${LEGACY_PRODUCT_INSTALL_KEY}"

			; Unregister COM objects (NSIS UnRegDLL command is broken and cannot be used)
			ExecWait '"$SYSDIR\regsvr32.exe" /u /s "$INSTDIR\x86\PIMETextService.dll"'
			; Verify the MD5/SHA1 checksum of 32-bit PIMETextService.dll
			StrCpy $0 "$INSTDIR\x86\PIMETextService.dll"
			md5dll::GetMD5File "$0"
			Pop $1
			StrCpy $2 "$PLUGINSDIR\PIMETextService_x86.dll"
			md5dll::GetMD5File "$2"
			Pop $3
			${If} $1 == $3
				StrCpy $UPDATEX86DLL "False"
			${Else}
				RMDir /REBOOTOK /r "$INSTDIR\x86"
			${EndIf}

			${If} ${RunningX64}
				SetRegView 64 ; disable registry redirection and use 64 bit Windows registry directly
				ExecWait '"$SYSDIR\regsvr32.exe" /u /s "$INSTDIR\x64\PIMETextService.dll"'
				; Verify the MD5/SHA1 checksum of 64-bit PIMETextService.dll
				StrCpy $0 "$INSTDIR\x64\PIMETextService.dll"
				md5dll::GetMD5File "$0"
				Pop $1
				StrCpy $2 "$PLUGINSDIR\PIMETextService_x64.dll"
				md5dll::GetMD5File "$2"
				Pop $3
				${If} $1 == $3
					StrCpy $UPDATEX64DLL "False"
				${Else}
					RMDir /REBOOTOK /r "$INSTDIR\x64"
				${EndIf}
			${EndIf}

			; Handle ARM64 version of PIMETextService.dll
!ifdef HAVE_ARM64_PIMETS
			${If} ${IsNativeARM64}
				SetRegView 64 ; For ARM64, use native 64-bit registry view
				ExecWait '"$SYSDIR\regsvr32.exe" /u /s "$INSTDIR\arm64\PIMETextService.dll"'
				; Verify MD5 checksum to determine if update is needed
				StrCpy $0 "$INSTDIR\arm64\PIMETextService.dll"
				md5dll::GetMD5File "$0"
				Pop $1
				StrCpy $2 "$PLUGINSDIR\PIMETextService_arm64.dll"
				md5dll::GetMD5File "$2"
				Pop $3
				${If} $1 == $3
					StrCpy $UPDATEARM64DLL "False"
				${Else}
					RMDir /REBOOTOK /r "$INSTDIR\arm64"
				${EndIf}
			${EndIf}
!endif

			; Try to terminate running PIMELauncher and the server process
			; Otherwise we cannot replace it.
			ExecWait '"$INSTDIR\PIMELauncher.exe" /quit'
			Sleep 1000
			Delete /REBOOTOK "$INSTDIR\PIMELauncher.exe"

            Delete "$INSTDIR\backends.json"
			RMDir /REBOOTOK /r "$INSTDIR\python"
			RMDir /REBOOTOK /r "$INSTDIR\node"

			; Only exist in earlier versions, but need to delete it.
			RMDir /REBOOTOK /r "$INSTDIR\server"

			; Delete shortcuts in Start Menu
			RMDir /r "$SMPROGRAMS\$(PRODUCT_NAME)"

			Delete "$INSTDIR\version.txt"
			Delete "$INSTDIR\Uninstall.exe"
			RMDir /REBOOTOK "$INSTDIR"

			${If} ${RebootFlag}
				MessageBox MB_YESNO "$(MB_REBOOT_REQUIRED)" /SD IDNO IDNO +3
				Reboot
				Quit
				Abort
			${EndIf}
		${EndIf}
	${EndIf}

	ClearErrors
	; Ensure that old files are all deleted
	${If} ${RunningX64}
		${If} ${FileExists} "$INSTDIR\x64\PIMETextService.dll"
			; Verify the MD5/SHA1 checksum of 64-bit PIMETextService.dll
			StrCpy $0 "$INSTDIR\x64\PIMETextService.dll"
			md5dll::GetMD5File "$0"
			Pop $1
			StrCpy $2 "$PLUGINSDIR\PIMETextService_x64.dll"
			md5dll::GetMD5File "$2"
			Pop $3
			${If} $1 == $3
				StrCpy $UPDATEX64DLL "False"
			${Else}
				Delete /REBOOTOK "$INSTDIR\x64\PIMETextService.dll"
				IfErrors 0 +2
					Call .onInstFailed
			${EndIf}
		${EndIf}
	${EndIf}

!ifdef HAVE_ARM64_PIMETS
	${If} ${IsNativeARM64}
		${If} ${FileExists} "$INSTDIR\arm64\PIMETextService.dll"
			; Verify the MD5 checksum of ARM64 PIMETextService.dll
			StrCpy $0 "$INSTDIR\arm64\PIMETextService.dll"
			md5dll::GetMD5File "$0"
			Pop $1
			StrCpy $2 "$PLUGINSDIR\PIMETextService_arm64.dll"
			md5dll::GetMD5File "$2"
			Pop $3
			${If} $1 == $3
				StrCpy $UPDATEARM64DLL "False"
			${Else}
				Delete /REBOOTOK "$INSTDIR\arm64\PIMETextService.dll"
				IfErrors 0 +2
					Call .onInstFailed
			${EndIf}
		${EndIf}
	${EndIf}
!else
	StrCpy $UPDATEARM64DLL "False"
!endif

	${If} ${FileExists} "$INSTDIR\x86\PIMETextService.dll"
		; Verify the MD5/SHA1 checksum of 32-bit PIMETextService.dll
		StrCpy $0 "$INSTDIR\x86\PIMETextService.dll"
		md5dll::GetMD5File "$0"
		Pop $1
		StrCpy $2 "$PLUGINSDIR\PIMETextService_x86.dll"
		md5dll::GetMD5File "$2"
		Pop $3
		${If} $1 == $3
			StrCpy $UPDATEX86DLL "False"
		${Else}
			Delete /REBOOTOK "$INSTDIR\x86\PIMETextService.dll"
			IfErrors 0 +2
				Call .onInstFailed
		${EndIf}
	${EndIf}

	${If} ${RebootFlag}
		Call .onInstFailed
	${EndIf}
FunctionEnd

; Called during installer initialization
Function .onInit
	;Language selection dialog

	${IfNot} ${Silent}
		Push ""
		Push ${LANG_TRADCHINESE}
		Push "繁體中文"
		Push ${LANG_SIMPCHINESE}
		Push "简体中文"
		Push ${LANG_ENGLISH}
		Push "English"
		Push A ; A means auto count languages
			   ; for the auto count to work the first empty push (Push "") must remain
		LangDLL::LangDialog $(INSTALLER_LANGUAGE_TITLE) $(INSTALL_LANGUAGE_MESSAGE)

		Pop $LANGUAGE
		StrCmp $LANGUAGE "cancel" 0 +2
			Abort
	${EndIf}

	; Currently, we're not able to support Windows xp since it has an incomplete TSF.
	${IfNot} ${AtLeastWinVista}
		MessageBox MB_ICONSTOP|MB_OK $(AtLeastWinVista_MESSAGE)
		Quit
	${EndIf}

	${If} ${RunningX64}
		SetRegView 64 ; disable registry redirection and use 64 bit Windows registry directly
	${EndIf}

	${If} ${IsNativeARM64}
		SetRegView 64 ; disable registry redirection for ARM64 (also uses 64-bit view)
	${EndIf}

	File "/oname=$PLUGINSDIR\PIMETextService_x86.dll" "..\build\PIMETextService\Release\PIMETextService.dll"
	File "/oname=$PLUGINSDIR\PIMETextService_x64.dll" "..\build64\PIMETextService\Release\PIMETextService.dll"
	!ifdef HAVE_ARM64_PIMETS
	File "/oname=$PLUGINSDIR\PIMETextService_arm64.dll" "..\build_arm64\PIMETextService\Release\PIMETextService.dll"
	!endif

	StrCpy $UPDATEX86DLL "True"
	StrCpy $UPDATEX64DLL "True"
	!ifdef HAVE_ARM64_PIMETS
	StrCpy $UPDATEARM64DLL "True"
	!else
	StrCpy $UPDATEARM64DLL "False"
	!endif

	; check if old version is installed and uninstall it first
	Call uninstallOldVersion
	${If} $INSTDIR == ""
		StrCpy $INSTDIR "$PROGRAMFILES32\YIME"
	${EndIf}
	Call stopRunningBackend
FunctionEnd

; called to show an error message when errors happen
Function .onInstFailed
	${If} ${RebootFlag}
		MessageBox MB_YESNO $(REBOOT_QUESTION) IDNO +3
		Reboot
		Quit
		Abort
	${Else}
		MessageBox MB_ICONSTOP|MB_OK $(INST_FAILED_MESSAGE)
		Abort
	${EndIf}
FunctionEnd

Function ensureVCRedist
	; Check if we have latest VC++ Redistributable
	; Reference: https://blogs.msdn.microsoft.com/vcblog/2015/03/03/introducing-the-universal-crt/
	;            https://docs.python.org/3/using/windows.html#embedded-distribution
	${IfNot} ${FileExists} "$SYSDIR\ucrtbase.dll"
	${OrIfNot} ${FileExists} "$SYSDIR\msvcp140.dll"
		${If} ${RunningX64}
			; In 64-bit environment, we need to check both x86 and x64 version of dlls,
			; because we only need at least one of the x86 or x64 version is available,
			; which means we need to check both these 2 directory:
			;   1. C:\Windows\System32 (x64 64-bit version dlls are in here)
			;   2. C:\Windows\SysWOW64 (x86 32-bit version dlls are in here) (already checked)

			; Because X64 FS Redirection is enabled by default ($SYSDIR is pointed to C:\Windows\SysWOW64),
			; now we just need to disable X64 FS Redirection (let $SYSDIR point to C:\Windows\System32)
			; in order to check if we have x64 64-bit version of Universal CRT
			${DisableX64FSRedirection}
			${IfNot} ${FileExists} "$SYSDIR\ucrtbase.dll"
			${OrIfNot} ${FileExists} "$SYSDIR\msvcp140.dll"
				MessageBox MB_YESNO|MB_ICONQUESTION $(DOWNLOAD_VCREDIST_QUESTION) IDYES +2
					Abort ; this is skipped if the user select Yes
				; Download latest VC++ Redistributable (x64 version)
				inetc::get "https://aka.ms/vs/17/release/vc_redist.x64.exe" "$TEMP\vc_redist.x64.exe"
				Pop $R0 ; Get the return value
				${If} $R0 != "OK"
					MessageBox MB_ICONSTOP|MB_OK $(DOWNLOAD_VCREDIST_FAILED_MESSAGE)
					Abort
				${EndIf}

				; Run vcredist installer
				ExecWait "$TEMP\vc_redist.x64.exe" $0

				; Check again if we have latest VC++ Redistributable
				${IfNot} ${FileExists} "$SYSDIR\ucrtbase.dll"
				${OrIfNot} ${FileExists} "$SYSDIR\msvcp140.dll"
					MessageBox MB_ICONSTOP|MB_OK $(INST_VCREDIST_FAILED_MESSAGE)
					ExecShell "open" "https://support.microsoft.com/en-us/kb/2999226"
					Abort
				${EndIf}
			${EndIf}

			; Change X64 FS Redirection back to default state
			${EnableX64FSRedirection}

		${ElseIf} ${IsNativeARM64}
			${DisableX64FSRedirection}
			${IfNot} ${FileExists} "$SYSDIR\ucrtbase.dll"
			${OrIfNot} ${FileExists} "$SYSDIR\msvcp140.dll"
				MessageBox MB_YESNO|MB_ICONQUESTION $(DOWNLOAD_VCREDIST_QUESTION) IDYES +2
					Abort
				inetc::get "https://aka.ms/vs/17/release/vc_redist.arm64.exe" "$TEMP\vc_redist.arm64.exe"
				Pop $R0
				${If} $R0 != "OK"
					MessageBox MB_ICONSTOP|MB_OK $(DOWNLOAD_VCREDIST_FAILED_MESSAGE)
					Abort
				${EndIf}
				ExecWait "$TEMP\vc_redist.arm64.exe" $0
				${IfNot} ${FileExists} "$SYSDIR\ucrtbase.dll"
				${OrIfNot} ${FileExists} "$SYSDIR\msvcp140.dll"
					MessageBox MB_ICONSTOP|MB_OK $(INST_VCREDIST_FAILED_MESSAGE)
					ExecShell "open" "https://support.microsoft.com/en-us/kb/2999226"
					Abort
				${EndIf}
			${EndIf}
			${EnableX64FSRedirection}

		${Else}
			MessageBox MB_YESNO|MB_ICONQUESTION $(DOWNLOAD_VCREDIST_QUESTION) IDYES +2
				Abort ; this is skipped if the user select Yes
			; Download latest VC++ Redistributable (x86 version)
			inetc::get "https://aka.ms/vs/17/release/vc_redist.x86.exe" "$TEMP\vc_redist.x86.exe"
			Pop $R0 ; Get the return value
			${If} $R0 != "OK"
				MessageBox MB_ICONSTOP|MB_OK $(DOWNLOAD_VCREDIST_FAILED_MESSAGE)
				Abort
			${EndIf}

			; Run vcredist installer
			ExecWait "$TEMP\vc_redist.x86.exe" $0

			; Check again if we have latest VC++ Redistributable
			${IfNot} ${FileExists} "$SYSDIR\ucrtbase.dll"
			${OrIfNot} ${FileExists} "$SYSDIR\msvcp140.dll"
				MessageBox MB_ICONSTOP|MB_OK $(INST_VCREDIST_FAILED_MESSAGE)
				ExecShell "open" "https://support.microsoft.com/en-us/kb/2999226"
				Abort
			${EndIf}
		${EndIf}
	${EndIf}
FunctionEnd

;Installer Type
InstType "$(INST_TYPE_STD)"

;Installer Sections
Section $(SECTION_MAIN) SecMain
	SectionIn 1 RO
	; Ensure that the native launcher and TSF components have the VC++ runtime.
	Call ensureVCRedist

	; TODO: may be we can automatically rebuild the dlls here.
	; http://stackoverflow.com/questions/24580/how-do-you-automate-a-visual-studio-build
	; For example, we can build the Visual Studio solution with the following command line.
	; C:\Program Files (x86)\Microsoft Visual Studio 12.0\Common7\IDE\devenv.com "..\build\PIME.sln" /build Release

	SetOverwrite on ; overwrite existing files
	SetOutPath "$INSTDIR"

    ; Install version info
    File "..\version.txt"

    ; Install backend informations
    File "..\backends.json"

	; Ship the notices and complete license texts with every installed copy.
	SetOutPath "$INSTDIR\licenses"
	File "..\LICENSE.txt"
	File "..\NOTICE.md"
	File "..\AUTHORS.txt"
	File "..\THIRD_PARTY_NOTICES.md"
	File "..\LGPL-2.0.txt"
	File "..\APACHE-2.0.txt"
	File /oname=NLOHMANN-JSON-MIT.txt "..\json\LICENSE.MIT"
	File "..\LICENSES\PIME-UPSTREAM-LICENSE.txt"
	File "..\LICENSES\RIME-BSD-3-Clause.txt"
	File "..\LICENSES\RIME-FROST-GPL-3.0.txt"
	File "..\LICENSES\SIL-OFL-1.1.txt"
	File "..\LICENSES\UNICODE-3.0.txt"
	File "..\LICENSES\RUST-DEPENDENCIES.md"
	SetOutPath "$INSTDIR"

	; Install the launcher responsible to launch the backends
	File "..\build\PIMELauncher\PIMELauncher.exe"

	; Yime is the standard product payload. Keep it in the required main
	; section so a default install always contains the configured backend.
	; These retired Go demo backends were shipped as empty directories by old
	; development packages. Non-recursive RMDir removes only empty leftovers
	; and preserves the directory if a user placed any files there.
	RMDir "$INSTDIR\go-backend\input_methods\fcitx5"
	RMDir "$INSTDIR\go-backend\input_methods\meow"
	RMDir "$INSTDIR\go-backend\input_methods\simple_pinyin"
	SetOutPath "$INSTDIR\go-backend"
	File /r "..\go-backend\build\go-backend\*.*"

	; PUA candidate annotations require the YinYuan glyph font. Keep an
	; existing system copy intact, but register the bundled copy when absent.
	SetOutPath "$FONTS"
	SetOverwrite off
	File /oname=YinYuan-Regular.ttf "..\go-backend\input_methods\yime\data\fonts\YinYuan-Regular.ttf"
	SetOverwrite on
	WriteRegStr HKLM "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" "YinYuan Regular (TrueType)" "YinYuan-Regular.ttf"
	System::Call 'gdi32::AddFontResource(t "$FONTS\YinYuan-Regular.ttf") i .r0'
	SendMessage 0xffff 0x001D 0 0
SectionEnd

Section "" Register
	SectionIn 1

	; Install the text service dlls
	${If} ${RunningX64} ; This is a 64-bit Windows system
		SetOutPath "$INSTDIR\x64"
		${If} $UPDATEX64DLL == "True"
			File "..\build64\PIMETextService\Release\PIMETextService.dll" ; put 64-bit PIMETextService.dll in x64 folder
		${EndIf}
		; Register COM objects (NSIS RegDLL command is broken and cannot be used)
		ExecWait '"$SYSDIR\regsvr32.exe" /s "$INSTDIR\x64\PIMETextService.dll"'
	${EndIf}

	!ifdef HAVE_ARM64_PIMETS
	${If} ${IsNativeARM64} ; This is a native ARM64 Windows system
		SetOutPath "$INSTDIR\arm64"
		${If} $UPDATEARM64DLL == "True"
			File "..\build_arm64\PIMETextService\Release\PIMETextService.dll" ; put ARM64 PIMETextService.dll in arm64 folder
		${EndIf}
		; Register COM objects (NSIS RegDLL command is broken and cannot be used)
		ExecWait '"$SYSDIR\regsvr32.exe" /s "$INSTDIR\arm64\PIMETextService.dll"'
	${EndIf}
	!endif

	SetOutPath "$INSTDIR\x86"
	${If} $UPDATEX86DLL == "True"
		File "..\build\PIMETextService\Release\PIMETextService.dll" ; put 32-bit PIMETextService.dll in x86 folder
	${EndIf}
	; Register COM objects (NSIS RegDLL command is broken and cannot be used)
	ExecWait '"$SYSDIR\regsvr32.exe" /s "$INSTDIR\x86\PIMETextService.dll"'
	Call enableYimeProfile

	; Launch the active Go backend through PIMELauncher on startup.
	WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Run" "PIMELauncher" "$INSTDIR\PIMELauncher.exe"

	;Store installation folder in the registry
	WriteRegStr HKLM "${PRODUCT_INSTALL_KEY}" "" $INSTDIR
	;Write an entry to Add & Remove applications
	WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayName" $(PRODUCT_NAME)
	WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
	WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "Publisher" $(PRODUCT_PUBLISHER)
	; WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayIcon" "$INSTDIR\x86\PIMETextService.dll"
	WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
	WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "URLInfoAbout" "${HOMEPAGE_URL}"
	WriteUninstaller "$INSTDIR\Uninstall.exe" ;Create uninstaller

	CreateShortCut "$SMPROGRAMS\$(PRODUCT_NAME)\$(UNINSTALL_PIME).lnk" "$INSTDIR\Uninstall.exe"
SectionEnd

;Uninstaller Section
Section "Uninstall"
	${If} ${RunningX64}
		SetRegView 64 ; disable registry redirection and use 64 bit Windows registry directly
	${EndIf}

	${If} ${IsNativeARM64}
		SetRegView 64 ; disable registry redirection on ARM64 systems
	${EndIf}

	; Remove the launcher from auto-start
	DeleteRegKey HKLM "${PRODUCT_UNINST_KEY}"
	DeleteRegKey HKLM "${LEGACY_PRODUCT_UNINST_KEY}"
	DeleteRegValue HKLM "Software\Microsoft\Windows\CurrentVersion\Run" "PIMELauncher"
	DeleteRegKey HKLM "${PRODUCT_INSTALL_KEY}"
	DeleteRegKey HKLM "${LEGACY_PRODUCT_INSTALL_KEY}"
	Call un.disableYimeProfile

	; Unregister COM objects (NSIS UnRegDLL command is broken and cannot be used)
	ExecWait '"$SYSDIR\regsvr32.exe" /u /s "$INSTDIR\x86\PIMETextService.dll"'
	${If} ${RunningX64}
		ExecWait '"$SYSDIR\regsvr32.exe" /u /s "$INSTDIR\x64\PIMETextService.dll"'
		RMDir /REBOOTOK /r "$INSTDIR\x64"
	${EndIf}

	!ifdef HAVE_ARM64_PIMETS
	${If} ${IsNativeARM64}
		ExecWait '"$SYSDIR\regsvr32.exe" /u /s "$INSTDIR\arm64\PIMETextService.dll"'
		RMDir /REBOOTOK /r "$INSTDIR\arm64"
	${EndIf}
	!endif

	; Try to terminate running PIMELauncher and the server process
	; Otherwise we cannot replace it.
	ExecWait '"$INSTDIR\PIMELauncher.exe" /quit'
	Sleep 1000
	Delete /REBOOTOK "$INSTDIR\PIMELauncher.exe"

	RMDir /REBOOTOK /r "$INSTDIR\x86"
	RMDir /REBOOTOK /r "$INSTDIR\python"
	RMDir /REBOOTOK /r "$INSTDIR\node"
	RMDir /REBOOTOK /r "$INSTDIR\licenses"
    Delete "$INSTDIR\backends.json"

	; Delete shortcuts in Start Menu
	RMDir /r "$SMPROGRAMS\$(PRODUCT_NAME)"

	Delete "$INSTDIR\version.txt"
	Delete "$INSTDIR\Uninstall.exe"
	RMDir /REBOOTOK "$INSTDIR"

	${If} ${RebootFlag}
		MessageBox MB_YESNO "$(MB_REBOOT_REQUIRED)" /SD IDNO IDNO +3
		Reboot
		Quit
		Abort
	${EndIf}
SectionEnd
