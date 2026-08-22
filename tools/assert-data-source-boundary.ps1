[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [string]$InputId,
    [string]$ApprovalManifest = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$approvalRoot = Join-Path $PSScriptRoot "data_import_approvals"
$resolvedSource = (Resolve-Path -LiteralPath $Path).Path
$sourceItem = Get-Item -LiteralPath $resolvedSource
$probe = if ($sourceItem.PSIsContainer) { $sourceItem } else { $sourceItem.Directory }

$reparseProbe = $sourceItem
while ($null -ne $reparseProbe) {
    if (($reparseProbe.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Data source paths must not traverse a symlink or junction: $($reparseProbe.FullName)"
    }
    $reparseProbe = $reparseProbe.Parent
}

function Test-PathWithin {
    param([string]$Candidate, [string]$Root)
    $candidateFull = [IO.Path]::GetFullPath($Candidate).TrimEnd('\', '/')
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    return $candidateFull.Equals($rootFull, [StringComparison]::OrdinalIgnoreCase) -or
        $candidateFull.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

$sourceRepository = $null
$cursor = $probe
while ($null -ne $cursor) {
    if (Test-Path -LiteralPath (Join-Path $cursor.FullName ".git")) {
        $sourceRepository = $cursor.FullName
        break
    }
    if ($cursor.Name -in @("Yime-python-prototype", "Yime-prototype")) {
        $sourceRepository = $cursor.FullName
        break
    }
    $cursor = $cursor.Parent
}

if ($null -eq $sourceRepository -or (Test-PathWithin -Candidate $sourceRepository -Root $repoRoot)) {
    exit 0
}
if ([string]::IsNullOrWhiteSpace($ApprovalManifest)) {
    throw "Data source belongs to another repository and is blocked by default: $resolvedSource (repository $sourceRepository); input ID '$InputId'. A reviewed, time-limited approval is required."
}

$resolvedApproval = (Resolve-Path -LiteralPath $ApprovalManifest).Path
if (-not (Test-PathWithin -Candidate $resolvedApproval -Root $approvalRoot)) {
    throw "Repository import approval must be stored under $approvalRoot for review."
}
$approval = Get-Content -LiteralPath $resolvedApproval -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$approval.schema_version -ne "yime-repository-data-import-approval-v1" -or
    [string]$approval.decision -ne "allow" -or
    [string]$approval.target_repository -ne "Yime") {
    throw "Repository import approval schema, decision, or target is invalid."
}
foreach ($field in @("approval_id", "approved_by", "reason", "authorization_reference", "source_repository_root")) {
    if ([string]::IsNullOrWhiteSpace([string]$approval.$field)) {
        throw "Repository import approval has no $field."
    }
}
$approvedAt = [DateTimeOffset]::Parse([string]$approval.approved_at)
$expiresAt = [DateTimeOffset]::Parse([string]$approval.expires_at)
$now = [DateTimeOffset]::UtcNow
if ($approvedAt -gt $now -or $expiresAt -le $now -or $expiresAt -le $approvedAt -or
    ($expiresAt - $approvedAt).TotalDays -gt 31) {
    throw "Repository import approval is not active or exceeds the 31-day limit."
}
if (-not ([IO.Path]::GetFullPath([string]$approval.source_repository_root).TrimEnd('\', '/')).Equals(
    [IO.Path]::GetFullPath($sourceRepository).TrimEnd('\', '/'),
    [StringComparison]::OrdinalIgnoreCase
)) {
    throw "Repository import approval source_repository_root does not match $sourceRepository."
}
if ($approval.allowed_input_ids -isnot [System.Array] -or
    @($approval.allowed_input_ids) -notcontains $InputId) {
    throw "Repository import approval does not allow input ID '$InputId'."
}
