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

!include "${NSISDIR}\Include\MUI2.nsh" ; modern UI
!include "${NSISDIR}\Include\x64.nsh" ; NSIS plugin used to detect 64 bit Windows
!include "${NSISDIR}\Include\Winver.nsh" ; Windows version detection
!include "${NSISDIR}\Include\LogicLib.nsh" ; for ${If}, ${Switch} commands
!include "${NSISDIR}\Include\FileFunc.nsh" ; command-line parsing for the same-SID elevation worker

Unicode true ; turn on Unicode (This requires NSIS 3.0)
SetCompressor /SOLID lzma ; use LZMA for best compression ratio
SetCompressorDictSize 16 ; larger dictionary size for better compression ratio
AllowSkipFiles off ; cannot skip a file

; icons of the generated installer and uninstaller
!define MUI_ICON "${NSISDIR}\Contrib\Graphics\Icons\orange-install.ico"
!define MUI_UNICON "${NSISDIR}\Contrib\Graphics\Icons\orange-uninstall.ico"

; Direct makensis invocation is forbidden: the build wrapper validates one
; sealed package plan and derives these definitions from it. The digest is also
; embedded in installer/uninstaller VERSIONINFO. The current receipt only
; verifies that the digest bytes occur in the output; named VERSIONINFO parsing
; remains a separate gate.
!ifndef PACKAGE_PLAN_SHA256
!error "Build through tools/build-rime-pime-installer.ps1 with a sealed package plan."
!endif
!ifndef PACKAGE_PLAN_X86_X64
!error "Only the sealed x86/x64 package-plan profile is currently admitted."
!endif
!ifdef PACKAGE_PLAN_X86_ARM64X
!error "The x86/Arm64X package-plan profile is reserved but not admitted."
!endif
!ifndef PACKAGE_STAGE_ROOT
!error "The sealed Rime/PIME package stage root is required."
!endif
!ifndef PACKAGE_STAGE_MANIFEST_SHA256
!error "The sealed Rime/PIME copied-content manifest digest is required."
!endif
!ifndef PACKAGE_STAGE_CONTENT_SHA256
!error "The sealed Rime/PIME copied-content tree digest is required."
!endif
!ifndef PACKAGE_PAYLOAD_NSH_PATH
!error "The deterministic Rime/PIME payload include is required."
!endif
!ifndef PACKAGE_PAYLOAD_NSH_SHA256
!error "The deterministic Rime/PIME payload include digest is required."
!endif
!ifndef PACKAGE_OUTPUT_PATH
!error "The build wrapper must provide a fresh candidate installer output path."
!endif
!ifndef PACKAGE_LOCALE_ROOT
!error "The build wrapper must provide the absolute sealed locale source root."
!endif
!ifndef PACKAGE_UNSIGNED_DISABLED_BUILD
!ifndef PACKAGE_SIGN_FILE_PATH
!error "A release-capable build must provide the absolute leased signing-hook path."
!endif
!ifndef PACKAGE_POWERSHELL_PATH
!error "A release-capable build must provide the absolute leased PowerShell signing host."
!endif
!endif

!include "${PACKAGE_PAYLOAD_NSH_PATH}"
!define /file PRODUCT_VERSION "${PACKAGE_STAGE_ROOT}\payload\version.txt"

!define PRODUCT_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\YIME"
!define LEGACY_PRODUCT_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\PIME"
!define PRODUCT_INSTALL_KEY "Software\YIME"
!define LEGACY_PRODUCT_INSTALL_KEY "Software\PIME"
!define HOMEPAGE_URL "https://github.com/tsaanghwang/Yime"
!define YIME_TIP "0x0804:{35F67E9D-A54D-4177-9697-8B0AB71A9E04}{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}"


Name "$(PRODUCT_NAME)"
BrandingText "$(PRODUCT_NAME)"

OutFile "${PACKAGE_OUTPUT_PATH}" ; Fresh candidate; the wrapper publishes only after post-verification.
; VIProductVersion is the numeric fixed-file version shared by the installer
; and generated uninstaller. Keep it synchronized with version.txt; the build
; guard rejects drift. String fields below are likewise embedded in both files.
VIProductVersion "1.4.0.0"
!ifndef PACKAGE_UNSIGNED_DISABLED_BUILD
!finalize '"${PACKAGE_POWERSHELL_PATH}" -NoProfile -ExecutionPolicy Bypass -File "${PACKAGE_SIGN_FILE_PATH}" -Path "%1"' = 0
!uninstfinalize '"${PACKAGE_POWERSHELL_PATH}" -NoProfile -ExecutionPolicy Bypass -File "${PACKAGE_SIGN_FILE_PATH}" -Path "%1"' = 0
!endif

; We install everything to C:\Program Files (x86)
InstallDir "$PROGRAMFILES32\YIME"

; Start as the invoking user, capture that SID, then relaunch this same signed
; package as an elevated worker. A credentials-over-the-shoulder elevation is
; rejected before any install/uninstall/profile mutation because its SID differs.
RequestExecutionLevel user
ManifestSupportedOS all
!define MUI_ABORTWARNING

;Pages
; license page
!insertmacro MUI_PAGE_LICENSE "${PACKAGE_STAGE_ROOT}\payload\licenses\LGPL-2.0.txt" ; for PIME

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
  !include "${PACKAGE_LOCALE_ROOT}\${LANGLOAD}.nsh"
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

