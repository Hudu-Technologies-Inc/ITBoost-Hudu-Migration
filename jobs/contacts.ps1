
if ($ITBoostData.ContainsKey("contacts")){
    $contactsLayout = $allHuduLayouts | Where-Object { ($(Get-NeedlePresentInHaystack -needle "contact" -haystack $_.name) -or $(Get-NeedlePresentInHaystack -needle "people" -Haystack $_.name)) } | Select-Object -First 1
    if (-not $contactsLayout){
        $contactsLayout=$(New-HuduAssetLayout -name "contacts" -Fields @(
            @{label        = 'first Name'; field_type   = 'Text'; show_in_list = 'true'; position     = 1},
            @{label        = 'Last Name'; field_type   = 'Text'; show_in_list = 'false';position     = 2},
            @{label        = 'Title'; field_type   = 'Text'; show_in_list = 'true'; position     = 3},
            @{label        = 'Contact Type'; field_type   = 'Text'; show_in_list = 'true'; position     = 4},
            @{label        = 'Location'; field_type   = 'AssetTag'; show_in_list = 'false';linkable_id  = $LocationLayout.ID; position     = 5},
            @{label        = 'Important'; field_type   = 'Text'; show_in_list = 'false';position     = 6},
            @{label        = 'Notes'; field_type   = 'RichText'; show_in_list = 'false';position     = 7},
            @{label        = 'Emails'; field_type   = 'RichText'; show_in_list = 'false';position     = 8},
            @{label        = 'Phones'; field_type   = 'RichText'; show_in_list = 'false';position     = 9}
        ) -Icon "fas fa-users" -IconColor "#ffffff" -Color "#6136ff" -IncludePasswords $true -IncludePhotos $true -IncludeComments $true -IncludeFiles $true).asset_layout
        $contactsLayout = Get-HuduAssetLayouts -id $contactsLayout.id
    }
    $contactsFields = $contactsLayout.fields
    $groupedContacts = $ITBoostData.contacts.CSVData | Group-Object { $_.organization } -AsHashTable -AsString
    $allHuduContacts = Get-HuduAssets -AssetLayoutId $contactsLayout.id

   foreach ($company in $groupedContacts.GetEnumerator().Name){
        $contactsForCompany=$groupedContacts["$company"]
        $matchedCompany = $huduCompanies | where-object {($_.name -eq $row.organization) -or [bool]$(Test-NameEquivalent -A $_.name -B $company)} | Select-Object -First 1
        $matchedCompany=$matchedCompany ?? $(Select-ObjectFromList -objects $huduCompanies -message "Which company to match for source company, named $company")
        write-host "$($contactsforcompany.count) locations for $company, hudu company id: $($matchedCompany.id)"
        foreach ($companyContact in $contactsForCompany){
            $matchedcontact = $allHuduContacts | where-object {$_.company_id -eq $matchedCompany.id -and 
                $($(Test-NameEquivalent -A $_.name -B $companyContact.name) -or
                 $(Test-NameEquivalent -A $companyContact.address_1 -B $($_.fields | where-object {$_.label -ilike "address"} | select-object -first 1).value))} | select-object -first 1
            if ($matchedcontact){
                Write-Host "Matched $($companyContact.name) to $($matchedcontact.name) for $($matchedCompany.name)"
                $ITBoostData.contacts["matches"]+=@{
                    CompanyName=$companyContact.organization
                    CsvRow=$companyContact.CsvRow
                    ITBID=$row.id
                    HuduID=$MatchedWebsite.id
                    HuduObject=$MatchedWebsite
                    HuduCompanyId=$matchedcontact.company_id
                    PasswordsToCreate=$($companyContact.password ?? @())
                }
            } else {
                $newcontactrequest=@{
                    Name="$($companyContact.first_name) $($companyContact.last_name)".Trim()
                    CompanyID = $matchedCompany.id
                    Fields=Build-FieldsFromRow -row $companyContact -layoutFields $contactsFields -companyId $matchedCompany.id
                    AssetLayoutId=$contactsLayout.id
                }
                $newcontactrequest.Fields | ConvertTo-Json -depth 99 | out-file "$($companyContact.id).json"

                try {
                    $newContact = New-Huduasset @newcontactrequest
                } catch {
                    write-host "Error creating location: $_"xw
                }
                if ($newContact){
                    $ITBoostData.contacts["matches"]+=@{
                        CompanyName=$companyContact.organization
                        CsvRow=$companyContact.CsvRow
                        ITBID=$companyContact.id
                        Name=$companyContact.name
                        HuduID=$newContact.id
                        HuduObject=$newContact
                        HuduCompanyId=$newContact.company_id
                        PasswordsToCreate=$($companyContact.password ?? @())
                    }            
                }
            }
        }
    }

} else {write-host "no contacts in CSV! skipping."} 