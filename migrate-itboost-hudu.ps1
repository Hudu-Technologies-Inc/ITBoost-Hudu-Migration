$project_workdir=$project_workdir ?? $PSScriptRoot
if ($MyInvocation.InvocationName -eq '.') {
    Write-Host "Script was dot-sourced" -ForegroundColor Green
} else {
    Write-Host "Script was executed without dot-sourcing, this is the recommended method of running the script to ensure settings are retained in the session" -ForegroundColor Yellow; write-warning "exiting to prevent issues later on, please dot-source the script by running `. .\yourenvironmentfile.ps1` or `. .\migrate-itboost-hudu.ps1` from powershell 7.5 or later (ideally as Administrator)" -ForegroundColor Red;
    exit 1
}
$availableJobs = @(
"read-csvs",
"companies",
"locations",
"contacts",
"websites",
"configs",
"expand-configs",
"passwords",
"documents",
"runbooks",
"standalone-notes",
"gallery"
)

$toolsPath = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'tools') -ErrorAction Stop
$project_workdir=$PSScriptRoot
if ([string]::IsNullOrWhiteSpace($debug_folder)) { $debug_folder = Join-Path $project_workdir 'debug' }
if ([string]::IsNullOrWhiteSpace($TMPbasedir)) { $TMPbasedir = Join-Path ([IO.Path]::GetTempPath()) 'ITBoost-Hudu-Migration' }
try {$migrationRecord = Set-MigrationRecord} catch {}
$UseSimpleMap = $true
$SkipInactive = $SkipInactive ?? $true
$ConfigExpansionMethod = "ALL"


$ITBoostExportPath=$ITBoostExportPath ?? "$(read-host "enter ITBoost export path")"
while (-not $(test-path $ITBoostExportPath)){
    $ITBoostExportPath=$(read-host "please specify your ITBoost export path and make sure it contains csvs!")
    if ($(test-path $ITBoostExportPath)){break}
}

# init 
foreach ($file in $(Get-ChildItem -LiteralPath (Join-Path $project_workdir 'helpers') -Filter "*.ps1" -File -ErrorAction Stop | Sort-Object Name)) {
    Write-Host "Importing: $($file.Name)" -ForegroundColor DarkBlue
    . $file.FullName
}
# Fail before migration jobs if results or conversion files cannot be saved.
$debug_folder = Initialize-MigrationOutputDirectory -Path $debug_folder
$TMPbasedir = Initialize-MigrationOutputDirectory -Path $TMPbasedir
$companiesIndex = Join-Path $debug_folder 'MatchedCompanies.json'
Get-PSVersionCompatible; Set-HuduModuleInitialized -HuduBaseURL $HuduBaseURL -HuduAPIKey $HuduAPIKey;
$currentVersionResult = $($currentVersionResult ?? $([version]((get-huduappinfo).version))); $MinAllowedVersion = ([version]"2.46.0"); $DisallowedVersions = @([version]("2.37.0")); if ($currentVersionResult -lt $MinAllowedVersion){Write-Host "Sorry, your Hudu version $currentVersionResult is not supported. You'll need to upgrade to $($MinAllowedVersion) in order to continue."; exit 1;}; if ($DisallowedVersions -contains [version]($currentVersionResult)) {write-host "disallowed version $($currentVersionResult); Please upgrade or downgrade if possible first." -ForegroundColor Red; exit 1;};
if ($null -eq $UseSimpleMap){$UseSimpleMap = $true}
$mergeOnMatch = $mergeOnMatch ?? $("yes" -eq $(Select-Objectfromlist -objects @("yes","no") -message "When matches are found, do you want to merge data from ITBoost into Hudu (yes) or skip asset and keep existing Hudu data (no)?"))
$skipInactive = $skipInactive ?? $("yes" -eq $(Select-Objectfromlist -objects @("yes","no") -message "When inactive assets are found, do you want to skip them (yes) or include them (no)?"))
if ($true -eq $mergeOnMatch){$preferOrginal = $preferOrginal ?? $(select-objectfromlist -objects @("ITBoost","Hudu") -message "When merging on match, which data source do you want to prefer for field values?")} else {$preferOrginal = $true}
$skiponmatch = (-not $mergeOnMatch)


