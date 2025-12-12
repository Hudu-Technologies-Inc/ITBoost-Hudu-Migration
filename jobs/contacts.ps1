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

# additional_contact_items
# companyUuid
# contact_type
# CsvRow
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

$LocationLayout = Get-HuduAssetLayouts | Where-Object { ($(Get-NeedlePresentInHaystack -needle "location" -haystack $_.name) -or $(Get-NeedlePresentInHaystack -needle "locations" -Haystack $_.name)) } | Select-Object -First 1

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


# load companies index if available
$ITBoostData.organizations["matches"] = $ITBoostData.organizations["matches"] ?? $(get-content $companiesIndex -Raw | convertfrom-json -depth 99) ?? @()

if ($ITBoostData.ContainsKey("contacts")){
    if (-not $ITBoostData.contacts.ContainsKey('matches')) { $ITBoostData.contacts['matches'] = @() }
    $contactsLayout = $allHuduLayouts | Where-Object { ($(Get-NeedlePresentInHaystack -needle "contact" -haystack $_.name) -or $(Get-NeedlePresentInHaystack -needle "people" -Haystack $_.name)) } | Select-Object -First 1
    if (-not $contactsLayout){
        $StatusList = Get-HuduLists | Where-Object {$_.name -ieq "People Status" -or $_.name -ieq "Contact Status"} | Select-Object -First 1
        $statusList = $StatusList ?? $(new-hudulist -name "People Status" -items @("ACTIVE", "INACTIVE (DO NOT SERVICE)", "Leave", "Terminated", "Onboarding"))
        $StatusList = $StatusList.list ?? $StatusList

        $contactList = Get-HuduLists | Where-Object {$_.name -ieq "People Preferred Communications" -or $_.name -ieq "Preferred Communications"} | Select-Object -First 1
        $contactList = $contactList ?? $(new-hudulist -name "People Preferred Communications" -items @("Office Phone","Cell Phone","Email","Text"))
        $contactList = $contactList.list ?? $contactList

        $genderList = Get-HuduLists | Where-Object {$_.name -ilike "Gender" -or $_.name -ilike "Sex"} | Select-Object -First 1
        $genderList = $genderList ?? $(new-hudulist -name "Gender" -items @("Male","Female","Non-Binary","Other","Prefer Not to Say"))
        $genderList = $genderList.list ?? $genderList        

        $contactsLayout=$(New-HuduAssetLayout -name "contacts" -Fields @(
        @{label="Status";   show_in_list=$false;   field_type="ListSelect";required=$false;   multiple_options=$true;list_id=$StatusList.id;   position=1},
        @{label="Email Address";   show_in_list=$false;   field_type="Email";required=$false;   hint="";   position=2},
        @{label="Office Phone number (DID)";   show_in_list=$false;   field_type="Phone";required=null;   hint="";   position=4},
        @{label="Cell Phone Number";   show_in_list=$false;   field_type="Phone";required=$false;   hint="";   position=5},
        @{label="Preferred Communications";   show_in_list=$false;   field_type="ListSelect";required=$false;   hint="";   multiple_options=$true;list_id=$contactList.id;   position=6},
        @{label="Gender";   show_in_list=$false;   field_type="ListSelect";required=$false;   hint="";   multiple_options=$true;list_id=$genderList.id;   position=7},
        @{label="Title";   show_in_list=$false;   field_type="Text";required=$false;   hint="Title / Job Description";   position=8},
        @{label="Accept Text?";   show_in_list=$false;   field_type="CheckBox";required=$false;   hint="Can we text the user?";   position=10},
        @{label="Workstation used";   show_in_list=$false;   field_type="Text";required=$false;   hint="What workstation is used?";   position=11},
        @{label="Notes";   show_in_list=$false;   field_type="RichText";required=$false;   hint="";   position=12},
        @{label="IP Address of Primary Computer";   show_in_list=$false;   field_type="Website";required=$false;   hint="";   linkable_id=5;   position=13},
        @{label="Location";   show_in_list=$true;   field_type="AssetTag";required=$false;   hint="";   linkable_id=$LocationLayout.id;   multiple_options=$false;list_id=4;   position=14}
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
        if ([string]::IsNullOrEmpty($company)){continue}
        write-host "starting $company"
        $contactsForCompany = $groupedContacts[$company]
        $matchedCompany = $null
        $matchedCompany = Get-HuduCompanyFromName -CompanyName $company -HuduCompanies $huduCompanies  -existingIndex $($ITBoostData.organizations["matches"] ?? $null)
        if ($null -eq $matchedCompany -or $null -eq $matchedcompany.id -or $matchedcompany.id -lt 1) {write-host "skipping $company due to no match"; continue;}
        foreach ($companyContact in $contactsForCompany){
            $matchedcontact = $null
            $matchedContact = Find-HuduContact `
                -CompanyId  $matchedCompany.id `
                -FirstName  $companyContact.first_name `
                -LastName   $companyContact.last_name `
                -Email      $companyContact.primary_email `
                -Phone      $companyContact.primary_phone `
                -Index      $contactIndex

            # fallback to API search by name if still null:
            if (-not $matchedContact -and ($companyContact.first_name -or $companyContact.last_name)) {
                $qName = ("{0} {1}" -f $companyContact.first_name, $companyContact.last_name).Trim()
                $matchedContact = Get-HuduAssets -AssetLayoutId $contactsLayout.id -CompanyId $matchedCompany.id -Name $qName |
                                    Select-Object -First 1
                $matchedcontact = $matchedContact.asset ?? $matchedContact
            }
            if ($null -ne $matchedcontact){
                $humanName = ("{0} {1}" -f $companyContact.first_name, $companyContact.last_name).Trim()
                Write-Host "Matched $humanName to $($matchedcontact.name) for $($matchedCompany.name)"

                # ensure the array exists once
                $ITBoostData.contacts['matches'] += @{
                    CompanyName      = $companyContact.organization
                    ITBID            = $companyContact.id
                    Name             = $humanName
                    HuduID           = $matchedcontact.id
                    HuduObject       = $matchedcontact
                    HuduCompanyId    = $matchedcontact.company_id
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
                foreach ($key in $ContactsMap.Keys | where-object {$_ -ne "location"} ) {
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
                                        Where-Object { test-equiv -A $_.name -B $companyContact.location } |
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
                $newContact = $null
                $newContact = New-Huduasset @newcontactrequest
                $newContact = $newContact.asset ?? $newContact
                write-host "Created new contact $($newContact.name) with ID $($newContact.id) for company $($matchedCompany.name)"
            } catch {
                write-host "Error creating location: $_"
            }
            
            if ($null -ne $newContact){
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
 else {write-host "no contacts in CSV! skipping."} 

# foreach ($dupecontact in $(Get-HuduAssets -AssetLayoutId $contactsLayout.id | Group-Object { '{0}|{1}' -f $_.company_id, (($_.'name' -as [string]).Trim() -replace '\s+',' ').ToLower() } | Where-Object Count -gt 1 | ForEach-Object { $_.Group | Sort-Object id | Select-Object -Skip 1 } )){
#     if ($dupecontact.archived -eq $true){continue}
#     Remove-HuduAsset -id $dupecontact.id -CompanyId $dupecontact.company_id -Confirm:$false}

$ITBoostData.contacts["matches"] | convertto-json -depth 99 | out-file $($(join-path $debug_folder -ChildPath "MatchedContacts.json")) -Force