!macro VERSION_INFO LANG_ID PRODUCT_NAME_VALUE FILE_DESCRIPTION_VALUE
	VIAddVersionKey /LANG=${LANG_ID} "FileVersion" "${PRODUCT_VERSION}"
	VIAddVersionKey /LANG=${LANG_ID} "ProductVersion" "${PRODUCT_VERSION}"
	VIAddVersionKey /LANG=${LANG_ID} "ProductName" "${PRODUCT_NAME_VALUE}"
	VIAddVersionKey /LANG=${LANG_ID} "FileDescription" "${FILE_DESCRIPTION_VALUE}"
	VIAddVersionKey /LANG=${LANG_ID} "CompanyName" "YIME Project"
	VIAddVersionKey /LANG=${LANG_ID} "LegalCopyright" "Copyright (C) 2026 YIME contributors"
	VIAddVersionKey /LANG=${LANG_ID} "PackagePlanSHA256" "${PACKAGE_PLAN_SHA256}"
	VIAddVersionKey /LANG=${LANG_ID} "PackageStageManifestSHA256" "${PACKAGE_STAGE_MANIFEST_SHA256}"
	VIAddVersionKey /LANG=${LANG_ID} "PackageStageContentSHA256" "${PACKAGE_STAGE_CONTENT_SHA256}"
	VIAddVersionKey /LANG=${LANG_ID} "PackagePayloadNshSHA256" "${PACKAGE_PAYLOAD_NSH_SHA256}"
	VIAddVersionKey /LANG=${LANG_ID} "PackageArchitectures" "x86,x64"
!macroend
!insertmacro VERSION_INFO ${LANG_TRADCHINESE} "YIME 輸入法" "YIME 安裝與解除安裝程式"
!insertmacro VERSION_INFO ${LANG_SIMPCHINESE} "YIME 输入法" "YIME 安装与卸载程序"
!insertmacro VERSION_INFO ${LANG_ENGLISH} "YIME Input Method" "YIME Installer and Uninstaller"

var UPDATEX86DLL
var UPDATEX64DLL
var UPDATEARM64DLL
var RimeOwnershipAction
var RimeOwnershipResult
var RimeOwnershipOutput
var RimeOwnershipPowerShell
var RimeOwnershipArchitectures
var registrationExitCode
var RimeNativeRegsvr32
var RimeX86Regsvr32
var RimeNativeArchitecture
var RimeInstallMode
var RimeTargetUserAction
var RimeTargetUserResult
var RimeTargetUserOutput
var RimeTargetUserPowerShell
var InitiatingSid
var TargetUserSid
var RimeTargetUserEnvelope
var RimeTargetUserCorrelation
var RimeTargetUserValidated

; ExecWait leaves its result variable unreliable when process creation itself
; fails. Every registrar/status command therefore starts with a non-success
; sentinel and treats the NSIS error flag independently from the child exit code.
!macro RunCheckedRegistrationCommand COMMAND FAILURE_MESSAGE
	ClearErrors
	StrCpy $registrationExitCode -1
	ExecWait '${COMMAND}' $registrationExitCode
	${If} ${Errors}
		DetailPrint "${FAILURE_MESSAGE}: process launch failed"
		Abort
	${EndIf}
	${If} $registrationExitCode != 0
		DetailPrint "${FAILURE_MESSAGE}: $registrationExitCode"
		Abort
	${EndIf}
!macroend

!macro YimePimeTargetUserHelper PREFIX
Function ${PREFIX}runTargetUserHelper
	InitPluginsDir
	!insertmacro YimePimeStageTargetUserHelpers
	StrCpy $RimeTargetUserPowerShell "$SYSDIR\WindowsPowerShell\v1.0\powershell.exe"
	${If} ${RunningX64}
		StrCpy $RimeTargetUserPowerShell "$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
	${EndIf}
	${If} $RimeTargetUserAction == "CaptureInitiator"
		nsExec::ExecToStack '"$RimeTargetUserPowerShell" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\invoke-rime-pime-target-user.ps1" -Action CaptureInitiator'
	${ElseIf} $RimeTargetUserAction == "CreateEnvelope"
		nsExec::ExecToStack '"$RimeTargetUserPowerShell" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\invoke-rime-pime-target-user.ps1" -Action CreateEnvelope -InitiatingSid "$InitiatingSid" -TargetUserSid "$TargetUserSid" -EnvelopePath "$RimeTargetUserEnvelope"'
	${Else}
		nsExec::ExecToStack '"$RimeTargetUserPowerShell" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\invoke-rime-pime-target-user.ps1" -Action ValidateWorker -InitiatingSid "$InitiatingSid" -TargetUserSid "$TargetUserSid" -EnvelopePath "$RimeTargetUserEnvelope" -CorrelationId "$RimeTargetUserCorrelation"'
	${EndIf}
	Pop $RimeTargetUserResult
	Pop $RimeTargetUserOutput
	${If} $RimeTargetUserResult != "0"
		MessageBox MB_OK|MB_ICONSTOP "Rime/PIME could not preserve one initiating Windows user across elevation. No maintenance action was admitted." /SD IDOK
		Abort
	${EndIf}
FunctionEnd

Function ${PREFIX}acceptTargetUserWorker
	StrCpy $RimeTargetUserAction "ValidateWorker"
	Call ${PREFIX}runTargetUserHelper
	${If} $RimeTargetUserOutput != $TargetUserSid
		MessageBox MB_OK|MB_ICONSTOP "Rime/PIME target-user validation returned an unexpected SID. No maintenance action was admitted." /SD IDOK
		Abort
	${EndIf}
	StrCpy $RimeTargetUserValidated "True"
FunctionEnd

