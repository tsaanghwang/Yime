$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot '../Product.psm1') -Force

$admin='S-1-5-32-544';$users='S-1-5-32-545'
$trusted=@('S-1-5-18',$admin)
function New-TestAcl([string]$Owner,[string]$Principal,[Security.AccessControl.FileSystemRights]$Rights,
    [Security.AccessControl.AccessControlType]$Type=[Security.AccessControl.AccessControlType]::Allow){
    $acl=[Security.AccessControl.DirectorySecurity]::new()
    $acl.SetOwner([Security.Principal.SecurityIdentifier]::new($Owner))
    $rule=[Security.AccessControl.FileSystemAccessRule]::new(
        [Security.Principal.SecurityIdentifier]::new($Principal),$Rights,$Type)
    $acl.AddAccessRule($rule)
    return $acl
}
function MustReject([scriptblock]$Case){
    $rejected=$false
    try{& $Case | Out-Null}catch{$rejected=$true}
    if(-not $rejected){throw 'Untrusted mutating ACL accepted'}
}

$read=New-TestAcl $admin $users ([Security.AccessControl.FileSystemRights]::ReadAndExecute)
Assert-Arm64ProtectedAcl $read 'synthetic-read-only' $trusted
if(Test-Arm64MutatingRight ([Security.AccessControl.FileSystemRights]::ReadAndExecute)){
    throw 'Read-only rights classified as mutation'
}
$adminWrite=New-TestAcl $admin $admin ([Security.AccessControl.FileSystemRights]::FullControl)
Assert-Arm64ProtectedAcl $adminWrite 'synthetic-admin-only' $trusted
$denied=New-TestAcl $admin $users ([Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles) ([Security.AccessControl.AccessControlType]::Deny)
Assert-Arm64ProtectedAcl $denied 'synthetic-deny' $trusted

$granular=@(
    [Security.AccessControl.FileSystemRights]::WriteData,
    [Security.AccessControl.FileSystemRights]::AppendData,
    [Security.AccessControl.FileSystemRights]::WriteExtendedAttributes,
    [Security.AccessControl.FileSystemRights]::WriteAttributes,
    [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles,
    [Security.AccessControl.FileSystemRights]::Delete,
    [Security.AccessControl.FileSystemRights]::ChangePermissions,
    [Security.AccessControl.FileSystemRights]::TakeOwnership
)
foreach($right in $granular){
    if(-not (Test-Arm64MutatingRight $right)){throw ('Mutation right omitted: '+$right)}
    $acl=New-TestAcl $admin $users $right
    MustReject {Assert-Arm64ProtectedAcl $acl 'synthetic-untrusted-write' $trusted}
}
foreach($right in @([Security.AccessControl.FileSystemRights]::Modify,[Security.AccessControl.FileSystemRights]::FullControl)){
    $acl=New-TestAcl $admin $users $right
    MustReject {Assert-Arm64ProtectedAcl $acl 'synthetic-untrusted-composite' $trusted}
}
foreach($right in @([Security.AccessControl.FileSystemRights]::CreateFiles,[Security.AccessControl.FileSystemRights]::CreateDirectories)){
    if(-not (Test-Arm64MutatingRight $right)){throw ('Directory creation right omitted: '+$right)}
}
foreach($right in @(0x10000000,0x40000000)){
    if(-not (Test-Arm64MutatingRight $right)){
        throw ('Generic mutation right omitted: '+$right)
    }
}
$badOwner=New-TestAcl $users $admin ([Security.AccessControl.FileSystemRights]::Read)
MustReject {Assert-Arm64ProtectedAcl $badOwner 'synthetic-untrusted-owner' $trusted}
Write-Output 'PASS ARM64 ACL mutation contract: 8 granular refusals, 2 composite refusals, read-only allow'
