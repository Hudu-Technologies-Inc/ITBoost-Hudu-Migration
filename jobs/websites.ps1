# load companies index if available
$ITBoostData.organizations["matches"] = $ITBoostData.organizations["matches"] ?? $(get-content $companiesIndex -Raw | convertfrom-json -depth 99) ?? @()
# Match or create websites from domains data
if ($ITBoostData.ContainsKey("domains")){
    foreach ($row in $ITBoostData.domains.CSVData){
        if (-not [string]::IsNullOrEmpty(($row.organization))){
            $matchedCompany = Get-HuduCompanyFromName -CompanyName $company -HuduCompanies $huduCompanies  -existingIndex $($ITBoostData.organizations["matches"] ?? $null)
            $matchedCompany = $matchedCompany ?? (Get-HuduCompanies -Name $row.organization | Select-Object -First 1)
        } else {
            $matchedCompany = Select-Objectfromlist -message "which company has website $($row.name)?" -objects $(get-huducompanies) -allowNull $false
        }

        $notes = Get-NotesFromArray -notesInput $($row.notes ?? @())
        if ($matchedCompany -and -not $MatchedWebsite){
                $newWebsiteRequest=@{
                    Name = "$($($row.name -replace '[\\/]+$', '') -replace '^(?!https://)', 'https://')".Trim()
                    Notes=$notes; CompanyID=$targetCompany.id
                    DisableSSL='false'; DisableDNS='false'; DisableWhois='false'; EnableDMARC='true'; EnableDKIM='true'; EnableSPF='true';}            
            try {
                Write-Host "No match for website $($newWebsiteRequest.name), creating now"
                $newWebsite=New-HuduWebsite @newWebsiteRequest
            } catch {
                Write-Host "Error during company create $_"
            }
            if ($newWebsite){
                $ITBoostData.domains["matches"]+=@{
                    CsvRow=-1
                    ITBID=$row.id
                    Name=$row.name
                    HuduID=$newWebsite.id
                    HuduObject=$newWebsite
                    CompanyName=$row.organization
                    HuduCompanyId=$newWebsite.company_id
                    PasswordsToCreate=$($row.password ?? @())
                }
            }
        } else {
            Write-Host "Matched website $($matchedCompany.name) to $($row.name)"
            $ITBoostData.organizations["matches"]+=@{
                CompanyName=$row.organization
                CsvRow=$row.CsvRow
                ITBID=$row.id
                Name=$row.name
                HuduID=$MatchedWebsite.id
                HuduObject=$MatchedWebsite
                HuduCompanyId=$MatchedWebsite.company_id
                PasswordsToCreate=$($row.password ?? @())
            }            
        }
    }
} else {write-host "no websites in CSV! skipping."}
$allHuduWebsites=Get-HuduWebsites
