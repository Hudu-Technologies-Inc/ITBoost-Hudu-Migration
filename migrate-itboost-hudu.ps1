$project_workdir=$project_workdir ?? $PSScriptRoot
$toolsPath = resolve-path .\tools\
$project_workdir=$PSScriptRoot
$debug_folder=$debug_folder ?? $(join-path "$project_workdir" "debug")
$companiesIndex =  $(join-path $debug_folder -ChildPath "MatchedCompanies.json")

$UseSimpleMap = $true
$SkipInactive = $SkipInactive ?? $true
$ConfigExpansionMethod = "ALL"


$ITBoostExportPath=$ITBoostExportPath ?? "$(read-host "enter ITBoost export path")"
while (-not $(test-path $ITBoostExportPath)){
    $ITBoostExportPath=$(read-host "please specify your ITBoost export path and make sure it contains csvs!")
    if ($(test-path $ITBoostExportPath)){break}
}

# init 
foreach ($file in $(Get-ChildItem -Path ".\helpers" -Filter "*.ps1" -File | Sort-Object Name)) {
    Write-Host "Importing: $($file.Name)" -ForegroundColor DarkBlue
    . $file.FullName
}
foreach ($requiredpath in @($TMPbasedir, $debug_folder)){Get-EnsuredPath -path $requiredpath}
Get-PSVersionCompatible; Get-HuduModule; Set-HuduInstance; Get-HuduVersionCompatible;

if ($null -eq $UseSimpleMap){$UseSimpleMap = $true}
$mergeOnMatch = $mergeOnMatch ?? $("yes" -eq $(Select-Objectfromlist -objects @("yes","no") -message "When matches are found, do you want to merge data from ITBoost into Hudu (yes) or skip asset and keep existing Hudu data (no)?"))
$skipInactive = $skipInactive ?? $("yes" -eq $(Select-Objectfromlist -objects @("yes","no") -message "When inactive assets are found, do you want to skip them (yes) or include them (no)?"))
if ($true -eq $mergeOnMatch){$preferOrginal = $preferOrginal ?? $(select-objectfromlist -objects @("ITBoost","Hudu") -message "When merging on match, which data source do you want to prefer for field values?")} else {$preferOrginal = $false}

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

foreach ($job in @(
"read-csvs",
"get-hududata",
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
)){
    $ITBoostData.JobState = @{Status="$job"; StartedAt=$(Get-Date); FinishedAt=$null}
    write-host "Starting $($ITBoostdata.JobState.Status) at $($ITBoostdata.JobState.StartedAt)"
    . ".\jobs\$job.ps1"
    $ITBoostData.FinishedAt=$(Get-Date)
    Write-Host "$($ITBoostData.JobState.Status) Completed"; $ITBoostData.CompletedJobs+=$ITBoostData.JobState;
}
$flexiLayoutsCompleted = $false
$flexIdx = 0
while ($false -eq $flexiLayoutsCompleted){
    $flexIdx++
    write-host "Starting flexible asset layouts round ($flexIdx) (optional, but reccomended)"
    $ITBoostData.JobState = @{Status="flexi-round-$idx"; StartedAt=$(Get-Date); FinishedAt=$null}
    if ("yes" -ieq $(select-objectfromlist -objects @("yes","No") -message "do you wish to process flexible layouts round-$flexIdx now? (select 1/yes or 2/no)")){
        . .\jobs\flexi-layout.ps1
    } else {
        $flexiLayoutsCompleted=$true
    }
    $ITBoostData.FinishedAt=$(Get-Date)
    Write-Host "$($ITBoostData.JobState.Status) Completed"; $ITBoostData.CompletedJobs+=$ITBoostData.JobState;
}
Write-Host "Wrapping Up"
. .\jobs\wrap-up.ps1
. .\jobs\relate-all.ps1