Function ${PREFIX}validateTargetUserWorker
	${If} $RimeTargetUserValidated != "True"
		MessageBox MB_OK|MB_ICONSTOP "Rime/PIME has no validated target-user elevation envelope. No maintenance action was admitted." /SD IDOK
		Abort
	${EndIf}
FunctionEnd
!macroend
!insertmacro YimePimeTargetUserHelper ""
!insertmacro YimePimeTargetUserHelper "un."

Function bootstrapTargetUser
	${GetParameters} $R0
	ClearErrors
	${GetOptions} "$R0" "/YimePimeElevatedWorker=" $R1
	${IfNot} ${Errors}
		ClearErrors
		${GetOptions} "$R0" "/InitiatingSid=" $InitiatingSid
		${If} ${Errors}
			Abort
		${EndIf}
		ClearErrors
		${GetOptions} "$R0" "/TargetUserSid=" $TargetUserSid
		${If} ${Errors}
			Abort
		${EndIf}
		ClearErrors
		${GetOptions} "$R0" "/EnvelopePath=" $RimeTargetUserEnvelope
		${If} ${Errors}
			Abort
		${EndIf}
		ClearErrors
		${GetOptions} "$R0" "/CorrelationId=" $RimeTargetUserCorrelation
		${If} ${Errors}
			Abort
		${EndIf}
		Call acceptTargetUserWorker
		Return
	${EndIf}
	; Reserved worker fields are generated only by this non-elevated bootstrap.
	ClearErrors
	${GetOptions} "$R0" "/InitiatingSid=" $R1
	${IfNot} ${Errors}
		Abort
	${EndIf}
	ClearErrors
	${GetOptions} "$R0" "/TargetUserSid=" $R1
	${IfNot} ${Errors}
		Abort
	${EndIf}
	ClearErrors
	${GetOptions} "$R0" "/EnvelopePath=" $R1
	${IfNot} ${Errors}
		Abort
	${EndIf}
	ClearErrors
	${GetOptions} "$R0" "/CorrelationId=" $R1
	${IfNot} ${Errors}
		Abort
	${EndIf}
	StrCpy $RimeTargetUserAction "CaptureInitiator"
	Call runTargetUserHelper
	StrCpy $InitiatingSid $RimeTargetUserOutput
	StrCpy $TargetUserSid $RimeTargetUserOutput
	StrCpy $RimeTargetUserEnvelope "$PLUGINSDIR\rime-pime-target-user-envelope.json"
	StrCpy $RimeTargetUserAction "CreateEnvelope"
	Call runTargetUserHelper
	StrCpy $RimeTargetUserCorrelation $RimeTargetUserOutput
	StrCpy $R2 "/YimePimeElevatedWorker=1 /InitiatingSid=$InitiatingSid /TargetUserSid=$TargetUserSid /EnvelopePath=$\"$RimeTargetUserEnvelope$\" /CorrelationId=$RimeTargetUserCorrelation $R0"
	ClearErrors
	ExecShellWait "runas" "$EXEPATH" "$R2" SW_SHOWNORMAL $R3
	${If} ${Errors}
		Abort
	${EndIf}
	SetErrorLevel $R3
	Quit
FunctionEnd

Function un.bootstrapTargetUser
	${un.GetParameters} $R0
	ClearErrors
	${un.GetOptions} "$R0" "/YimePimeElevatedWorker=" $R1
	${IfNot} ${Errors}
		ClearErrors
		${un.GetOptions} "$R0" "/InitiatingSid=" $InitiatingSid
		${If} ${Errors}
			Abort
		${EndIf}
		ClearErrors
		${un.GetOptions} "$R0" "/TargetUserSid=" $TargetUserSid
		${If} ${Errors}
			Abort
		${EndIf}
		ClearErrors
		${un.GetOptions} "$R0" "/EnvelopePath=" $RimeTargetUserEnvelope
		${If} ${Errors}
			Abort
		${EndIf}
		ClearErrors
		${un.GetOptions} "$R0" "/CorrelationId=" $RimeTargetUserCorrelation
		${If} ${Errors}
			Abort
		${EndIf}
		Call un.acceptTargetUserWorker
		Return
	${EndIf}
	ClearErrors
	${un.GetOptions} "$R0" "/InitiatingSid=" $R1
	${IfNot} ${Errors}
		Abort
	${EndIf}
	ClearErrors
	${un.GetOptions} "$R0" "/TargetUserSid=" $R1
	${IfNot} ${Errors}
		Abort
	${EndIf}
	ClearErrors
	${un.GetOptions} "$R0" "/EnvelopePath=" $R1
	${IfNot} ${Errors}
		Abort
	${EndIf}
	ClearErrors
	${un.GetOptions} "$R0" "/CorrelationId=" $R1
	${IfNot} ${Errors}
		Abort
	${EndIf}
	StrCpy $RimeTargetUserAction "CaptureInitiator"
	Call un.runTargetUserHelper
	StrCpy $InitiatingSid $RimeTargetUserOutput
	StrCpy $TargetUserSid $RimeTargetUserOutput
	StrCpy $RimeTargetUserEnvelope "$PLUGINSDIR\rime-pime-target-user-envelope.json"
	StrCpy $RimeTargetUserAction "CreateEnvelope"
	Call un.runTargetUserHelper
	StrCpy $RimeTargetUserCorrelation $RimeTargetUserOutput
	StrCpy $R2 "/YimePimeElevatedWorker=1 /InitiatingSid=$InitiatingSid /TargetUserSid=$TargetUserSid /EnvelopePath=$\"$RimeTargetUserEnvelope$\" /CorrelationId=$RimeTargetUserCorrelation $R0"
	ClearErrors
	ExecShellWait "runas" "$EXEPATH" "$R2" SW_SHOWNORMAL $R3
	${If} ${Errors}
		Abort
	${EndIf}
	SetErrorLevel $R3
	Quit
