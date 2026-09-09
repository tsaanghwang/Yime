; Separate guarded development artifact. This never enables the historical NSIS lane.
Unicode true
RequestExecutionLevel user
SilentInstall silent
AutoCloseWindow true
SetCompressor /SOLID lzma
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "x64.nsh"
!ifndef CANDIDATE_OUTPUT
!error "A fresh externally selected candidate output is required."
!endif
!ifndef CANDIDATE_INCLUDE
!error "An exact generated payload include is required."
!endif
!ifndef CANDIDATE_MANIFEST_SHA256
!error "A sealed manifest digest is required."
!endif
Name "Yime Rime/PIME isolated development candidate"
OutFile "${CANDIDATE_OUTPUT}"
Var Arguments
Var Mode
Var Authorization
Var Approval
Var Boundary
Var Receipt
Var Prepared
Var PowerShell
Var CheckValue
Var Machine

; Values are used only as quoted arguments to powershell -File. Reject quotes,
; control characters and trailing backslashes before assembling that command.
Function ValidateArgument
  StrLen $0 $CheckValue
  ${If} $0 == 0
    SetErrorLevel 64
    Quit
  ${EndIf}
  StrCpy $1 0
  loop_argument:
    StrCpy $2 $CheckValue 1 $1
    ${If} $2 == '$\"'
    ${OrIf} $2 == '$\r'
    ${OrIf} $2 == '$\n'
    ${OrIf} $2 == '$\t'
      SetErrorLevel 64
      Quit
    ${EndIf}
    IntOp $1 $1 + 1
    IntCmp $1 $0 done_argument loop_argument done_argument
  done_argument:
  StrCpy $2 $CheckValue 1 -1
  ${If} $2 == '\'
    SetErrorLevel 64
    Quit
  ${EndIf}
FunctionEnd

Function .onInit
  ; No candidate payload is expanded and no maintenance child is started yet.
  System::Call 'kernel32::GetComputerNameW(w .r0, *i ${NSIS_MAX_STRLEN}) i.r1'
  ${If} $1 == 0
    SetErrorLevel 64
    Quit
  ${EndIf}
  StrCpy $Machine $0
  ${If} $Machine == "MYCOMPUTER"
    SetErrorLevel 64
    Quit
  ${EndIf}
  ${IfNot} ${RunningX64}
    SetErrorLevel 64
    Quit
  ${EndIf}
  ${If} ${IsNativeARM64}
    SetErrorLevel 64
    Quit
  ${EndIf}
  ${GetParameters} $Arguments
  ${GetOptions} $Arguments "/Mode=" $Mode
  ${GetOptions} $Arguments "/AuthorizationPath=" $Authorization
  ${GetOptions} $Arguments "/TrustedApprovalSha256=" $Approval
  ${GetOptions} $Arguments "/BoundaryPath=" $Boundary
  ${GetOptions} $Arguments "/ReceiptPath=" $Receipt
  ${GetOptions} $Arguments "/PreparedSha256=" $Prepared
  ${If} $Mode != "Install"
  ${AndIf} $Mode != "Remove"
  ${AndIf} $Mode != "Resume"
    SetErrorLevel 64
    Quit
  ${EndIf}
  StrCpy $CheckValue $Authorization
  Call ValidateArgument
  StrCpy $CheckValue $Approval
  Call ValidateArgument
  StrCpy $CheckValue $Boundary
  Call ValidateArgument
  StrCpy $CheckValue $Receipt
  Call ValidateArgument
  ${If} $Mode == "Resume"
  ${OrIf} $Mode == "Remove"
    StrCpy $CheckValue $Prepared
    Call ValidateArgument
  ${ElseIf} $Prepared != ""
    SetErrorLevel 64
    Quit
  ${EndIf}
  StrCpy $PowerShell "$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
  IfFileExists "$PowerShell" +3 0
    SetErrorLevel 64
    Quit
FunctionEnd

Section
  InitPluginsDir
  !include "${CANDIDATE_INCLUDE}"
  ; The source-owned controller validates exact SID, approval, receipt and target
  ; before UAC or mutation. No NSIS registration, deletion, Run key or uninstaller.
  ClearErrors
  ExecWait '"$PowerShell" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\bundle\maintenance\invoke-rime-pime-candidate.ps1" -Mode "$Mode" -PackageRoot "$PLUGINSDIR\bundle" -ExpectedManifestSha256 "${CANDIDATE_MANIFEST_SHA256}" -InstallerPath "$EXEPATH" -AuthorizationPath "$Authorization" -TrustedApprovalSha256 "$Approval" -BoundaryPath "$Boundary" -ReceiptPath "$Receipt" -PreparedSha256 "$Prepared"' $0
  ${If} ${Errors}
    SetErrorLevel 70
  ${Else}
    SetErrorLevel $0
  ${EndIf}
SectionEnd
