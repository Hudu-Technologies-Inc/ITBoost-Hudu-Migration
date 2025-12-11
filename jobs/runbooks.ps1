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
Write-Host "$($runbooks.Count) runbook folders found without CSV data, processing from filesystem"

foreach ($r in $runbooks) {
    Write-Host "Processing runbook: $($r.Name)"

    $docFiles = Get-ChildItem -Path $r.FullName -Recurse -File |
        Where-Object { $_.Extension -match '^\.(html?|txt)$' } |
        Sort-Object FullName

    if (-not $docFiles) {
        Write-Host "No document file found in runbook $($r.Name), skipping"
        continue
    }

    $uuid = [guid]::NewGuid().ToString()
    $dest = Join-Path $TMPbasedir ("rb-" + $uuid)
    Get-EnsuredPath -Path $dest | Out-Null

    $childFolder = (Get-ChildItem -Path $r.FullName -Directory | Select-Object -ExpandProperty Name) -join " - "
    if ([string]::IsNullOrWhiteSpace($childFolder)) {
        $childFolder = $r.Name
    }

    $docName = Get-SafeFilename -MaxLength 65 -Name "Runbook $childFolder"
    $docName = $docName -replace "Untitled","Untitled $($($uuid -split '-')[0])"
    Write-Host "Doc will be titled $docName"

    $images = Get-ChildItem -Path $r.FullName -Recurse -File |
        Where-Object { $_.Extension -match '^\.(png|jpe?g)$' }

    Write-Host "RB $docName has $($docFiles.Count) docfiles and $($images.Count) images"

    # combine docs
    $chunks = @()
    $docIdx = 0
    foreach ($doc in $docFiles) {
        $docIdx++
        $header = "===== Doc $docIdx $($doc.Name) ====="
        $body   = Get-Content -Path $doc.FullName -Raw
        $chunks += @($header, $body)
    }

    $combinedDoc = ($chunks -join "`n`n").Trim()
    Set-Content -Value $combinedDoc -Path (Join-Path $dest "rb-doc.html") -Force

    foreach ($img in $images) {
        Copy-Item -Path $img.FullName -Destination (Join-Path $dest $img.Name) -Force
    }

    # company matching unchanged, just possibly cleaned up
    if (-not $alwaysInternal) {
        $matchedRecord = $itboostdata.rb.csvdata |
            Where-Object { "$($_.id)" -ieq "$($r.Name)" } |
            Select-Object -First 1

        if ($null -ne $matchedRecord) {
            if ($matchedRecord.organization -ieq "Global"){
                $matchedCompany = $internalCompany
            } else {
                Write-Host "CSV indicates runbook $($r.Name) is linked to company $($matchedRecord.organization), attempting to match"
                $matchedCompany = Get-HuduCompanyFromName -CompanyName $matchedRecord.organization -HuduCompanies $huduCompanies -existingIndex ($ITBoostData.organizations["matches"] ?? $null)
            }
        } else {
            $matchedCompany = $internalCompany
        }

        if (-not $matchedCompany) {
            Write-Host "No matching company found for runbook $($r.Name), assigning to internal company $($internalCompany.Name)"
            $matchedCompany = $internalCompany
        }
    } else {
        $matchedCompany = $internalCompany
    }

    $matchedCompany = $matchedCompany.company ?? $matchedCompany
    Write-Host "Creating article for company $($matchedCompany.Name) - $docName"
    try {
        $newRunbook =$null
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