FunctionEnd

; Both installer and uninstaller carry their own helper bytes. No YimeCore or
; repository file is required on the user's machine. These helpers never use
; image-name termination or PIME's shared quit event as ownership evidence.
!macro YimePimeOwnershipGuard PREFIX
Function ${PREFIX}runOwnershipGuard
	InitPluginsDir
	!insertmacro YimePimeStageOwnershipHelpers
	StrCpy $RimeOwnershipPowerShell "$SYSDIR\WindowsPowerShell\v1.0\powershell.exe"
	${If} ${RunningX64}
		StrCpy $RimeOwnershipPowerShell "$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
	${EndIf}
	nsExec::ExecToStack '"$RimeOwnershipPowerShell" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\invoke-rime-pime-maintenance.ps1" -Action "$RimeOwnershipAction" -InstallRoot "$INSTDIR" -TargetUserSid "$TargetUserSid" -ArchitectureSet "$RimeOwnershipArchitectures"'
	Pop $RimeOwnershipResult
	Pop $RimeOwnershipOutput
	${If} $RimeOwnershipResult != "0"
		MessageBox MB_OK|MB_ICONSTOP "Rime/PIME maintenance was not admitted. Save your work and close this product, then retry. Unknown or incomplete installations require separate repair. No force stop, shared quit event or cross-product cleanup was performed." /SD IDOK
		Abort
	${EndIf}
FunctionEnd
!macroend
!insertmacro YimePimeOwnershipGuard ""
!insertmacro YimePimeOwnershipGuard "un."

Function validateInstallPimeRoot
	StrCpy $RimeOwnershipAction "ValidateInstall"
	Call runOwnershipGuard
FunctionEnd

Function validateExistingPimeRoot
	StrCpy $RimeOwnershipAction "ValidateExisting"
	Call runOwnershipGuard
FunctionEnd

Function verifyRegistrationOwnership
	StrCpy $RimeOwnershipAction "ValidateRegistration"
	Call runOwnershipGuard
FunctionEnd

Function verifyRegistrationOwnershipForRemoval
	StrCpy $RimeOwnershipAction "ValidateRegistrationForRemoval"
	Call runOwnershipGuard
FunctionEnd

Function verifyRegistrationVacant
	StrCpy $RimeOwnershipAction "ValidateRegistrationVacant"
	Call runOwnershipGuard
FunctionEnd

Function verifyStagedRegistrationAbsent
	Call verifyRegistrationVacant
	!insertmacro RunCheckedRegistrationCommand '"$PLUGINSDIR\PIMERegistrationStatus_x86.exe" verify-absent' "x86 fresh-install TSF vacancy verification failed"
	${If} $RimeNativeArchitecture == "x64"
		!insertmacro RunCheckedRegistrationCommand '"$PLUGINSDIR\PIMERegistrationStatus_x64.exe" verify-absent' "x64 fresh-install TSF vacancy verification failed"
	${EndIf}
	!ifdef PACKAGE_PLAN_X86_ARM64X
	${If} $RimeNativeArchitecture == "arm64"
		!insertmacro RunCheckedRegistrationCommand '"$PLUGINSDIR\PIMERegistrationStatus_arm64.exe" verify-absent' "ARM64 fresh-install TSF vacancy verification failed"
	${EndIf}
	!endif
FunctionEnd

Function verifyStagedRegistrationForRemoval
	!insertmacro RunCheckedRegistrationCommand '"$PLUGINSDIR\PIMERegistrationStatus_x86.exe" verify-registered' "x86 pre-removal TSF registration verification failed"
	${If} $RimeNativeArchitecture == "x64"
		!insertmacro RunCheckedRegistrationCommand '"$PLUGINSDIR\PIMERegistrationStatus_x64.exe" verify-registered' "x64 pre-removal TSF registration verification failed"
	${EndIf}
	!ifdef PACKAGE_PLAN_X86_ARM64X
	${If} $RimeNativeArchitecture == "arm64"
		!insertmacro RunCheckedRegistrationCommand '"$PLUGINSDIR\PIMERegistrationStatus_arm64.exe" verify-registered' "ARM64 pre-removal TSF registration verification failed"
	${EndIf}
	!endif
FunctionEnd

Function un.verifyRegistrationOwnershipForRemoval
	StrCpy $RimeOwnershipAction "ValidateRegistrationForRemoval"
	Call un.runOwnershipGuard
FunctionEnd

Function un.verifyInstalledRegistrationForRemoval
	!insertmacro RunCheckedRegistrationCommand '"$PLUGINSDIR\PIMERegistrationStatus_x86.exe" verify-registered' "x86 pre-removal TSF registration verification failed"
	${If} $RimeNativeArchitecture == "x64"
		!insertmacro RunCheckedRegistrationCommand '"$PLUGINSDIR\PIMERegistrationStatus_x64.exe" verify-registered' "x64 pre-removal TSF registration verification failed"
	${EndIf}
	!ifdef PACKAGE_PLAN_X86_ARM64X
	${If} $RimeNativeArchitecture == "arm64"
		!insertmacro RunCheckedRegistrationCommand '"$PLUGINSDIR\PIMERegistrationStatus_arm64.exe" verify-registered' "ARM64 pre-removal TSF registration verification failed"
	${EndIf}
	!endif
