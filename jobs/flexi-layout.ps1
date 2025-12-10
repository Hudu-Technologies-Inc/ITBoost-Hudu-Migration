# reset all possible user-mapping inputs
$smooshLabels = @(); $smooshToDestinationLabel = $null; $flexisMap = @{}; $flexiFields = @(); $jsonSourceFields = @(); $nameField = "Name"; $givenICon = $null; $PasswordsFields = @(); $contstants = @(); $listMaps = @{}; $tagMaps=@{}; $createNewItemsForLists = $false;
$DocFields = @(); $LinkAsPasswords = @();
$standardlayouts = @('locations','configurations','contacts','domains','organizations','passwords')

# Choose next layout to target, a template will be generated for you to fill out mappings
# $completedFlexlayouts = $completedFlexlayouts ?? @()
$completedFlexlayouts = @()
$flexiChoices = $ITBoostData.Keys | Where-Object { $_.ToLower() -notin $standardlayouts -and $_.ToLower() -notin  $completedFlexlayouts} | Sort-Object -CaseSensitive
if (-not $flexiChoices -or $flexiChoices.count -eq 0){exit 0}
$sourceProperty = Select-ObjectFromList -objects $flexiChoices -message "Which Flexi-Layout to process next?" -allowNull $false

$usingExistingLayout = $($(Select-ObjectFromList -objects @("Yes","No") -message "Do you already have a Hudu Asset Layout for $sourceProperty created?" -allowNull $false) -eq "Yes")
$existingLayout = $null
if ($true -eq $usingExistingLayout){
    $existingLayout = Select-ObjectFromList -objects (Get-HuduAssetLayouts | Sort-Object Name -CaseSensitive) -message "Select the existing layout for $sourceProperty" -allowNull $false
    $existingLayout = $existingLayout.asset_layout ?? $existingLayout
    $FlexiLayoutName = $existingLayout.name
    write-host "Mapping source property $sourceProperty to existing Hudu layout $FlexiLayoutName"
} else {
    $FlexiLayoutName = $sourceProperty
}
Read-Host "Migrating $($sourceProperty) to $(if ($true -eq $usingExistingLayout) {'existing'} else {'new'}) layout, called $FlexiLayoutName. Press enter to continue or CTL+C to exit now."

$completedFlexlayouts+=$FlexiLayoutName
$flexiTemplate = "$project_workdir\mappings-$(get-safefilename $FlexiLayoutName).ps1"

if ($true -eq $usingExistingLayout){
    write-host "generating mapping template for existing layout $($existingLayout.name)"
    New-GeneratedTemplateFromHuduLayout -HuduLayout $existingLayout -ITboostdata $ITBoostData -sourceProperty $sourceProperty -outFile $flexiTemplate
} else {
    write-host "generating mapping template for New or Newly-Created layout $($FlexiLayoutName)"
    New-GeneratedTemplateFromFlexiHeaders -ITboostdata $ITBoostData -FlexiLayoutName $FlexiLayoutName -outFile $flexiTemplate
}
# Copy-Item "$project_workdir\jobs\flexi-map.ps1" $flexiTemplate -Force
Read-Host "Please fill out mappings in $flexiTemplate and ensure its completion. then, press enter."
$successRead = $false
while ($true) {
    try {
        . $flexiTemplate
        $successRead = $true
    } catch {
        Read-Host "Error reading your mappings file: $_ ($flexiTemplate); ensure its completion. then, press enter to try again."
    }
    if ($successRead) {break}
}
if ($smooshLabels -and $smooshLabels.count -gt 0){
    write-host "smooshing $($smooshLabels.count) fields into $smooshToDestinationLabel"
}



# load companies index if available
$ITBoostData.organizations["matches"] = $ITBoostData.organizations["matches"] ?? $(get-content $companiesIndex -Raw | convertfrom-json -depth 99) ?? @()
$LocationLayout = Get-HuduAssetLayouts | Where-Object { ($(Get-NeedlePresentInHaystack -needle "location" -haystack $_.name) -or $(Get-NeedlePresentInHaystack -needle "locations" -Haystack $_.name)) } | Select-Object -First 1

