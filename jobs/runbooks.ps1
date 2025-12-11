get-ensuredpath -path $TMPbasedir | Out-Null

$internalCompany = Get-HuduCompanies -id $internalCompanyId
$internalCompany = $internalCompany.company ?? $internalCompany
if (-not $internalCompany){
    write-host "Internal company $($internalCompany.name) with ID $internalCompanyId not found, cannot proceed"
    exit 1
}
$newRunbooks = @()
if (-not $itboostdata.ContainsKey("rb") -or -not $itboostdata.rb.csvdata){
    $alwaysInternal = $true
} else {$alwaysInternal = $false}
$runbooksFolder = $(join-path $ITBoostExportPath -ChildPath "Rb")
if (-not $(test-path $runbooksFolder)){
    write-host "No runbooks folder found at $runbooksFolder, skipping"
    exit 1
}
$runbooks = Get-ChildItem -Path $runbooksFolder -Directory
write-host "$($runbooks.count) runbooks folders found without CSV data, processing from filesystem"
foreach ($r in $runbooks){
    write-host "processing runbook: $($r.name)"
    $docFile = $null; $images = $null;
    $docFile = Get-ChildItem -Path $r.FullName -Recurse -File |
                Where-Object { $_.Extension -match '\.md|\.markdown|\.html|\.htm|\.txt' } |
                Select-Object -First 1
    if (-not $docFile){
        write-host "No document file found in runbook $($r.name), skipping"
        continue
    }
    $uuid = [guid]::NewGuid().ToString()

    $childFolder = get-childitem -Path $r.FullName -Directory | select-object -first 1
    $docName = "$(Get-SafeFilename -MaxLength 65 -Name "Runbook $($childFolder.name)")" -replace "Untitled","Untitled $($($uuid -split "-")[0])"
    write-host "Doc will be titled $docname"
    $images = Get-ChildItem -Path $r.FullName -Recurse -File |
                Where-Object { $_.Extension -match '\.png|\.jpg|\.jpeg' }
    write-host "RB has docfile $docFile and $($images.count) images"

    $dest = Join-Path $TMPbasedir ("rb-" + $uuid)    
    get-ensuredpath -path $dest | Out-Null

    copy-item -path $docFile.FullName -destination (Join-Path $dest $docFile.Name) -force
    foreach ($img in $images){
        copy-item -path $img.FullName -destination (Join-Path $dest $img.Name) -force
    }
    if ($false -eq $alwaysInternal){
        $matchedRecord = $null
        $matchedRecord = $itboostdata.rb.csvdata | where-object {"$($_.id)" -ieq "$($r.name)"} | select-object -first 1
        if ($null -ne $matchedRecord){
            $matchedCompany = $internalCompany
        } else {
            write-host "csv indicates that runbook $($r.name) is linked to company $($matchedRecord.organization), attempting to match"
            $matchedCompany = Get-HuduCompanyFromName -CompanyName $matchedRecord.organization -HuduCompanies $huduCompanies  -existingIndex $($ITBoostData.organizations["matches"] ?? $null)
        }
        if (-not $matchedCompany){
            write-host "No matching company found for runbook $($r.name), assigning to internal company $($internalCompany.name)"
            $matchedCompany = $internalCompany
        }
    } else {
        $matchedCompany = $internalCompany
    }
    write-host "creating article for company $($matchedCompany.name) -"
    try {
        $newRunbook = Set-HuduArticleFromResourceFolder -resourcesFolder $dest -companyName $matchedCompany.name -title $docName
    } catch {
        Write-Host "Error creating article for runbook $($docName): $_"
        continue
    }
    if (-not $newRunbook -or -not $newRunbook.Title){
        Write-Host "Failed to create article for runbook $($docName), skipping"
        continue
    }
    $newRunbooks+=$newRunbook
}
