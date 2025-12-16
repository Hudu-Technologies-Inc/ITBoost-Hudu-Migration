$project_workdir=$project_workdir ?? $PSScriptRoot
$toolsPath = resolve-path .\tools\
$project_workdir=$PSScriptRoot
$debug_folder=$debug_folder ?? $(join-path "$project_workdir" "debug")
$companiesIndex =  $(join-path $debug_folder -ChildPath "MatchedCompanies.json")

$UseSimpleMap = $true
$SkipInactive = $true


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
# "companies",
# "locations",
"contacts",
# "websites",
# "configs",
# "expand-configs",
# "documents",
# "runbooks",
# "standalone-notes",
# "gallery",
# "flexi-layout"
"passwords",
"wrap-up"
)){
# foreach ($job in @("get-hududata","read-csvs")){
    $ITBoostData.JobState = @{Status="$job"; StartedAt=$(Get-Date); FinishedAt=$null}
    write-host "Starting $($ITBoostdata.JobState.Status) at $($ITBoostdata.JobState.StartedAt)"
    . ".\jobs\$job.ps1"
    $ITBoostData.FinishedAt=$(Get-Date)
    Write-Host "$($ITBoostData.JobState.Status) Completed"; $ITBoostData.CompletedJobs+=$ITBoostData.JobState
}