FunctionEnd

Function un.cleanupTargetUserProfile
	StrCpy $RimeOwnershipAction "CleanupTargetUserProfile"
	Call un.runOwnershipGuard
FunctionEnd

Function un.verifyTargetUserProfileAbsent
	StrCpy $RimeOwnershipAction "ValidateTargetUserProfileAbsent"
	Call un.runOwnershipGuard
FunctionEnd

Function un.verifyNativeRegistrationAbsent
	StrCpy $RimeOwnershipAction "ValidateNativeRegistrationAbsent"
	Call un.runOwnershipGuard
FunctionEnd

Function verifyNativeRegistrationAbsent
	StrCpy $RimeOwnershipAction "ValidateNativeRegistrationAbsent"
	Call runOwnershipGuard
FunctionEnd

Function un.stopOwnedPime
	StrCpy $RimeOwnershipAction "ValidateExisting"
	Call un.runOwnershipGuard
	StrCpy $RimeOwnershipAction "Stop"
	Call un.runOwnershipGuard
FunctionEnd

Function InstallLayoutOrTipForUser
	Call validateTargetUserWorker
	; Add the registered TSF profile to the current user's language list.
	; The worker SID was matched to the captured non-elevated initiating SID.
	; Zero flags enable the TIP without replacing existing layouts.
	System::Call 'input.dll::InstallLayoutOrTip(w "${YIME_TIP}", i 0) i .r0'
	DetailPrint "InstallLayoutOrTip enable result: $0"
	${If} $0 == 0
		MessageBox MB_OK|MB_ICONSTOP "Rime/PIME could not add its profile to the initiating user's language list." /SD IDOK
		Abort
	${EndIf}
FunctionEnd

Function un.InstallLayoutOrTipForUser
	Call un.validateTargetUserWorker
	; ILOT_UNINSTALL (0x1) removes only this TIP from the user language list.
	System::Call 'input.dll::InstallLayoutOrTip(w "${YIME_TIP}", i 1) i .r0'
	DetailPrint "InstallLayoutOrTip disable result: $0"
	${If} $0 == 0
		; A user may already have disabled the profile. Continue only to the
		; exact TargetUserSid cleanup and the read-only verify-disabled gate;
		; neither a FALSE return nor a guessed enabled state is accepted alone.
		DetailPrint "InstallLayoutOrTip reported FALSE; exact disabled-state verification is still required."
	${EndIf}
FunctionEnd

; Admit only a genuinely fresh install. Current-family in-place upgrade remains
; disabled until side-by-side DLL staging, a durable journal and rollback are
; implemented. This function is deliberately read-only.
Function uninstallOldVersion
	ClearErrors
	StrCpy $RimeInstallMode ""
	; Current and historical marker families must never be mixed. This source
	; lane admits only a vacant root. A current or legacy installation needs
	; the separately reviewed journaled migration transaction and remains intact.
	ReadRegStr $R0 HKLM "${PRODUCT_UNINST_KEY}" "UninstallString"
	ReadRegStr $R1 HKLM "${PRODUCT_INSTALL_KEY}" ""
	ReadRegStr $R2 HKLM "${LEGACY_PRODUCT_UNINST_KEY}" "UninstallString"
	ReadRegStr $R3 HKLM "${LEGACY_PRODUCT_INSTALL_KEY}" ""
	${If} $R0 == ""
		${If} $R1 != ""
			MessageBox MB_OK|MB_ICONSTOP "Rime/PIME current registration is incomplete. Use the recovery workflow; no install mutation was started." /SD IDOK
			Abort
		${EndIf}
		${If} $R2 != ""
			MessageBox MB_OK|MB_ICONSTOP "A historical PIME installation needs an explicit migration workflow. It was not changed." /SD IDOK
			Abort
		${EndIf}
		${If} $R3 != ""
			MessageBox MB_OK|MB_ICONSTOP "A partial historical PIME registration was found. It was not changed." /SD IDOK
			Abort
		${EndIf}
		${If} $INSTDIR == ""
			StrCpy $INSTDIR "$PROGRAMFILES32\YIME"
		${EndIf}
		; Empty product markers are not proof of a fresh machine. Refuse Run,
		; nonempty roots, COM registrations, the shared TSF set and user remnants.
		Call verifyStagedRegistrationAbsent
		StrCpy $RimeInstallMode "fresh"
	${ElseIf} $R1 == ""
		MessageBox MB_OK|MB_ICONSTOP "Rime/PIME current registration is incomplete. Use the recovery workflow; no install mutation was started." /SD IDOK
		Abort
	${EndIf}
	${If} $R0 != ""
		StrCpy $INSTDIR $R1
		Call validateInstallPimeRoot
		Call validateExistingPimeRoot
		MessageBox MB_OK|MB_ICONSTOP "A current Rime/PIME installation was found. In-place upgrade is not enabled until side-by-side staging, a durable journal and rollback are sealed. The existing installation was not stopped, unregistered, overwritten or deleted." /SD IDOK
		Abort
	${EndIf}
	Call validateInstallPimeRoot
FunctionEnd

Function enforceInstallRootPolicy
	GetFullPathName $R0 "$PROGRAMFILES32\YIME"
	GetFullPathName $R1 "$INSTDIR"
	StrCmp $R1 $R0 installRootAccepted
		MessageBox MB_OK|MB_ICONSTOP "Rime/PIME must use its protected product root: $R0. Command-line /D overrides and user-writable roots are not admitted." /SD IDOK
		Abort
	installRootAccepted:
	StrCpy $INSTDIR $R0
