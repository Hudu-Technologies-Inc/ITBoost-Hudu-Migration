$project_workdir=$project_workdir ?? $PSScriptRoot


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

foreach ($job in @("get-hududata","read-csvs",#"companies","websites","locations",
"contacts")){
#,"passwords","wrap-up")){
    $ITBoostData.JobState = @{Status="$job"; StartedAt=$(Get-Date); FinishedAt=$null}
    write-host "Starting $($ITBoostdata.JobState.Status) at $($ITBoostdata.JobState.StartedAt)"
    . ".\jobs\$job.ps1"
    $ITBoostData.FinishedAt=$(Get-Date)
    Write-Host "$($ITBoostData.JobState.Status) Completed"; $ITBoostData.CompletedJobs+=$ITBoostData.JobState
}

