$project_workdir=$project_workdir ?? $PSScriptRoot
$toolsPath = resolve-path .\tools\
$project_workdir=$PSScriptRoot
$debug_folder=$debug_folder ?? $(join-path "$project_workdir" "debug")
$companiesIndex =  $(join-path $debug_folder -ChildPath "MatchedCompanies.json")

$UseSimpleMap = $true
$SkipInactive = $true
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
"websites"
"configs",
"expand-configs",
"documents",
"runbooks",
"standalone-notes",
"gallery",
"passwords"
)){
# foreach ($job in @("get-hududata","read-csvs")){
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
    if ("Yes" -eq $(selectobject-fromlist -objects @("yes","No") -message "do you wish to process flexible layouts round-$flexIdx now?")){
        . .\jobs\flexi-layout.ps1
    } else {
        $flexiLayoutsCompleted=$true
    }
    $ITBoostData.FinishedAt=$(Get-Date)
    Write-Host "$($ITBoostData.JobState.Status) Completed"; $ITBoostData.CompletedJobs+=$ITBoostData.JobState;
}
Write-Host "Wrapping Up"
# . .\jobs\wrap-up.ps1
