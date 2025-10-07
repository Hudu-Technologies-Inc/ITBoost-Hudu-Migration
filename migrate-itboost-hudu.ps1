$project_workdir=$project_workdir ?? $PSScriptRoot
$toolsPath = resolve-path .\tools\
$project_workdir=$PSScriptRoot
$debug_folder=$(join-path "$project_workdir" "debug")
$locations_folder=$(join-path $debug_folder "locations")
$contacts_folder=$(join-path $debug_folder "contacts")
$docs_folder=$(join-path $project_workdir "docs")


foreach ($folder in @($debug_folder, $contacts_folder, $locations_folder, $docs_folder)) {
    if (!(Test-Path -Path "$folder")) { New-Item "$folder" -ItemType Directory }
}
$ITBoostExportPath=$ITBoostExportPath ?? "C:\tmp\ITBoost"
while (-not $(test-path $ITBoostExportPath)){
    $ITBoostExportPath=$(read-host "please specify your ITBoost export path and make sure it contains csvs!")
    if ($(test-path $ITBoostExportPath)){break}
}

# init 
foreach ($file in $(Get-ChildItem -Path ".\helpers" -Filter "*.ps1" -File | Sort-Object Name)) {
    Write-Host "Importing: $($file.Name)" -ForegroundColor DarkBlue
    . $file.FullName
}
Get-PSVersionCompatible; Get-HuduModule; Set-HuduInstance; Get-HuduVersionCompatible;

if ($null -eq $UseSimpleMap){$UseSimpleMap = $true}
## grab the csv data
$ITBoostData=@{
    JobState=@{}
    CompletedJobs=@()
}

# foreach ($job in @("get-hududata","read-csvs","companies","websites","locations","contacts","configs","passwords","wrap-up")){
foreach ($job in @("get-hududata","read-csvs","documents")){
    $ITBoostData.JobState = @{Status="$job"; StartedAt=$(Get-Date); FinishedAt=$null}
    write-host "Starting $($ITBoostdata.JobState.Status) at $($ITBoostdata.JobState.StartedAt)"
    . ".\jobs\$job.ps1"
    $ITBoostData.FinishedAt=$(Get-Date)
    Write-Host "$($ITBoostData.JobState.Status) Completed"; $ITBoostData.CompletedJobs+=$ITBoostData.JobState
}

