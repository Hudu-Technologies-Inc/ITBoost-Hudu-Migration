#boost

# additional_contact_items
# companyUuid
# contact_type
# first_name
# id
# last_name
# location
# notes
# organization
# password
# primary_email
# primary_phone
# relationship
# resource_id
# resource_type
# title
# types


# $hudu
# Status
# Email Address
# Office Phone number (DID)
# Cell Phone Number
# Preferred Communications
# Gender
# Title
# Department
# Accept Text?
# Workstation used


$ContactsMap = @{
primary_email = "Email Address"
contact_type="Contact Type"
primary_phone = "Office Phone number (DID)"
title = "Title"
}
$smooshToNotesProps = @("notes","resource_type","contact_type","relationship","additional_contact_items")
$SmooshPropsTo = "Notes"

#             @{label        = 'first Name'; field_type   = 'Text'; show_in_list = 'true'; position     = 1},
#             @{label        = 'Last Name'; field_type   = 'Text'; show_in_list = 'false';position     = 2},
#             @{label        = 'Title'; field_type   = 'Text'; show_in_list = 'true'; position     = 3},
#             @{label        = 'Contact Type'; field_type   = 'Text'; show_in_list = 'true'; position     = 4},
#             @{label        = 'Location'; field_type   = 'AssetTag'; show_in_list = 'false';linkable_id  = $LocationLayout.ID; position     = 5},
#             @{label        = 'Important'; field_type   = 'Text'; show_in_list = 'false';position     = 6},
#             @{label        = 'Notes'; field_type   = 'RichText'; show_in_list = 'false';position     = 7},
#             @{label        = 'Emails'; field_type   = 'RichText'; show_in_list = 'false';position     = 8},
#             @{label        = 'Phones'; field_type   = 'RichText'; show_in_list = 'false';position     = 9}

# Status
# Email Address
# Office Phone number (DID)`
# Cell Phone Number
# Preferred Communications
# Gender
# Title
# Department
# Accept Text?
# Workstation used
# Notes
# IP Address of Primary Computer

$LocationLayout = Get-HuduLayoutLike -labelSet @('location','branch','office location','site','building','sucursal','standort','filiale','vestiging','sede')

function Build-HuduContactIndex {
  [CmdletBinding()]
  param([Parameter(Mandatory)][object[]]$Contacts)

  $idx = @{
    ByName  = @{}
    ByEmail = @{}
    ByPhone = @{}
  }

  foreach($c in $Contacts){
    $cid = $c.company_id

    # Name index from First+Last if present, else asset.name
    $fn = Get-HuduFieldValue -Asset $c -Labels $FIRSTNAME_LABELS
    $ln = Get-HuduFieldValue -Asset $c -Labels $LASTNAME_LABELS
    $nameKey = if ($fn -or $ln) { Normalize-Name "$fn $ln" } else { Normalize-Name $c.name }
    if ($nameKey) {
      $k = "$cid|$nameKey"
      if (-not $idx.ByName.ContainsKey($k)) { $idx.ByName[$k] = @() }
      $idx.ByName[$k] += $c
    }

    # Email index
    $em = Get-HuduFieldValue -Asset $c -Labels $EMAIL_LABELS
    $emKey = Normalize-Email $em
    if ($emKey) {
      $k = "$cid|$emKey"
      if (-not $idx.ByEmail.ContainsKey($k)) { $idx.ByEmail[$k] = @() }
      $idx.ByEmail[$k] += $c
    }

    # Phone index
    $ph = Get-HuduFieldValue -Asset $c -Labels $PHONE_LABELS
    $phKey = Normalize-Phone $ph
    if ($phKey) {
      $k = "$cid|$phKey"
      if (-not $idx.ByPhone.ContainsKey($k)) { $idx.ByPhone[$k] = @() }
      $idx.ByPhone[$k] += $c
    }
  }

  return $idx
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
   $contactIndex    = if ($allHuduContacts.count -gt 0) {Build-HuduContactIndex -Contacts $allHuduContacts} else {@{    ByName  = @{}
    ByEmail = @{}
    ByPhone = @{}}}
    foreach ($company in $groupedContacts.Keys) {
        write-host "starting $company"
        $contactsForCompany = $groupedContacts[$company]
        $matchedCompany = Get-HuduCompanyFromName -CompanyName $company -HuduCompanies $huduCompanies
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
                # build fields
                $fields = @()
                if ($false -eq $UseSimpleMap){
                    $fields=Build-FieldsFromRow -row $companyContact -layoutFields $contactsFields -companyId $matchedCompany.id
                
                } else {


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

                    # smoosh extra props to notes
                    $notes = ""
                    foreach ($prop in $smooshToNotesProps){
                        if (-not [string]::IsNullOrWhiteSpace($companyContact.$prop)){
                            $notes="$notes`n$($prop): $($companyContact.$prop)"
                        }
                    }
                    if (-not [string]::IsNullOrWhiteSpace($notes)){
                        $fields+=@{"$SmooshPropsTo" ="$notes`n$contactNotes"}
                    }
                }
                # add all fields
                $newcontactrequest['Fields'] = $fields


                


                    try {
                        $newContact = New-Huduasset @newcontactrequest
                    } catch {
                        write-host "Error creating location: $_"
                    }
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