FunctionEnd

; Called during installer initialization
Function .onInit
	MessageBox MB_OK|MB_ICONSTOP "This Rime/PIME development installer is disabled until exact payload ownership, durable recovery and reboot-journal closure are sealed. No product state was changed." /SD IDOK
	Abort

	; The supported desktop baseline is Windows 10 version 1903 (build 18362).
	; ManifestSupportedOS makes WinVer report the real Windows 10/11 version.
	; Check before extracting helpers or starting the same-SID elevation flow.
	${IfNot} ${AtLeastWin10}
		MessageBox MB_ICONSTOP|MB_OK $(AtLeastWin10_1903_MESSAGE)
		Quit
	${EndIf}
	${IfNot} ${AtLeastBuild} 18362
		MessageBox MB_ICONSTOP|MB_OK $(AtLeastWin10_1903_MESSAGE)
		Quit
	${EndIf}

	; Reject /D= and other alternate roots before extracting same-SID helpers.
	Call enforceInstallRootPolicy
	Call bootstrapTargetUser
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

	${If} ${RunningX64}
		SetRegView 64 ; disable registry redirection and use 64 bit Windows registry directly
	${EndIf}

	${If} ${IsNativeARM64}
		SetRegView 64 ; disable registry redirection for ARM64 (also uses 64-bit view)
	${EndIf}

	!insertmacro YimePimeStageRegistrationTools

	StrCpy $UPDATEX86DLL "True"
	StrCpy $UPDATEX64DLL "False"
	StrCpy $UPDATEARM64DLL "False"
	; NSIS is a 32-bit process. Use Sysnative for the host-native registrar and
	; SysWOW64 for the x86 registrar so neither DLL is sent to the wrong loader.
	StrCpy $RimeNativeRegsvr32 "$SYSDIR\regsvr32.exe"
	StrCpy $RimeX86Regsvr32 "$SYSDIR\regsvr32.exe"
	StrCpy $RimeNativeArchitecture ""
	StrCpy $RimeOwnershipArchitectures ""
	${If} ${IsNativeARM64}
		; A plain ARM64 DLL and a plain x64 DLL cannot occupy the same shared
		; 64-bit COM registration. Keep installation closed until the Arm64X
		; surface and ARM64-native, x64-emulated and x86-WOW64 host matrix seal.
		MessageBox MB_OK|MB_ICONSTOP "Windows ARM64 installation is not enabled yet: the Arm64X text-service surface and native, x64-emulated and x86 host acceptance are not sealed. No install mutation was started." /SD IDOK
		Abort
	${ElseIf} ${IsNativeAMD64}
		StrCpy $RimeNativeArchitecture "x64"
		StrCpy $UPDATEX64DLL "True"
		StrCpy $RimeNativeRegsvr32 "$WINDIR\Sysnative\regsvr32.exe"
		StrCpy $RimeX86Regsvr32 "$WINDIR\SysWOW64\regsvr32.exe"
		StrCpy $RimeOwnershipArchitectures "x64,x86"
	${Else}
		MessageBox MB_OK|MB_ICONSTOP "This development package supports mainstream Windows x86-64 systems; ARM64 installation remains fail closed pending Arm64X acceptance." /SD IDOK
		Abort
	${EndIf}

FunctionEnd

; The uninstaller never executes mutable files from its installation directory
; as privileged registration helpers. These bytes are embedded when the signed
; uninstaller is built and extracted into its private plugin directory.
Function un.stageTrustedRegistrationTools
	InitPluginsDir
	!insertmacro YimePimeStageRegistrationTools
FunctionEnd

Function un.onInit
	MessageBox MB_OK|MB_ICONSTOP "This Rime/PIME development uninstaller is disabled until exact payload ownership, durable recovery and reboot-journal closure are sealed. No product state was changed." /SD IDOK
	Abort

	Call un.bootstrapTargetUser
	StrCpy $RimeNativeRegsvr32 "$SYSDIR\regsvr32.exe"
	StrCpy $RimeX86Regsvr32 "$SYSDIR\regsvr32.exe"
	StrCpy $RimeNativeArchitecture ""
	StrCpy $RimeOwnershipArchitectures ""
	${If} ${IsNativeARM64}
		!ifdef PACKAGE_PLAN_X86_ARM64X
		StrCpy $RimeNativeArchitecture "arm64"
		StrCpy $RimeNativeRegsvr32 "$WINDIR\Sysnative\regsvr32.exe"
		StrCpy $RimeX86Regsvr32 "$WINDIR\SysWOW64\regsvr32.exe"
		StrCpy $RimeOwnershipArchitectures "arm64,x86"
		!else
		MessageBox MB_OK|MB_ICONSTOP "This uninstaller has no ARM64 text-service payload; no uninstall mutation was started." /SD IDOK
		Abort
		!endif
	${ElseIf} ${IsNativeAMD64}
		StrCpy $RimeNativeArchitecture "x64"
		StrCpy $RimeNativeRegsvr32 "$WINDIR\Sysnative\regsvr32.exe"
		StrCpy $RimeX86Regsvr32 "$WINDIR\SysWOW64\regsvr32.exe"
		StrCpy $RimeOwnershipArchitectures "x64,x86"
	${Else}
		MessageBox MB_OK|MB_ICONSTOP "This development package supports mainstream Windows x86-64 and ARM64 systems only." /SD IDOK
		Abort
	${EndIf}
	Call un.stageTrustedRegistrationTools
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


;Installer Type
InstType "$(INST_TYPE_STD)"

