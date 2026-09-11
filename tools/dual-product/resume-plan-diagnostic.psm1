# Pure plan validation copied from Read-MaintenancePreparedPlan at 6321067de.
# No transaction store, registration, or runtime operations.
function Assert-ArchivedResumePlan($Plan,$PackageModule){
$script:CandidatePackageModule=$PackageModule
        & $script:CandidatePackageModule {
            param($v)
            Assert-CandidateObject $v @('schema_version','run_id','install_root','state_root','recovery_root','install_directory_id','state_directory_id',
                'initiating_sid','target_machine_id','target_name','manifest_sha256','package_sha256','product_version','original_approval_sha256','default_input','files','generated_files','recovery_executable')
            if($v.schema_version -isnot [string] -or $v.schema_version -cne 'yime-rime-pime-candidate-install-plan-v1'){throw 'Unsupported install plan.'}
            foreach($field in @('manifest_sha256','package_sha256','original_approval_sha256')){Assert-CandidateHash $v.$field}
            if($v.run_id -isnot [string] -or $v.run_id -cnotmatch '^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$'){throw 'Invalid install plan run identity.'}
            if($v.files -isnot [array] -or $v.files.Count -lt 12 -or $v.files.Count -gt 4096){throw 'Invalid install plan member count.'}
            $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach($row in $v.files){
                Assert-CandidateObject $row @('path','bytes','sha256','file_id')
                $null=Get-CandidatePath 'C:\Candidate' $row.path
                Assert-CandidateHash $row.sha256
                if(-not $seen.Add($row.path) -or $row.file_id -isnot [string] -or $row.file_id -cnotmatch '^[0-9a-f]{8}:[0-9a-f]{16}$' -or
                    ($row.bytes -isnot [long] -and $row.bytes -isnot [int]) -or $row.bytes -lt 0){throw 'Invalid install plan file identity.'}
            }
            Assert-CandidateObject $v.default_input @('override','first_language','first_tip')
            foreach($property in $v.default_input.PSObject.Properties){if($property.Value -isnot [string]){throw 'Invalid default-input baseline.'}}
            foreach($field in @('install_directory_id','state_directory_id')){
                if($v.$field -isnot [string] -or $v.$field -cnotmatch '^[0-9a-f]{8}:[0-9a-f]{16}$'){throw 'Invalid retained directory identity.'}
            }
            if($v.product_version -isnot [string] -or $v.product_version -cnotmatch '^1\.4\.0-dev\.[1-9][0-9]*$'){throw 'Invalid prepared product version.'}
            Assert-CandidateObject $v.recovery_executable @('file_id','bytes','sha256')
            Assert-CandidateHash $v.recovery_executable.sha256
            if($v.recovery_executable.file_id -isnot [string] -or $v.recovery_executable.file_id -cnotmatch '^[0-9a-f]{8}:[0-9a-f]{16}$' -or
                ($v.recovery_executable.bytes -isnot [int] -and $v.recovery_executable.bytes -isnot [long]) -or $v.recovery_executable.bytes -le 0 -or
                $v.recovery_executable.sha256 -cne $v.package_sha256){throw 'Invalid recovery executable binding.'}
            if($v.generated_files -isnot [array] -or $v.generated_files.Count -ne 2){throw 'Invalid generated installed members.'}
            foreach($g in $v.generated_files){
                Assert-CandidateObject $g @('path','bytes','sha256')
                $matching=@($v.files|Where-Object path -CEQ $g.path)
                if($g.path -cnotin @('rime-pime-candidate-state.json','maintenance-candidate.exe') -or $matching.Count -ne 1 -or
                    $g.bytes -cne $matching[0].bytes -or $g.sha256 -cne $matching[0].sha256){throw 'Generated member differs from prepared file.'}
            }
            if($v.generated_files[0].path -ceq $v.generated_files[1].path){throw 'Duplicate generated installed member.'}
        } $Plan
}
Export-ModuleMember -Function Assert-ArchivedResumePlan