. (Join-Path $project_workdir 'jobs/get-hududata.ps1')

if ($null -eq $kbsEnabled -or $false -eq $kbsEnabled.CompanyKB -or $false -eq $kbsEnabled.CentralKB) {
    write-warning "in order to proceed, you need to enable both the CompanyKB and CentralKB features in Hudu."; exit 1;
}
if ($null -eq $assetsEnabled -or $false -eq $assetsEnabled) {
    write-warning "in order to proceed, you need to enable the Assets feature in Hudu."; exit 1;    
}


write-host @"
Merging on Match is set to: $mergeOnMatch
Skip Inactive is set to: $skipInactive
Prefer Original is set to: $preferOrginal
Config Expansion Method is set to: $ConfigExpansionMethod
Press CTL+C now to cancel if you need to adjust.
"@
start-sleep -Seconds 6
## grab the csv data
$ITBoostData=@{
    JobState=@{}
    CompletedJobs=@()
    ErrorsEncountered=@()
}

# Discovery and company creation are prerequisites, including when selected jobs are being rerun.
$jobsToRun = @('read-csvs', 'companies') + @($availableJobs | Where-Object { $_ -notin @('read-csvs', 'companies') })

foreach ($job in $jobsToRun){
    $ITBoostData.JobState = @{Status="$job"; Outcome='Running'; StartedAt=$(Get-Date); FinishedAt=$null}
    write-host "Starting $($ITBoostdata.JobState.Status) at $($ITBoostdata.JobState.StartedAt)"
    try {
        . (Join-Path $project_workdir "jobs/$job.ps1")
        $ITBoostData.JobState.FinishedAt = Get-Date
        $ITBoostData.JobState.Outcome = 'Completed'
        $ITBoostData.CompletedJobs += $ITBoostData.JobState
        Write-Host "$($ITBoostData.JobState.Status) Completed"
    } catch {
        $ITBoostData.JobState.FinishedAt = Get-Date
        $ITBoostData.JobState.Outcome = 'Failed'
        $ITBoostData.JobState.Error = $_.Exception.Message
        $ITBoostData.ErrorsEncountered += $ITBoostData.JobState
        Write-Warning "$($ITBoostData.JobState.Status) failed. Migration stopped; current results remain in `$ITBoostData."
        throw
    }
}
$flexiLayoutsCompleted = $false
$flexIdx = 0
while ($false -eq $flexiLayoutsCompleted){
    $flexIdx++
    write-host "Starting flexible asset layouts round ($flexIdx) (optional, but reccomended)"
    if ("yes" -ieq $(select-objectfromlist -objects @("yes","No") -message "do you wish to process flexible layouts round-$flexIdx now? (select 1/yes or 2/no)")){
        $ITBoostData.JobState = @{Status="flexi-round-$flexIdx"; Outcome='Running'; StartedAt=$(Get-Date); FinishedAt=$null}
        try {
            . (Join-Path $project_workdir 'jobs/flexi-layout.ps1')
            $ITBoostData.JobState.FinishedAt = Get-Date
            $ITBoostData.JobState.Outcome = 'Completed'
            $ITBoostData.CompletedJobs += $ITBoostData.JobState
            Write-Host "$($ITBoostData.JobState.Status) Completed"
        } catch {
            $ITBoostData.JobState.FinishedAt = Get-Date
            $ITBoostData.JobState.Outcome = 'Failed'
            $ITBoostData.JobState.Error = $_.Exception.Message
            $ITBoostData.ErrorsEncountered += $ITBoostData.JobState
            Write-Warning "$($ITBoostData.JobState.Status) failed. Migration stopped; current results remain in `$ITBoostData."
            throw
        }
    } else {
        $flexiLayoutsCompleted=$true
    }
}
Write-Host "Wrapping Up"
. (Join-Path $project_workdir 'jobs/wrap-up.ps1')
. (Join-Path $project_workdir 'jobs/relate-all.ps1')
