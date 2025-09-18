# Match or create websites from domains data
if ($ITBoostData.ContainsKey("domains")){
    foreach ($row in $ITBoostData.domains.CSVData){
        if ($allHuduWebsites -and $allHuduWebsites.count -gt 1){
            $MatchedWebsite=$allHuduWebsites | where-object {$_ -and -not [string]::IsNullOrWhiteSpace($_.name) -and $_.name -eq $row.name -or[bool]$(Test-NameEquivalent -A "$(Get-NormalizedWebsiteHost -Website "$($_.name)")" -B "$(Get-NormalizedWebsiteHost "$($row.name)")")}
        } else {$MatchedWebsite = $null}
        $targetCompany = $($ITBoostdata.organizations.Matches | where-object {$_.CompanyName -ilike "*$($row.'organization')*"} | Select-Object -First 1).HuduCompany
        
        # if website exists, match company by who owns website in Hudu
        if (-not $targetCompany){
            if ($matchedWebsite){
                $matchedCompany = $huduCompanies | where-object {$_.id -eq $matchedwebsite.company_id}
            } else {
                $targetCompany = Select-ObjectFromList -message "Which company does this website belong to?" -objects $huduCompanies -allownull $false
            }
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