;Installer Sections
Section $(SECTION_MAIN) SecMain
	SectionIn 1 RO
	; This is the first point after the license page. Admission is read-only and
	; current-family upgrades fail closed until their durable transaction exists.
	Call uninstallOldVersion
	${If} $INSTDIR == ""
		StrCpy $INSTDIR "$PROGRAMFILES32\YIME"
	${EndIf}
	Call validateInstallPimeRoot
	${If} $RimeInstallMode != "fresh"
		MessageBox MB_OK|MB_ICONSTOP "Rime/PIME install mode was not admitted. No payload or registration was changed." /SD IDOK
		Abort
	${EndIf}
	; Re-read the exact root, markers, COM views and one shared TSF set
	; immediately before the first payload write.
	Call validateInstallPimeRoot
	Call verifyStagedRegistrationAbsent
	; The remaining source below is deliberately compiled for static/package
	; verification, but no install is admitted until exact payload removal,
	; durable recovery/journal replay, private font ownership, non-elevated
	; runtime readiness and signed-uninstaller closure are all wired and sealed.
	MessageBox MB_OK|MB_ICONSTOP "This Rime/PIME development package is not installable yet. Payload removal, durable recovery, private font ownership, runtime readiness and signed-uninstaller closure remain unsealed. No product state was changed." /SD IDOK
	Abort

	; Native and Go payloads are built and architecture-checked before NSIS runs.
	; The installer must only package those verified artifacts; it must never invoke
	; a compiler on an end user's machine.

	SetOverwrite on ; overwrite existing files
	; Yime is the standard product payload. Keep it in the required main
	; section so a default install always contains the configured backend.
	; These retired Go demo backends were shipped as empty directories by old
	; development packages. Non-recursive RMDir removes only empty leftovers
	; and preserves the directory if a user placed any files there.
	RMDir "$INSTDIR\go-backend\input_methods\fcitx5"
	RMDir "$INSTDIR\go-backend\input_methods\meow"
	RMDir "$INSTDIR\go-backend\input_methods\simple_pinyin"
	!insertmacro YimePimeStageMainPayload

	; The packaged Yime backend already contains YinYuan-Regular.ttf. The TSF
	; loads that single copy with FR_PRIVATE in each host process; never copy it
	; to the system Fonts directory or create a second product-owned copy.
SectionEnd

!macro InstallTextServiceDll ARCH UPDATE_FLAG
	SetOutPath "$INSTDIR\${ARCH}"
	; Only a vacant fresh root reaches this macro. Deferred replacement would
	; permit old mapped bytes to be registered and is therefore forbidden.
	${If} ${UPDATE_FLAG} != "True"
		MessageBox MB_OK|MB_ICONSTOP "Rime/PIME text-service staging was not admitted for ${ARCH}." /SD IDOK
		Abort
	${EndIf}
!macroend

Section "" Register
	SectionIn 1

	; Install the text service dlls
	${If} $RimeNativeArchitecture == "x64"
		!insertmacro InstallTextServiceDll "x64" $UPDATEX64DLL
		!insertmacro YimePimeStageTextServiceX64
		; Register COM objects (NSIS RegDLL command is broken and cannot be used)
		!insertmacro RunCheckedRegistrationCommand '"$RimeNativeRegsvr32" /s "$INSTDIR\x64\PIMETextService.dll"' "x64 text-service registration failed"
	${EndIf}

	!insertmacro InstallTextServiceDll "x86" $UPDATEX86DLL
	!insertmacro YimePimeStageTextServiceX86
	; Register COM objects (NSIS RegDLL command is broken and cannot be used)
	!insertmacro RunCheckedRegistrationCommand '"$RimeX86Regsvr32" /s "$INSTDIR\x86\PIMETextService.dll"' "x86 text-service registration failed"
	Call InstallLayoutOrTipForUser

	; Bind every path-bearing product registration to the selected install root.
	WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Run" "PIMELauncher" "$\"$INSTDIR\PIMELauncher.exe$\""

	;Store installation folder in the registry
	WriteRegStr HKLM "${PRODUCT_INSTALL_KEY}" "" $INSTDIR
	;Write an entry to Add & Remove applications
	WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayName" $(PRODUCT_NAME)
	WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
	WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "InstallLocation" "$INSTDIR"
	WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "Publisher" $(PRODUCT_PUBLISHER)
	; WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayIcon" "$INSTDIR\x86\PIMETextService.dll"
	WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
	WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "URLInfoAbout" "${HOMEPAGE_URL}"
	WriteUninstaller "$INSTDIR\Uninstall.exe" ;Create uninstaller
	Call verifyRegistrationOwnership

	; COM paths are verified above. TSF has one shared machine Profile/category
	; set; architecture-matched probes must agree when enumerating that same set.
	!insertmacro RunCheckedRegistrationCommand '"$PLUGINSDIR\PIMERegistrationStatus_x86.exe" verify-present' "x86 TSF profile/category verification failed"
	${If} $RimeNativeArchitecture == "x64"
		!insertmacro RunCheckedRegistrationCommand '"$PLUGINSDIR\PIMERegistrationStatus_x64.exe" verify-present' "x64 TSF profile/category verification failed"
	${EndIf}