if (-not $ITBoostData.ContainsKey("$sourceProperty")){write-host "No data for $sourceproperty"; exit 1}
if ($usingExistingLayout -and $existingLayout) {
    $flexisLayout = $existingLayout.asset_layout ?? $existingLayout
} else {    
    $flexisLayout = $allHuduLayouts | Where-Object { $_.name -eq $FlexiLayoutName } | Select-Object -First 1
}
$flexisLayout = $flexisLayout.asset_layout ?? $flexisLayout
if (-not $flexisLayout){
    $GivenIcon = try {$($FontAwesomeMap[$($FontAwesomeMap.Keys | Where-Object {$_ -ilike "*$sourceProperty*" -or $_ -ilike "*$FlexiLayoutName*"} | select-object -first 1)])} catch {"fas fa-boxes"}
    try {
    $flexisLayout = (New-HuduAssetLayout -name "$FlexiLayoutName" -Fields $FlexiFields -IncludePasswords $true -IncludePhotos $true -IncludeComments $true -IncludeFiles $true -color "#6136ff" -icon_color "#ffffff"  -Icon $givenICon)
    # re-fetch to get proper shape
    $flexisLayout = get-huduassetlayouts -name $FlexiLayoutName | select-object -first 1
    $flexisLayout = $flexisLayout.asset_layout ?? $flexisLayout
    } catch {
        write-host "Error creating flexi layout: $_"
    }
    set-huduassetlayout -id $flexisLayout.id -active $true | Out-Null 
    
    write-host "Created new flexi layout $($flexisLayout.name) with id $($flexisLayout.id) and icon $($GivenIcon)"
    
    $flexisLayout = Get-HuduAssetLayouts -id $flexisLayout.id
}
$flexisFields = $flexisLayout.fields
$dateFields = $flexisFields | Where-Object { $_.field_type -eq "Date" } | Select-Object -ExpandProperty label
$NumberFields = $flexisFields | Where-Object { $_.field_type -eq "Number" } | Select-Object -ExpandProperty label
$WebsiteFields = $flexisFields | Where-Object { $_.field_type -eq "Website" } | Select-Object -ExpandProperty label
$ListFields = $flexisFields | Where-Object { $_.field_type -eq "ListSelect" }
$tagFields = $flexisFields | Where-Object { $_.field_type -eq "AssetTag" }
foreach ($tagField in $tagFields){
    $al = $(get-huduassetlayouts -id $tagfield.linkable_id)
    $al = $al.asset_layout ?? $al
    $tagMaps["$($tagfield.label)"] = $al
}

foreach ($listField in $ListFields){
    $ListMaps["$($listField.label)"]=$(get-hudulists -id $listfield.list_id)
}


$SmooshFieldIsRichTExt = [bool]$(($flexisFields | Where-Object { $_.label -eq $($smooshToDestinationLabel) } | Select-Object -First 1).field_type -ieq "RichText") ?? $true
Write-Host "Smooshable dest is $(if ($true -eq $SmooshFieldIsRichTExt) {"RichText"} else {"Text"})"

$groupedflexis = $ITBoostData.$sourceProperty.CSVData | Group-Object { $_.organization } -AsHashTable -AsString

