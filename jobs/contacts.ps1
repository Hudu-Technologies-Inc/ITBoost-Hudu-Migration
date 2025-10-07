$ContactsMap = @{
first_name="First Name"
last_name="Last Name"
contact_type="Contact Type"
location="Location"
primary_phone = "Phones"
primary_email = "Email"
notes = "Notes"
title = "Title"

}


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
    try {
        $allHuduContacts = Get-HuduAssets -AssetLayoutId $contactsLayout.id
    } catch {
        $allHuduContacts=@()
    }
   $contactIndex    = Build-HuduContactIndex -Contacts $allHuduContacts    
    foreach ($company in $groupedContacts.Keys) {
        write-host "starting $company"
        $contactsForCompany = $groupedContacts[$company]
        $matchedCompany = $huduCompanies | where-object {
            ($_.name -eq $company) -or
            [bool]$(Test-NameEquivalent -A $_.name -B "*$($company)*") -or
            [bool]$(Test-NameEquivalent -A $_.nickname -B "*$($company)*")} | Select-Object -First 1
        $matchedCompany = $huduCompanies | Where-Object {
            $_.name -eq $company -or
            (Test-NameEquivalent -A $_.name -B "*$company*") -or
            (Test-NameEquivalent -A $_.nickname -B "*$company*")
            } | Select-Object -First 1

            $matchedCompany = $matchedCompany ?? (Get-HuduCompanies -Name $company | Select-Object -First 1)

        if (-not $matchedCompany -or -not $matchedCompany.id -or $matchedCompany.id -lt 1) { continue }
        foreach ($companyContact in $contactsForCompany){
            $matchedContact = Find-HuduContact `
            -CompanyId  $matchedCompany.id `
            -FirstName  $companyContact.first_name `
            -LastName   $companyContact.last_name `
            -Email      $companyContact.primary_email `
            -Phone      $companyContact.primary_phone `
            -Index      $contactIndex

            # Optional fallback to API search by name if still null:
            if (-not $matchedContact -and ($companyContact.first_name -or $companyContact.last_name)) {
            $qName = ("{0} {1}" -f $companyContact.first_name, $companyContact.last_name).Trim()
            $matchedContact = Get-HuduAssets -AssetLayoutId $contactsLayout.id -CompanyId $matchedCompany.id -Name $qName |
                                Select-Object -First 1
            }
            if ($matchedcontact){
                    $humanName = ("{0} {1}" -f $companyContact.first_name, $companyContact.last_name).Trim()
                    Write-Host "Matched $humanName to $($matchedcontact.name) for $($matchedCompany.name)"

                    # ensure the array exists once
                    if (-not $ITBoostData.contacts.ContainsKey('matches')) { $ITBoostData.contacts['matches'] = @() }

                    $ITBoostData.contacts['matches'] += @{
                        CompanyName      = $companyContact.organization
                        CsvRow           = $companyContact.CsvRow
                        ITBID            = $companyContact.id
                        Name             = $humanName
                        HuduID           = $matchedcontact.id
                        HuduObject       = $matchedcontact
                        HuduCompanyId    = $matchedcontact.company_id
                        PasswordsToCreate= ($companyContact.password ?? @())
                    }
                    continue

            } else {
                $newcontactrequest=@{
                    Name="$($companyContact.first_name) $($companyContact.last_name)".Trim()
                    CompanyID = $matchedCompany.id
                    AssetLayoutId=$contactsLayout.id
                }
                if ($false -eq $UseSimpleMap){
                    $newcontactrequest["Fields"]=Build-FieldsFromRow -row $companyContact -layoutFields $contactsFields -companyId $matchedCompany.id
                
                } else {
                    $fields = @()
                    foreach ($key in $ContactsMap.Keys | where-object {$_ -ne "location"}) {
                        # pull value from CSV row
                        $rowVal = $companyContact.$key ?? $null
                        if ($null -eq $rowVal) { continue }
                        $rowVal = [string]$rowVal
                        if ([string]::IsNullOrWhiteSpace($rowVal)) { continue }

                        $huduField = $ContactsMap[$key]
                        $fields+=@{ $($huduField) = $rowVal.Trim() }
                        }

                        if (-not $([string]::IsNullOrWhiteSpace($companyContact.location))){
                                $matchedlocation = Get-HuduAssets -AssetLayoutId ($LocationLayout.id ?? 2) -CompanyId $matchedCompany.id |
                                                Where-Object { Test-NameEquivalent -A $_.name -B $companyContact.location } |
                                                Select-Object -First 1
                                               if ($matchedlocation){
                                $fields+=@{"Location" = "[$($matchedlocation.id)]"}
                            }
                        }
                        $newcontactrequest["Fields"]=$fields

                    }



                }


                try {
                    $newContact = New-Huduasset @newcontactrequest
                } catch {
                    write-host "Error creating location: $_"
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
 else {write-host "no contacts in CSV! skipping."} 

foreach ($dupecontact in $(Get-HuduAssets -AssetLayoutId $contactsLayout.id | Group-Object { '{0}|{1}' -f $_.company_id, (($_.'name' -as [string]).Trim() -replace '\s+',' ').ToLower() } | Where-Object Count -gt 1 | ForEach-Object { $_.Group | Sort-Object id | Select-Object -Skip 1 } )){
    if ($dupecontact.archived -eq $true){continue}
    Remove-HuduAsset -id $dupecontact.id -CompanyId $dupecontact.company_id -Confirm:$false}