!ifdef PACKAGE_PLAN_X86_ARM64X
	${If} $RimeNativeArchitecture == "arm64"
		!insertmacro RunCheckedRegistrationCommand '"$PLUGINSDIR\PIMERegistrationStatus_arm64.exe" verify-present' "ARM64 TSF profile/category verification failed"
	${EndIf}
	!endif

	; A later transaction stage will return startup to a non-elevated token.
	; Until then this source build is not approved for native installation.
	ClearErrors
	Exec '"$INSTDIR\PIMELauncher.exe"'
	${If} ${Errors}
		DetailPrint "PIMELauncher process creation failed."
		Abort
	${EndIf}

	CreateShortCut "$SMPROGRAMS\$(PRODUCT_NAME)\$(UNINSTALL_PIME).lnk" "$INSTDIR\Uninstall.exe"
SectionEnd

;Uninstaller Section
Section "Uninstall"
	MessageBox MB_OK|MB_ICONSTOP "This Rime/PIME development uninstaller is disabled until exact payload ownership, durable recovery and reboot-journal closure are sealed. No product state was changed." /SD IDOK
	Abort

	; Removal must remain possible when the initiating user already disabled the
	; profile. Machine registration, selected root and SID are still exact.
	Call un.verifyRegistrationOwnershipForRemoval
	Call un.verifyInstalledRegistrationForRemoval
	Call un.stopOwnedPime
	${If} ${RunningX64}
		SetRegView 64 ; disable registry redirection and use 64 bit Windows registry directly
	${EndIf}

	${If} ${IsNativeARM64}
		SetRegView 64 ; disable registry redirection on ARM64 systems
	${EndIf}

	; Remove only the initiating user's language-list entry before unregistering
	; the machine Profile/categories. Product markers remain available until all
	; unregister exits and read-only absence probes pass.
	Call un.InstallLayoutOrTipForUser

	; InstallLayoutOrTip may report FALSE for an already-disabled profile. Before
	; any raw per-user cleanup, architecture-matched probes must agree on the one
	; shared machine profile/category set and a disabled current-user TIP.
	!insertmacro RunCheckedRegistrationCommand '"$PLUGINSDIR\PIMERegistrationStatus_x86.exe" verify-disabled' "x86 TSF disabled-state verification failed"
	${If} $RimeNativeArchitecture == "x64"
		!insertmacro RunCheckedRegistrationCommand '"$PLUGINSDIR\PIMERegistrationStatus_x64.exe" verify-disabled' "x64 TSF disabled-state verification failed"
	${EndIf}
	!ifdef PACKAGE_PLAN_X86_ARM64X
	${If} $RimeNativeArchitecture == "arm64"
		!insertmacro RunCheckedRegistrationCommand '"$PLUGINSDIR\PIMERegistrationStatus_arm64.exe" verify-disabled' "ARM64 TSF disabled-state verification failed"
	${EndIf}
	!endif

	; Unregister with package-embedded, architecture-matched bytes. Never grant
	; elevated execution to a replaceable installed DLL.
	!insertmacro RunCheckedRegistrationCommand '"$RimeX86Regsvr32" /u /s "$PLUGINSDIR\PIMETextService_x86.dll"' "x86 text-service unregister failed"
	${If} $RimeNativeArchitecture == "x64"
		!insertmacro RunCheckedRegistrationCommand '"$RimeNativeRegsvr32" /u /s "$PLUGINSDIR\PIMETextService_x64.dll"' "x64 text-service unregister failed"
	${EndIf}

	!ifdef PACKAGE_PLAN_X86_ARM64X
	${If} $RimeNativeArchitecture == "arm64"
		!insertmacro RunCheckedRegistrationCommand '"$RimeNativeRegsvr32" /u /s "$PLUGINSDIR\PIMETextService_arm64.dll"' "ARM64 text-service unregister failed"
	${EndIf}
	!endif

	Call un.verifyNativeRegistrationAbsent
	!insertmacro RunCheckedRegistrationCommand '"$PLUGINSDIR\PIMERegistrationStatus_x86.exe" verify-absent' "x86 TSF profile/category absence verification failed"
	${If} $RimeNativeArchitecture == "x64"
		!insertmacro RunCheckedRegistrationCommand '"$PLUGINSDIR\PIMERegistrationStatus_x64.exe" verify-absent' "x64 TSF profile/category absence verification failed"
	${EndIf}
	!ifdef PACKAGE_PLAN_X86_ARM64X
	${If} $RimeNativeArchitecture == "arm64"
		!insertmacro RunCheckedRegistrationCommand '"$PLUGINSDIR\PIMERegistrationStatus_arm64.exe" verify-absent' "ARM64 TSF profile/category absence verification failed"
	${EndIf}
	!endif

	; Raw per-user cleanup is intentionally last among registration mutations.
	; If native unregister/readback fails, recovery can still re-enable the intact
	; target-user subtree rather than discovering that it was already erased.
	Call un.cleanupTargetUserProfile
	Call un.verifyTargetUserProfileAbsent

	; Historical PIME marker families are never deleted without their own exact
	; owner snapshot. This uninstaller owns only the current YIME records.
	DeleteRegKey HKLM "${PRODUCT_UNINST_KEY}"
	DeleteRegValue HKLM "Software\Microsoft\Windows\CurrentVersion\Run" "PIMELauncher"
	DeleteRegKey HKLM "${PRODUCT_INSTALL_KEY}"

	; Quiescent state and ownership were checked before any mutation.
	Delete /REBOOTOK "$INSTDIR\PIMELauncher.exe"
	${If} $RimeNativeArchitecture == "x64"
		RMDir /REBOOTOK /r "$INSTDIR\x64"
	${EndIf}
	!ifdef PACKAGE_PLAN_X86_ARM64X
	${If} $RimeNativeArchitecture == "arm64"
		RMDir /REBOOTOK /r "$INSTDIR\arm64"
	${EndIf}
	!endif

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