try {
    $allHuduflexis = Get-HuduAssets -AssetLayoutId $flexisLayout.id
} catch {
    $allHuduflexis=@()
}
foreach ($company in $groupedflexis.Keys) {
    write-host "starting $company"
    $RelationsForAsset = @()
    $flexisForCompany = $groupedflexis[$company]
    $matchedCompany = Get-HuduCompanyFromName -CompanyName $company -HuduCompanies $huduCompanies  -existingIndex $($ITBoostData.organizations["matches"] ?? $null)
    if (-not $matchedCompany -or -not $matchedCompany.id -or $matchedCompany.id -lt 1) { continue }
    foreach ($companyflexi in $flexisForCompany){
        $matchedflexi = Get-HuduAssets -AssetLayoutId $flexisLayout.id -CompanyId $matchedCompany.id -Name $($companyflexi.$nameField ?? $companyFlexi.name) |
                            Select-Object -First 1
    
        if ($matchedflexi){continue} 
        $GivenName = $null
        $AltLabel = $nameField -replace "_"," "                
        $GivenName = $($companyflexi.$nameField ?? $companyflexi.$AltLabel ?? $companyflexi.name)
        if ($jsonSourceFields -contains $nameField.ToLowerInvariant()) {
            $GivenName = SafeDecode $GivenName
            $GivenName = $GivenName.value ?? $GivenName.text ?? $GivenName
        }
        $GivenName = $(if ([string]::IsNullOrWhiteSpace($GivenName)) { $($companyflexi.path ?? $companyflexi.host ?? $companyflexi.share_name) } else { $GivenName })
        $GivenName = $(if ([string]::IsNullOrWhiteSpace($GivenName)) { "Unnamed $sourceProperty" } else { $GivenName })
        $matchedflexi = Get-HuduAssets -AssetLayoutId $flexisLayout.id -CompanyId $matchedCompany.id -Name $GivenName | Select-Object -First 1                
        if ($matchedflexi){
            write-host "Skipping creation of $GivenName as it already exists."
            continue
        }
        
        $newflexirequest=@{
            Name=$givenName
            CompanyID = $matchedCompany.id
            AssetLayoutId=$flexisLayout.id
        }
        # build fields from non-empty mapped values
        $fields = $()
        foreach ($key in $flexisMap.Keys | where-object {$_ -ne "location" -and $smooshLabels -notcontains $_ -and $PasswordsFields -notcontains $_}) {

            $rowVal = $null
            $huduField = $null
            $setVal = $null   # ← reset per field

            $rowVal = Get-ValueFromCSVKeyVariants -Row $companyflexi -Label $key
            if ($null -eq $rowVal) { continue }
            $rowVal = [string]$rowVal
            if ([string]::IsNullOrWhiteSpace($rowVal)) { continue }


            if ($jsonSourceFields -contains $key) {
                $rowVal = SafeDecode $rowVal
                $rowVal = $rowVal.value ?? $rowVal.text ?? $rowVal
            }

            $huduField = $flexisMap[$key]
            Write-Host "Hudufield is $hudufield for $key"

            $MatchedList = if ($ListMaps.ContainsKey("$huduField")) { $ListMaps["$huduField"] } else { $null }
            $MatchedTagfield = if ($tagMaps.ContainsKey("$huduField")) { $tagMaps["$huduField"] } else { $null }
            if ($null -ne $MatchedTagfield) {
                $matchedAsset=$null;
                $assetDeserialized = SafeDecode $rowVal
                $AssetName = $assetDeserialized.value ?? $assetDeserialized.text ?? $rowVal
                if ([string]::IsNullOrWhiteSpace($AssetName)){continue}
                $matchedAsset = Get-HuduAssets -CompanyId $matchedCompany.id -AssetLayoutId $MatchedTagfield.id -name $assetName | Select-Object -first 1
                $matchedAsset = $matchedAsset.asset ?? $matchedAsset
                if ($null -eq $matchedAsset -or $null -eq $matchedasset.id){continue}
                $setVal = "[$($matchedAsset.id)]"
            } elseif ($null -ne $MatchedList) {
                $Listoptions = $MatchedList.list_items
                Write-Host "Comparing row val $rowVal to available List options $($Listoptions.name -join ', ')" -ForegroundColor Green

                $bestChoice = ChoseBest-ByName -choices $Listoptions -name $rowVal

                if (-not $bestChoice.name -or [string]::IsNullOrWhiteSpace($bestChoice.name)) {
                    if (-not $createNewItemsForLists) { continue }

                    Write-Host "Adding new list option: $rowval to listitems for $($matchedList.Name)"
                    $NewOptions = $Listoptions.name
                    $NewOptions += $rowVal
                    Set-HuduList -id $MatchedList.id -name $MatchedList.Name -listItems $NewOptions
                    $ListMaps["$huduField"] = Get-HuduLists -id $MatchedList.id
                    Write-Host "Updated list cache with new item, $rowVal"
                    $setVal = $rowVal
                } else {
                    Write-Host "normalizing rowval $rowVal to best-fit in list $($bestChoice.name)"
                    $setVal = $bestChoice.name
                }

            } elseif ($dateFields -contains "$huduField".ToLowerInvariant()) {
                $setVal = Get-CoercedDate -inputDate $rowVal
            } elseif ($NumberFields -contains "$huduField".ToLowerInvariant()) {
                $setVal = Get-CastIfNumeric -Value $rowVal
                $setVal = [int]([regex]::Match($rowVal, '\d+').Value)
            } elseif ($WebsiteFields -contains "$huduField".ToLowerInvariant()) {
                $setVal = Normalize-WebURL -Url $rowVal
                if ([string]::IsNullOrEmpty($setVal)){continue}
            } else {
                $setVal = $rowVal
            }

            if ([string]::IsNullOrWhiteSpace([string]$setVal)) { continue }

            $fields += @{ $huduField = "$setVal".Trim() }
        }

        if (-not $([string]::IsNullOrWhiteSpace($companyflexi.location))){
            $locationDeserialized = SafeDecode $companyflexi.location
            $locationDeserialized = $locationDeserialized.value ?? $locationDeserialized.text ?? $locationDeserialized.location ?? $locationDeserialized
            if (-not $([string]::IsNullOrWhiteSpace($locationDeserialized))){
            $matchedlocation = Get-HuduAssets -AssetLayoutId ($LocationLayout.id ?? 2) -CompanyId $matchedCompany.id |
                                Where-Object { test-equiv -A $_.name -B $locationDeserialized } |
                                Select-Object -First 1
                                if ($matchedlocation){
                $fields+=@{"Location" = "[$($matchedlocation.id)]"}
                }
            }
        }
        $SmooshedNotes = @()
    foreach ($smooshLabel in $smooshLabels){
        $rowVal = $null
        $rowVal = Get-ValueFromCSVKeyVariants -Row $companyflexi -Label $smooshLabel
        $rowVal = [string]$rowVal
        if ([string]::IsNullOrWhiteSpace($rowVal)) { continue }
        if ($key -eq "ITBNotes"){
            $rowval= $(try {$(safedecode $($(SafeDecode $rowval) -as [string])) -replace "; ","`n"} catch {continue})

        }

        if ($jsonSourceFields -contains $smooshLabel) {
            $rowVal = SafeDecode $rowVal
            $rowVal = $rowVal.value ?? $rowVal.text ?? $rowVal
        }
        
        if ($true -eq $SmooshFieldIsRichTExt){
            $SmooshedNotes+= "$($smooshLabel)-<br>$("$($rowVal)".Trim())"
        } else {
            $SmooshedNotes+= "$($smooshLabel)- $("$($rowVal)".Trim())"
        }
    }
    
    if ($SmooshedNotes.Count -gt 0){
        write-host "$($SmooshedNotes.Count) fields smooshed into $smooshToDestinationLabel for $GivenName as $(if ($true -eq $SmooshFieldIsRichTExt) {"RichText"} else {"Text"})"
        $smooshedContent = if ($true -eq $SmooshFieldIsRichTExt) {$SmooshedNotes -join "<br><hr><br>"} else { $SmooshedNotes -join "`n`n" }
        $fields+=@{ $smooshToDestinationLabel = "$smooshedContent".Trim() }
    }
    foreach ($constant in $contstants){
        $fields+=$constant
    }


    $newflexirequest["Fields"]=$fields

    $newFlexi = $null
    try {
        $newflexi = New-Huduasset @newflexirequest
        $newFlexi = $newflexi.asset ?? $newflexi

    } catch {
        write-host "Error creating $FlexiLayoutName from $sourceProperty- $_"
    }
    if ($null -ne $newFlexi){
        foreach ($doc in $DocFields){
            $DocName = Safedecode $companyflexi.$doc
            $DocName = $DocName.name ?? $DocName.value ?? $null
            if ([string]::IsNullOrWhiteSpace($DocName)){continue}
            $article = $null
            $article = Get-HuduArticles -CompanyId $matchedCompany.id -name $DocName | Select-Object -first 1
            $article = $article.article ?? $article
            if ($null -eq $article -or $null -eq $article.id ){continue}
            New-HuduRelation -FromableType "Asset" -ToableType "Article" -FromableID $newFlexi.id -ToableID $article.id
        }
        foreach ($related in $RelateditemFields) {
            $itemName = Safedecode $companyflexi.$related
            $itemName = $itemName.name ?? $itemName.value ?? $null
            if ([string]::IsNullOrWhiteSpace($itemName)){continue}
            $asset = $null
            $related = Get-HuduAssets -CompanyId $matchedCompany.id -name $itemName | where-object {$_.id -ne $newFlexi.id}
            foreach ($r in $related){
                $asset = $r.asset ?? $asset
                if ($null -eq $asset -or $null -eq $asset.id ){continue}
                New-HuduRelation -FromableType "Asset" -ToableType "Asset" -FromableID $newFlexi.id -ToableID $asset.id
            }
        }
        foreach ($eligiblepassField in $LinkAsPasswords) {
            $flexipass = Safedecode $companyflexi.$eligiblepassField
            $flexipass = $flexipass.name ?? $flexipass.value ?? $flexipass
            if ([string]::IsNullOrWhiteSpace($flexipass)){write-host "empty pass $($companyflexi.$eligiblepassField)"; continue}

            $passrequest = @{CompanyId=$matchedCompany.id; Name = "$givenName $eligiblepassField"; PasswordableType = "Asset"; PasswordableId=$newFlexi.id; Password=$flexipass; PasswordType="$($existingLayout.name) Password"}
            $userNameKey = $($companyflexi.keys | Where-Object {$_ -ilike "*user*" -or $_ -ilike "*username*"} | Select-Object -first 1)
            $userNameKey = $($companyflexi.keys | Where-Object {$_ -ilike "*user*" -or $_ -ilike "*username*"} | Select-Object -first 1)
            if (-not [string]::IsNullOrEmpty($userNameKey)){
                $userName = Get-ValueFromCSVKeyVariants -Row $companyflexi -Label $userNameKey
                if (-not [string]::IsNullOrEmpty($userName)){$passrequest["UserName"]=$userName}
            }
            $existingpass = get-hudupasswords -CompanyId $matchedCompany.id -name $givenName | Select-Object -first 1
            $existingpass=$existingpass.asset_password ?? $existingpass
            if ($null -ne $existingpass -and $null -ne $existingpass.id){$passrequest["Id"]=$existingpass.id}
            if ($passrequest.ContainsKey("Id") -and $null -ne $passrequest.id){
                Set-HuduPassword @passrequest
            } else {New-HuduPassword @passrequest}
        }

    }


    
    }
}
