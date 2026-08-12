function Clear-DupeDocuments {
    param ([array]$HuduArticles, [array]$huduUploads)

    $HuduArticles |
        Group-Object { '{0}|{1}' -f ($_.company_id ?? -1), (([string]$_.name).Trim() -replace '\s+',' ').ToLower() } |
        Where-Object Count -gt 1 |
        ForEach-Object {
        $_.Group |
            Sort-Object @{Expression={ 
                $d=$_.updated_at ?? $_.created_at; try{[datetime]$d}catch{Get-Date '1900-01-01'} }; Descending=$true
            }, @{
                Expression='id'; Descending=$true
            } | Select-Object -Skip 1
        } |
        Where-Object { $_.archived -ne $true } |
        ForEach-Object { Remove-HuduArticle -Id $_.id -Confirm:$false }

    $huduUploads |
        Group-Object {
            $uid = $_.uploadable_id
            $utype = $_.uploadable_type
            $nm  = (([string]$_.name).Trim() -replace '\s+',' ').ToLower()
            { "{0}|{1}|{2}" -f $uid,$utype,$nm }
        }  | Where-Object Count -gt 1 | ForEach-Object {
            $_.Group |  Sort-Object @{Expression={
                $d=$_.created_at ?? $_.created_date; try{[datetime]$d}catch{Get-Date '1900-01-01'} }; Descending=$true
            }, @{Expression='id'; Descending=$true} | Select-Object -Skip 1
         } | ForEach-Object { Invoke-HuduRequest -Method delete -Resource "/api/v1/uploads/$($_.id)" }
}

function remove-dupeassets {
    param ([bool]$dryRun = $true)
    write-host "RUNNING IN $($dryRun -eq $true ? 'DRY RUN' : 'LIVE') MODE. NO ASSETS WILL BE REMOVED IN DRY RUN MODE." -ForegroundColor Yellow

$candidates =
    Get-HuduAssets |
    Group-Object {
        '{0}|{1}|{2}' -f (
            $_.company_id ?? -1
        ), (
            $_.asset_layout_id ?? -1
        ), (
            (([string]$_.name).Trim() -replace '\s+', ' ').ToLower()
        )
    } |
    Where-Object Count -gt 1 |
    ForEach-Object {
        $sorted = $_.Group | Sort-Object `
            @{ Expression = {
                    $d = $_.created_at ?? $_.updated_at;
                    try { [datetime]$d } catch { Get-Date '1900-01-01' }
                }; Descending = $false
            },
            @{ Expression = 'id'; Descending = $false }

        $keeper = $sorted | Select-Object -First 1
        $dupes  = $sorted | Select-Object -Skip 1

        foreach ($d in $dupes) {
            [pscustomobject]@{
                LayoutId       = $d.asset_layout_id
                CompanyId      = $d.company_id
                Name           = $d.name
                KeepId         = $keeper.id
                RemoveId       = $d.id
                KeepCreated    = $keeper.created_at
                RemoveCreated  = $d.created_at
                KeepUpdated    = $keeper.updated_at
                RemoveUpdated  = $d.updated_at
                Archived       = $d.archived
            }
        }
    }

$candidates | Format-Table -AutoSize
if ($true -eq $dryRun) {
    Write-Host "Dry run mode enabled. No assets will be removed."
    return $candidates
} else {
    foreach ($c in $candidates) {
        Remove-HuduAsset -Id $c.RemoveId -Confirm:$false
    }
    return $candidates
}
}
function Omni-Relate {
    param(
        [bool]$includeArticles=$true,
        [bool]$includeProcesses=$true,
        [bool]$includeWebsites=$true,
        [bool]$includeIPAM=$true,
        [bool]$includePasswords=$true,
        [bool]$dryRun=$false
    )

    function _Normalize-AssetName {
        param([string]$Name)
        if ([string]::IsNullOrWhiteSpace($Name)) { return "" }
        $n = $Name.Normalize([Text.NormalizationForm]::FormKC)
        $n = $n -replace '&nbsp;',' ' -replace '\s+',' '
        $n = $n.Trim().ToLowerInvariant()
        return $n
    }

    function _Normalize-WebsiteURL {
        param([string]$Url)
        if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
        $u = $Url.Trim()
        if ($u -match '^(https?://)?(?<host>[^/]+)(?<rest>/.*)?$') {
            $hostname = $matches.host.ToLowerInvariant()
            return $hostname.ToLowerInvariant()
        }
        return $u.ToLowerInvariant()
    }

    function _Add-UniqueText {
        param(
            [System.Collections.Generic.List[string]]$List,
            [string]$Value
        )

        if ([string]::IsNullOrWhiteSpace($Value)) { return }

        $trimmed = $Value.Trim()
        if (-not $List.Contains($trimmed)) {
            $null = $List.Add($trimmed)
        }
    }

    function _Contains-IgnoreCase {
        param(
            [string]$Text,
            [string]$Value
        )

        if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Value)) { return $false }
        return $Text.IndexOf($Value, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    }

    function _Test-TextsContainNeedle {
        param(
            [string[]]$Texts,
            [string]$Needle,
            [int]$MinimumLength = 5
        )

        if ([string]::IsNullOrWhiteSpace($Needle)) { return $false }

        $candidate = $Needle.Trim()
        $looksStructured = $candidate -match '[\.:/@\\]'
        if (-not $looksStructured -and "$candidate".length -lt $MinimumLength) {
            return $false
        }

        foreach ($text in @($Texts)) {
            if (_Contains-IgnoreCase -Text $text -Value $candidate) {
                return $true
            }
        }

        return $false
    }

    function _Get-AssetIdentifiers {
        param($Asset)

        $identifiers = [System.Collections.Generic.List[string]]::new()
        _Add-UniqueText -List $identifiers -Value $Asset.name

        $normalizedAssetName = _Normalize-AssetName $Asset.name
        if (-not [string]::IsNullOrWhiteSpace($normalizedAssetName) -and "$normalizedAssetName".length -ge 5 -and $normalizedAssetName -ine 'main') {
            _Add-UniqueText -List $identifiers -Value $normalizedAssetName
        }

        foreach ($field in @($Asset.fields | Where-Object { $_.field_type -eq 'Website' })) {
            _Add-UniqueText -List $identifiers -Value $field.value
            _Add-UniqueText -List $identifiers -Value (_Normalize-WebsiteURL $field.value)
        }

        return @($identifiers)
    }

    function _Get-AssetsMentionedInTexts {
        param(
            [object[]]$Assets,
            $SourceAsset,
            [string[]]$Texts
        )

        if (-not $Assets -or -not $Texts -or $Texts.Count -eq 0) { return @() }

        $matchedAssets = [System.Collections.Generic.List[object]]::new()

        foreach ($asset in @($Assets)) {
            if ($null -eq $asset -or [string]$asset.id -eq [string]$SourceAsset.id) { continue }

            $normalizedName = _Normalize-AssetName $asset.name
            if ([string]::IsNullOrWhiteSpace($normalizedName) -or $normalizedName -ieq 'main' -or "$normalizedName".Length -le 5) {
                continue
            }

            $identifiers = [System.Collections.Generic.List[string]]::new()
            _Add-UniqueText -List $identifiers -Value $asset.name
            _Add-UniqueText -List $identifiers -Value $normalizedName

            foreach ($identifier in @($identifiers)) {
                if (_Test-TextsContainNeedle -Texts $Texts -Needle $identifier -MinimumLength 6) {
                    $null = $matchedAssets.Add($asset)
                    break
                }
            }
        }

        return @($matchedAssets)
    }

    function _Get-PasswordFolderName {
        param(
            $Password,
            [object[]]$PasswordFolders
        )

        if ($null -eq $Password -or $null -eq $Password.password_folder_id) { return $null }

        return ($PasswordFolders | Where-Object { $_.id -eq $Password.password_folder_id } | Select-Object -First 1).name
    }

    function _Get-NonAssetSearchTexts {
        param(
            [string]$Type,
            $Item,
            [object[]]$PasswordFolders
        )

        $texts = [System.Collections.Generic.List[string]]::new()

        switch ($Type) {
            'Website' {
                _Add-UniqueText -List $texts -Value $Item.name
                _Add-UniqueText -List $texts -Value $Item.notes
                _Add-UniqueText -List $texts -Value (_Normalize-WebsiteURL $Item.name)
                if ($Item.PSObject.Properties['url']) {
                    _Add-UniqueText -List $texts -Value $Item.url
                    _Add-UniqueText -List $texts -Value (_Normalize-WebsiteURL $Item.url)
                }
            }
            'Article' {
                _Add-UniqueText -List $texts -Value $Item.name
                _Add-UniqueText -List $texts -Value $Item.content
            }
            'Procedure' {
                _Add-UniqueText -List $texts -Value $Item.name
                foreach ($task in @($Item.procedure_tasks_attributes)) {
                    if ($task -is [string]) {
                        _Add-UniqueText -List $texts -Value $task
                        continue
                    }

                    _Add-UniqueText -List $texts -Value $task.name
                    if ($task.PSObject.Properties['description']) {
                        _Add-UniqueText -List $texts -Value $task.description
                    }
                }
            }
            'AssetPassword' {
                _Add-UniqueText -List $texts -Value $Item.name
                _Add-UniqueText -List $texts -Value $Item.notes
                _Add-UniqueText -List $texts -Value $Item.description
                _Add-UniqueText -List $texts -Value (_Get-PasswordFolderName -Password $Item -PasswordFolders $PasswordFolders)
            }
            'Network' {
                _Add-UniqueText -List $texts -Value $Item.name
                _Add-UniqueText -List $texts -Value $Item.notes
                _Add-UniqueText -List $texts -Value $Item.description
                foreach ($propertyName in @('network', 'cidr', 'subnet', 'gateway')) {
                    if ($Item.PSObject.Properties[$propertyName]) {
                        _Add-UniqueText -List $texts -Value ([string]$Item.$propertyName)
                    }
                }
            }
            'IPAddress' {
                _Add-UniqueText -List $texts -Value $Item.name
                _Add-UniqueText -List $texts -Value $Item.notes
                _Add-UniqueText -List $texts -Value $Item.description
                foreach ($propertyName in @('ip_address', 'address', 'hostname')) {
                    if ($Item.PSObject.Properties[$propertyName]) {
                        _Add-UniqueText -List $texts -Value ([string]$Item.$propertyName)
                    }
                }
            }
        }

        return @($texts)
    }

    function _Get-RelationTargetIdentifiers {
        param(
            [string]$Type,
            $Item,
            [object[]]$PasswordFolders
        )

        if ($Type -eq 'Asset') {
            return @(_Get-AssetIdentifiers -Asset $Item)
        }

        $identifiers = [System.Collections.Generic.List[string]]::new()
        _Add-UniqueText -List $identifiers -Value $Item.name

        switch ($Type) {
            'Website' {
                _Add-UniqueText -List $identifiers -Value (_Normalize-WebsiteURL $Item.name)
                if ($Item.PSObject.Properties['url']) {
                    _Add-UniqueText -List $identifiers -Value $Item.url
                    _Add-UniqueText -List $identifiers -Value (_Normalize-WebsiteURL $Item.url)
                }
            }
            'Procedure' {
                foreach ($task in @($Item.procedure_tasks_attributes)) {
                    if ($task -is [string]) {
                        _Add-UniqueText -List $identifiers -Value $task
                    } else {
                        _Add-UniqueText -List $identifiers -Value $task.name
                    }
                }
            }
            'AssetPassword' {
                _Add-UniqueText -List $identifiers -Value (_Get-PasswordFolderName -Password $Item -PasswordFolders $PasswordFolders)
            }
            'Network' {
                foreach ($propertyName in @('network', 'cidr', 'subnet', 'gateway')) {
                    if ($Item.PSObject.Properties[$propertyName]) {
                        _Add-UniqueText -List $identifiers -Value ([string]$Item.$propertyName)
                    }
                }
            }
            'IPAddress' {
                foreach ($propertyName in @('ip_address', 'address', 'hostname')) {
                    if ($Item.PSObject.Properties[$propertyName]) {
                        _Add-UniqueText -List $identifiers -Value ([string]$Item.$propertyName)
                    }
                }
            }
        }

        return @($identifiers)
    }

    function _New-TrackedRelation {
        param(
            [string]$CompanyName,
            [string]$FromType,
            [object]$FromId,
            [string]$FromName,
            [string]$ToType,
            [object]$ToId,
            [string]$ToName,
            [string]$RelationLabel,
            [hashtable]$SeenRelations,
            [switch]$DryRun
        )

        if ($FromType -eq $ToType -and [string]$FromId -eq [string]$ToId) { return }
        if ($FromType -eq "IPAddress" -and $ToType -eq "IPAddress") { return }
        $relationKey = "$FromType|$FromId|$ToType|$ToId"
        if ($SeenRelations.ContainsKey($relationKey)) { return }
        $SeenRelations[$relationKey] = $true

        Write-Host "[$CompanyName] '$FromName' ($FromId) mentions $RelationLabel -> '$ToName' ($ToId)"

        if ($DryRun) { return }

        try {
            $null = New-HuduRelation -FromableType $FromType -ToableType $ToType -FromableID $FromId -ToableID $ToId
        } catch {
            Write-Warning "Failed relation creation for $FromType/$FromId -> $ToType/$ToId : $($_.Exception.Message)"
        }
    }

    if (get-command -name Set-HapiErrorsDirectory -ErrorAction SilentlyContinue){try {Set-HapiErrorsDirectory -skipRetry $true} catch {}}
    write-host "getting companies"; $allcompanies = get-huducompanies;
    write-host "getting assets"; $allAssets = get-huduassets;
    if ($includewebsites){write-host "getting websites"; $allWebsites = get-huduwebsites;} else {write-host "skipping websites"; $allWebsites = @();}
    if ($includeArticles){write-host "getting articles"; $allArticles = get-huduarticles;} else {write-host "skipping articles"; $allArticles = @();}
    if ($includeProcesses){write-host "getting processes"; $allProcesses = Get-HuduProcedures;} else {write-host "skipping processes"; $allProcesses = @();}
    if ($includeIPAM){
        write-host "getting networks"; $allNetworks = Get-HuduNetworks;
        write-host "getting addresses"; $alladdresses = get-huduipaddresses;
    } else {write-host "skipping IPAM"; $allNetworks = @(); $alladdresses = @();}
    if ($includePasswords){
        write-host "getting passwords"; $allPasswords = get-hudupasswords;
        write-host "getting password folders"; $allPasswordFolders = get-hudupasswordfolders;
    } else {write-host "skipping passwords"; $allPasswords = @(); $allPasswordFolders = @();}



    foreach ($c in $allcompanies) { 

        $companyAssets = $allAssets | Where-Object { $_.company_id -eq $c.id }
        $companywebsites = $allWebsites | Where-Object { $_.company_id -eq $c.id }
        $companyArticles = $allArticles | Where-Object { $_.company_id -eq $c.id }
        $companyProcesses = $allProcesses | Where-Object { $_.company_id -eq $c.id }
        $companyNetworks = $allNetworks | Where-Object { $_.company_id -eq $c.id }
        $companyAddresses = $alladdresses | Where-Object { $_.company_id -eq $c.id }
        $companypasswords = $allPasswords | Where-Object { $_.company_id -eq $c.id }
        $companypasswordfolders = $allPasswordFolders | Where-Object { $_.company_id -eq $c.id }

        foreach ($i in @($companywebsites,$companyArticles,$companyProcesses,$companyNetworks,$companyAddresses,$companyAssets,$companypasswords,$companypasswordfolders) | Where-Object { $_.count -gt 0 }) {
            write-host "Company '$($c.name)' has $($i.count) items of type $($i[0].psobject.typeNames[0])" -ForegroundColor DarkCyan
        }

        $companyProcedureTaskNames = $companyProcesses.procedure_tasks_attributes.name | sort-object -unique
        $companyProcedureAssignments = $companyProcesses.procedure_tasks_attributes.first_assigned_user_name | sort-object -unique


        $companyAssetsByName = $companyAssets | Group-Object { _Normalize-AssetName $_.name } -AsHashTable -AsString
        $companySeenRelations = @{}

        foreach ($a in $companyAssets) {
            $normalizedAssetName = _Normalize-AssetName $a.name
            write-host "Processing asset '$($a.name)' ($($a.id))"


            $mentionedWebsites = @()
            $mentionedArticles = @()
            $mentionedAssets = @()
            $mentionedProcedures = @()
            $mentionedPasswords = @()
            $networksMentioned = @()
            $addressesMentioned = @()


            # start out with association by name (if not generalized)
            if ($normalizedAssetName -ieq "main" -or "$normalizedAssetName".length -lt 5) {
                write-host "Skipping match by name on too-generic of asset '$($a.name)' ($($a.id)) due to short or generic name" -ForegroundColor Yellow
            } else {
            if ($companywebsites) {
                $mentionedWebsites = $companywebsites | Where-Object { $_.Notes -and ($_.Notes.Contains($normalizedAssetName) -or $_.Notes.Contains($a.name)) }
            }
            if ($companyArticles) {
                $mentionedArticles = $companyArticles | Where-Object { ($_.Name -and $_.Content.Contains($a.name)) -or ($_.Content -and $_.Content.Contains($normalizedAssetName)) }
            }
            if ($companyProcesses) {
                $mentionedProcedures = $companyProcesses | Where-Object { ($_.name -and $_.name.Contains($normalizedAssetName)) -or ($_.procedure_tasks_attributes.name -and $_.procedure_tasks_attributes.name.Contains($normalizedAssetName)) -or ($_.name -and $_.name.Contains($a.name)) -or ($_.procedure_tasks_attributes.name -and $_.procedure_tasks_attributes.name.Contains($a.name)) }
            }
            if ($companypasswords) {
                $mentionedPasswords = $companypasswords | Where-Object { ($_.name -and ($_.name.Contains($normalizedAssetName) -or $_.name.Contains($a.name))) -or ($_.notes -and ($_.notes.Contains($normalizedAssetName) -or $_.notes.Contains($a.name)) -or ($_.description -and ($_.description.Contains($normalizedAssetName) -or $_.description.Contains($a.name)))) }
            }}
            

            # websites where name or url is mentioned in text/richtext fields of the asset
            # articles with content or name mentioned in a website field (either website field or text/richtext fields)
            $a.fields | Where-Object {$_.field_type -eq "Website"} | ForEach-Object {
                $fieldValue = $_.value
                $fieldvaluenormalized = _Normalize-WebsiteURL $fieldValue
                foreach ($companyProcess in $companyProcesses){ # procedure or tasks contain website field value or asset name
                    if (($companyProcess.name -and $companyProcess.name.Contains($fieldValue) -or $companyProcess.procedure_tasks_attributes.name -and $companyProcess.procedure_tasks_attributes.name.Contains($fieldValue)) -or `
                        ($companyProcess.name -and $companyProcess.name.Contains($fieldValue) -or $companyProcess.procedure_tasks_attributes.name -and $companyProcess.procedure_tasks_attributes.name.Contains($fieldValue))){
                        $mentionedProcedures += $companyProcess
                    }
                }
                foreach ($password in $companypasswords){ # password or password notes contain website field value or asset name
                    if (($password.name -and $password.name.Contains($fieldValue)) -or ($password.notes -and $password.notes.Contains($fieldValue)) -or ($password.name -and $password.name.Contains($a.name)) -or ($password.notes -and $password.notes.Contains($a.name))){
                        $mentionedPasswords += $password
                    } elseif ($null -ne $password.password_folder_id){
                        $passwordFolder = $companypasswordfolders | Where-Object { $_.id -eq $password.password_folder_id } | Select-Object -First 1
                        if ($passwordFolder.name -and $fieldValue -and $passwordFolder.name.Contains($fieldValue) -or $passwordFolder.name -and $fieldValue -and $passwordFolder.name.Contains($a.name)){
                            $mentionedPasswords += $password
                        }
                    }
                }
                foreach ($network in $companyNetworks){
                    if ($network.name -and $network.name.Contains($fieldValue) -or $network.notes -and $network.notes.Contains($fieldValue) -or $network.name -and $network.name.Contains($a.name) -or $network.notes -and $network.notes.Contains($a.name) -or $network.description -and ( $network.description.Contains($fieldValue) -or $network.description.Contains($a.name) -or $network.description.Contains($fieldvaluenormalized)) ){
                        $networksMentioned += $network
                    }
                }
                foreach ($address in $companyaddresses){
                    if ($address.name -and $address.name.Contains($fieldValue) -or $address.notes -and $address.notes.Contains($fieldValue) -or $address.name -and $address.name.Contains($a.name) -or $address.notes -and $address.notes.Contains($a.name) -or $address.description -and ( $address.description.Contains($fieldValue) -or $address.description.Contains($a.name) -or $address.description.Contains($fieldvaluenormalized)) ){
                        $addressesMentioned += $address
                    }
                }
                $mentionedWebsites += $companywebsites | Where-Object { "$fieldvaluenormalized*" -ilike "$(_Normalize-WebsiteURL $_.name)*" -or $_.name -icontains "$($fieldvaluenormalized)" -or $_.name -icontains $normalizedAssetName }
                $mentionedArticles += $companyArticles | Where-Object { $_.content -and $_.content.Contains("$($fieldvaluenormalized)") -or ($_.Name -and $_.Name.Contains("$($fieldvaluenormalized)")) }
                $mentionedAssets += $companyAssets | Where-Object { $_.name -and $_.name.Contains("$($fieldvaluenormalized)") }
            }
            $a.fields | Where-Object {$_.field_type -eq "ConfidentialText"} | ForEach-Object {
                if (($_.value -and $_.value -eq $password.password) -or ($_.value -and $_.value -eq $password.notes) -or ($_.value -and $_.value -eq $a.name) -or ($_.value -and $_.value -eq $password.name)){
                    $mentionedPasswords += $password
                } 
            }

            $a.fields | Where-Object {$_.field_type -eq "RichText" -or $_.field_type -ieq "Heading"  -or $_.field_type -ieq "Embed"} | ForEach-Object {
                $fieldValue = $_.value
                foreach ($companyProcess in $companyProcesses){
                    if (($companyProcess.name -and $fieldValue -icontains $companyProcess.name -or $companyProcess.procedure_tasks_attributes.name -and $fieldValue -icontains $companyProcess.procedure_tasks_attributes.name)){
                        $mentionedProcedures += $companyProcess
                    }
                }
                foreach ($password in $companypasswords){ 
                    if (($password.name -and $fieldValue -icontains $password.name) -or ($password.notes -and $fieldValue -icontains $password.notes) -or ($password.name -and $fieldValue -icontains $a.name) -or ($password.notes -and $fieldValue -icontains $a.name)){
                        $mentionedPasswords += $password
                    } elseif ($null -ne $password.password_folder_id){
                        $passwordFolder = $companypasswordfolders | Where-Object { $_.id -eq $password.password_folder_id } | Select-Object -First 1
                        if ($passwordFolder.name -and $fieldValue -and $fieldValue -icontains $passwordFolder.name -or $passwordFolder.name -and $fieldValue -icontains $a.name){
                            $mentionedPasswords += $password
                        }
                    }
                }
                foreach ($network in $companyNetworks){
                    if ($network.name -and $fieldValue -icontains $network.name -or $network.notes -and $fieldValue -icontains $network.notes -or $network.name -and $fieldValue -icontains $a.name -or $network.notes -and $fieldValue -icontains $a.name -or $network.description -and ( $fieldValue -icontains $network.description) ){
                        $networksMentioned += $network
                    }
                }
                foreach ($address in $companyaddresses){
                    if ($address.name -and $fieldValue -icontains $address.name -or $address.notes -and $fieldValue -icontains $address.notes -or $address.name -and $fieldValue -icontains $a.name -or $address.notes -and $fieldValue -icontains $a.name -or $address.description -and ( $fieldValue -icontains $address.description) ){
                        $addressesMentioned += $address
                    }
                }                
                $mentionedWebsites += $companywebsites | Where-Object { $fieldValue -icontains $normalizedAssetName -or $(_Normalize-AssetName $_.name) -ieq $normalizedAssetName -or $fieldValue -icontains $_.name -or $_.notes -icontains $normalizedAssetName -or $_.notes -icontains $a.name }
                $mentionedArticles += $companyArticles | Where-Object { $_.content -and $_.content.Contains($normalizedAssetName) -or $_.content -icontains $a.name -or $normalizedAssetName -ieq (_Normalize-AssetName $_.name) }
                $mentionedAssets += _Get-AssetsMentionedInTexts -Assets $companyAssets -SourceAsset $a -Texts @($fieldValue)
            }       
            $a.fields | Where-Object {$_.field_type -eq "Text"  -or $_.field_type -ieq "Link"  -or $_.field_type -ieq "ConfidentialText"  -or $_.field_type -ieq "Phone"  -or $_.field_type -ieq "Copyable_Text"} | ForEach-Object {
                $fieldValue = $_.value
                foreach ($companyProcess in $companyProcesses){
                    if (
                        ($companyProcess.name -and $fieldValue -icontains $companyProcess.name -or $companyProcess.procedure_tasks_attributes.name -and $fieldValue -icontains $companyProcess.procedure_tasks_attributes.name) `
                        -or ($companyProcess.name -and $companyProcess.name -icontains $fieldValue -or $companyProcess.procedure_tasks_attributes.name -and $companyProcess.procedure_tasks_attributes.name -icontains $fieldValue)){
                        $mentionedProcedures += $companyProcess
                    }
                }
                foreach ($password in $companypasswords){ 
                    if (
                        ($password.name -and $fieldValue -icontains $password.name) -or ($password.notes -and $fieldValue -icontains $password.notes) -or ($password.name -and $fieldValue -icontains $a.name) -or ($password.notes -and $fieldValue -icontains $a.name) `
                        -or ($password.name -and $password.name -icontains $fieldValue) -or ($password.notes -and $password.notes -icontains $fieldValue)){
                        $mentionedPasswords += $password
                    } elseif ($null -ne $password.password_folder_id){
                        $passwordFolder = $companypasswordfolders | Where-Object { $_.id -eq $password.password_folder_id } | Select-Object -First 1
                        if (
                            ($passwordFolder.name -and $fieldValue -and $fieldValue -icontains $passwordFolder.name) -or ($passwordFolder.name -and $fieldValue -icontains $a.name) `
                            -or ($passwordFolder.name -and $passwordFolder.name -icontains $fieldValue)){
                            $mentionedPasswords += $password
                        }
                    }
                }
                foreach ($network in $companyNetworks){
                    if (($network.name -and $fieldValue -icontains $network.name -or $network.notes -and $fieldValue -icontains $network.notes -or $network.name -and $fieldValue -icontains $a.name -or $network.notes -and $fieldValue -icontains $a.name -or $network.description -and ( $fieldValue -icontains $network.description)) -or `
                        ($network.name -and $network.name -icontains $fieldValue) -or ($network.notes -and $network.notes -icontains $fieldValue) -or ($network.description -and $network.description -icontains $fieldValue)){
                        $networksMentioned += $network
                    }
                }
                foreach ($address in $companyaddresses){
                    if (($address.name -and $fieldValue -icontains $address.name -or $address.notes -and $fieldValue -icontains $address.notes -or $address.name -and $fieldValue -icontains $a.name -or $address.notes -and $fieldValue -icontains $a.name -or $address.description -and ( $fieldValue -icontains $address.description) ) -or `
                        ($address.name -and $address.name -icontains $fieldValue) -or ($address.notes -and $address.notes -icontains $fieldValue) -or ($address.description -and $address.description -icontains $fieldValue)){
                        $addressesMentioned += $address
                    }
                }

                $mentionedArticles += $companyArticles | Where-Object { $($fieldValue) -ieq $_.name -or $_.content -and $_.content.Contains($fieldValue) }
                $mentionedWebsites += $companywebsites | Where-Object { $($fieldValue) -ieq $_.name -or $(_Normalize-WebsiteURL $_.name) -ieq $fieldValue -or $_.notes -icontains $fieldValue -or $_.notes -icontains $a.name }
                $mentionedAssets += _Get-AssetsMentionedInTexts -Assets $companyAssets -SourceAsset $a -Texts @($fieldValue)
            }
    
            # "siblings": other assets with same normalized name but different id
            $siblings = @($companyAssetsByName[$normalizedAssetName] | Where-Object { $_.id -ne $a.id })
            $siblings | ForEach-Object {
                Write-Host "Sibling Asset $($a.name)@($($a.asset_layout_id)) -> $($_.name)@($($_.asset_layout_id))"
                _New-TrackedRelation -CompanyName $c.name -FromType "Asset" -FromId $a.id -FromName $a.name -ToType "Asset" -ToId $_.id -ToName $_.name -RelationLabel "asset" -SeenRelations $companySeenRelations -DryRun:$dryRun
            }
            $mentionedWebsites | ForEach-Object {
                _New-TrackedRelation -CompanyName $c.name -FromType "Asset" -FromId $a.id -FromName $a.name -ToType "Website" -ToId $_.id -ToName $_.name -RelationLabel "website" -SeenRelations $companySeenRelations -DryRun:$dryRun
            }
            $mentionedArticles | ForEach-Object {
                _New-TrackedRelation -CompanyName $c.name -FromType "Asset" -FromId $a.id -FromName $a.name -ToType "Article" -ToId $_.id -ToName $_.name -RelationLabel "article" -SeenRelations $companySeenRelations -DryRun:$dryRun
            }
            $mentionedAssets | ForEach-Object {
                _New-TrackedRelation -CompanyName $c.name -FromType "Asset" -FromId $a.id -FromName $a.name -ToType "Asset" -ToId $_.id -ToName $_.name -RelationLabel "asset" -SeenRelations $companySeenRelations -DryRun:$dryRun
            }
            $mentionedPasswords | ForEach-Object {
                _New-TrackedRelation -CompanyName $c.name -FromType "Asset" -FromId $a.id -FromName $a.name -ToType "AssetPassword" -ToId $_.id -ToName $_.name -RelationLabel "password" -SeenRelations $companySeenRelations -DryRun:$dryRun
            }
            $mentionedProcedures | ForEach-Object {
                _New-TrackedRelation -CompanyName $c.name -FromType "Asset" -FromId $a.id -FromName $a.name -ToType "Procedure" -ToId $_.id -ToName $_.name -RelationLabel "procedure" -SeenRelations $companySeenRelations -DryRun:$dryRun
            }
            $addressesMentioned | ForEach-Object {
                _New-TrackedRelation -CompanyName $c.name -FromType "Asset" -FromId $a.id -FromName $a.name -ToType "IPAddress" -ToId $_.id -ToName $_.name -RelationLabel "address" -SeenRelations $companySeenRelations -DryRun:$dryRun
            }
            $networksMentioned | ForEach-Object {
                _New-TrackedRelation -CompanyName $c.name -FromType "Asset" -FromId $a.id -FromName $a.name -ToType "Network" -ToId $_.id -ToName $_.name -RelationLabel "network" -SeenRelations $companySeenRelations -DryRun:$dryRun
            }
        }

        $nonAssetSources = @()
        $nonAssetSources += $companywebsites | ForEach-Object { [pscustomobject]@{ type = 'Website'; item = $_ } }
        $nonAssetSources += $companyArticles | ForEach-Object { [pscustomobject]@{ type = 'Article'; item = $_ } }
        $nonAssetSources += $companyProcesses | ForEach-Object { [pscustomobject]@{ type = 'Procedure'; item = $_ } }
        $nonAssetSources += $companypasswords | ForEach-Object { [pscustomobject]@{ type = 'AssetPassword'; item = $_ } }
        $nonAssetSources += $companyNetworks | ForEach-Object { [pscustomobject]@{ type = 'Network'; item = $_ } }
        $nonAssetSources += $companyAddresses | ForEach-Object { [pscustomobject]@{ type = 'IPAddress'; item = $_ } }

        $relationTargets = @()
        $relationTargets += $companyAssets | ForEach-Object { [pscustomobject]@{ type = 'Asset'; label = 'asset'; item = $_ } }
        $relationTargets += $companywebsites | ForEach-Object { [pscustomobject]@{ type = 'Website'; label = 'website'; item = $_ } }
        $relationTargets += $companyArticles | ForEach-Object { [pscustomobject]@{ type = 'Article'; label = 'article'; item = $_ } }
        $relationTargets += $companyProcesses | ForEach-Object { [pscustomobject]@{ type = 'Procedure'; label = 'procedure'; item = $_ } }
        $relationTargets += $companypasswords | ForEach-Object { [pscustomobject]@{ type = 'AssetPassword'; label = 'password'; item = $_ } }
        $relationTargets += $companyNetworks | ForEach-Object { [pscustomobject]@{ type = 'Network'; label = 'network'; item = $_ } }
        $relationTargets += $companyAddresses | ForEach-Object { [pscustomobject]@{ type = 'IPAddress'; label = 'address'; item = $_ } }

        foreach ($source in $nonAssetSources) {
            $sourceTexts = @(_Get-NonAssetSearchTexts -Type $source.type -Item $source.item -PasswordFolders $companypasswordfolders)
            if (-not $sourceTexts -or $sourceTexts.Count -eq 0) { continue }

            $sourceName = $source.item.name
            if ([string]::IsNullOrWhiteSpace($sourceName)) {
                $sourceName = "$($source.type) $($source.item.id)"
            }

            Write-Host "Processing $($source.type.ToLowerInvariant()) '$sourceName' ($($source.item.id)) for relation mentions"

            foreach ($target in $relationTargets) {
                if ($source.type -eq $target.type -and [string]$source.item.id -eq [string]$target.item.id) { continue }

                $targetIdentifiers = @(_Get-RelationTargetIdentifiers -Type $target.type -Item $target.item -PasswordFolders $companypasswordfolders)
                if (-not $targetIdentifiers -or $targetIdentifiers.Count -eq 0) { continue }

                $matched = $false
                foreach ($targetIdentifier in $targetIdentifiers) {
                    if (_Test-TextsContainNeedle -Texts $sourceTexts -Needle $targetIdentifier) {
                        $matched = $true
                        break
                    }
                }

                if (-not $matched) { continue }

                _New-TrackedRelation -CompanyName $c.name -FromType $source.type -FromId $source.item.id -FromName $sourceName -ToType $target.type -ToId $target.item.id -ToName $target.item.name -RelationLabel $target.label -SeenRelations $companySeenRelations -DryRun:$dryRun
            }
        }
    }
    if (get-command -name Set-HapiErrorsDirectory -ErrorAction SilentlyContinue){try {Set-HapiErrorsDirectory -skipRetry $false} catch {}}

}

function New-HuduAddress {
    param([Parameter(Mandatory)][object]$Input)

    # Parse JSON strings; pass through objects
    $o = if ($Input -is [string]) { try { $Input | ConvertFrom-Json } catch { $null } } else { $Input }
    if (-not $o) { return $null }

    # Helper to grab the first present alias
    $first = {
        param($obj, [string[]]$names)
        foreach ($n in $names) { if ($obj.PSObject.Properties.Name -contains $n) { return $obj.$n } }
        return $null
    }

    $addr1 = & $first $o @('address_line_1','address1','address_1','line1','street','street1','address')
    $addr2 = & $first $o @('address_line_2','address2','address_2','line2','street2')
    $city           = & $first $o @('city','town')
    $state          = & $first $o @('state','province','region')
    $zip            = & $first $o @('zip','zipcode','postal','postal_code')
    $cntry   = & $first $o @('country_name','country')
    if ($addr1 -or $addr2 -or $city -or $state -or $zip -or $cntry) {
    $NewAddress = [ordered]@{
        address_line_1 = $addr1
        city           = $city
        state          = $state
        zip            = $zip
        country_name   = $cntry
    }
    if ($addr2) { $NewAddress['address_line_2'] = $addr2 }
    return $NewAddress
    } else {return $null}
}

function Resolve-LocationForCompany {
  param(
    [Parameter(Mandatory)][int]$CompanyId,
    [Parameter(Mandatory)]$Row,
    [Parameter(Mandatory)]$AllHuduLocations,
    [string[]]$Hints
  )

  # If $Hints can be null at call-time, set a safe default here (avoid default param expr that depends on external vars)
  if (-not $Hints) { $Hints = @('location','branch','office','site','building') }

  $candKeys = @()
  foreach ($prop in $Row.PSObject.Properties) {
    $propName = $prop.Name
    if ($Hints.Where({ param($h) (Test-Fuzzy $propName $h) }, 'First')) {
      $candKeys += $propName
    }
  }
  $candKeys = $candKeys | Sort-Object -Unique

  $candVals = @()
  foreach ($k in $candKeys) {
    $v = $Row.$k
    if ($null -ne $v -and "$v".Trim()) { $candVals += "$v" }
  }
  if (-not $candVals) { return $null }

  $companyLocs = $AllHuduLocations | Where-Object { $_.company_id -eq $CompanyId }
  foreach ($cv in $candVals) {
    $hit = $companyLocs | Where-Object { test-equiv -A $_.name -B $cv } | Select-Object -First 1
    if ($hit) { return $hit }
  }
  return $null
}
function Get-ListItemFuzzy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][int]$ListId,
        [double]$MinSimilarity = 0.85   # tweak as needed
    )

    if ([string]::IsNullOrWhiteSpace($Source)) { return $null }

    $list = Get-HuduLists -Id $ListId
    if (-not $list -or -not $list.list_items) { return $null }

    $sNorm = Normalize-Text $Source

    $bestItem  = $null
    $bestScore = -1.0

    foreach ($item in $list.list_items) {
        $name = [string]$item.name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $nNorm = Normalize-Text $name

        $score = if ($nNorm -eq $sNorm) { 1.0 } else { Get-Similarity $name $Source }
        if ($nNorm.StartsWith($sNorm) -or $sNorm.StartsWith($nNorm)) {
            $score = [Math]::Min(1.0, $score + 0.02)
        }

        if ($score -gt $bestScore) {
            $bestScore = $score
            $bestItem  = $item
        }
    }

    if ($bestScore -lt $MinSimilarity) { return $null }
    return $bestItem
}

function Get-UniqueHuduListName {
  param([Parameter(Mandatory)][string]$BaseName,[bool]$allowReuse=$false)

  $name = $BaseName.Trim()
  $i = 0
  while ($true) {
    $existing = Get-HuduLists -name $name
    if (-not $existing) { return $name }
    if ($existing -and $true -eq $allowReuse) {return $existing}
    $i++
    $name = "{0}-{1}" -f $BaseName.Trim(), $i
  }
}

function Get-HuduLayoutLike {
  param ([array]$LabelSet)

  foreach ($layout in $(get-huduassetlayouts)){
    foreach ($Label in $LabelSet){
      if ($true -eq $(Test-Equiv -A $locationLabel -$layout.name)){
        return $layout
      }
    }
  }
  Write-Host "No location layout found. Ensure your location layout name is in LocationLayoutNames array ($LocationLayoutNames)"
  return $null
}

function Ensure-HuduListItemByName {
    param(
        [Parameter(Mandatory)][int]$ListId,
        [Parameter(Mandatory)][string]$Name,
        [hashtable]$listNameExistsByListId
    )

    $nameTrim = $Name.Trim()
    $needle = $nameTrim.ToLowerInvariant()

    if (-not $listNameExistsByListId.ContainsKey($ListId)) {
        Refresh-ListCache
    }

    $map = $listNameExistsByListId[$ListId]
    if ($map -and $map.ContainsKey($needle)) {
        return $map[$needle]  # return canonical name as stored
    }

    # Add item to list
    $list = Get-HuduLists -Id $ListId
    $listName = $list.name

    $items = @()
    foreach ($existing in ($list.list_items ?? @())) {
        $items += @{ id = [int]$existing.id; name = [string]$existing.name }
    }
    $items += @{ name = $nameTrim }

    $null = Set-HuduList -Id $ListId -Name $listName -ListItems $items

    # refresh cache and return
    $listNameExistsByListId = Refresh-ListCache
    $map = $listNameExistsByListId[$ListId]
    if ($map.ContainsKey($needle)) { return $map[$needle] }

    throw "Failed to add/list item '$Name' to list $ListId"
}
function Refresh-ListCache {
    $listNameExistsByListId = @{}
    foreach ($l in Get-HuduLists) {
        $lid = [int]$l.id
        $map = @{}
        foreach ($it in ($l.list_items ?? @())) {
            if ($it.name) {
                $map[$it.name.ToString().Trim().ToLowerInvariant()] = [string]$it.name
            }
        }
        $listNameExistsByListId[$lid] = $map
    }
    return $listNameExistsByListId
}

function normalize-companyName {
    param([string]$Text)

    ($Text `
        -replace '(?i)\binc\b', '' `
        -replace '[\.,]', '' `
        -replace '\s+', ' '
    ).Trim()
}
function Get-HuduCompanyFromName {
    # use index first. Then existing list. Then API call.
    param (
        [Parameter(Mandatory = $true)]
        [string]$CompanyName,
        [array]$HuduCompanies,
        [bool]$includenicknames = $false,
        [array]$existingIndex = @(),
        [bool]$deepCompanySearch = $false
    )
    if ([string]::IsNullOrWhiteSpace($CompanyName)) { return $null }

        $normalizedCompanyName = normalize-companyName -Text $CompanyName
    # matched first
    $matchedCompany = $null
    if ($deepCompanySearch -eq $true){
        $matchedCompany = get-huducompanies | Where-Object {$(normalize-companyName -Text $_.name) -ieq (normalize-companyName -Text $normalizedCompanyName)} | Select-Object -First 1
    }
    if ($existingIndex -ne $null -and $existingIndex.count -gt 0 -and $matchedCompany -eq $null){
        $matchedCompany = $matchedCompany ?? $existingIndex | where-object {
            ($_.CompanyName -ieq $CompanyName) -or ($_.HuduCompany.name -ieq $CompanyName) -or
            ($normalizedCompanyName -ieq (normalize-companyName -Text $_.CompanyName)) -or ($normalizedCompanyName -ieq (normalize-companyName -Text $_.HuduCompany.name)) -or
            ($normalizedCompanyName -icontains (normalize-companyName -Text $_.CompanyName)) -or ($normalizedCompanyName -icontains (normalize-companyName -Text $_.HuduCompany.name)) -or
            [bool]$(test-equiv -A $_.CompanyName -B $CompanyName) } | Select-Object -First 1
        if ($includenicknames){
            $matchedCompany = $matchedCompany ?? $existingIndex | where-object {
                (-not [string]::IsNullOrWhiteSpace($_.HuduCompany.nickname)) -and (
                    ($_.HuduCompany.nickname -ieq $CompanyName) -or
                    [bool]$(test-equiv -A $_.HuduObject.nickname -B $CompanyName))
            } | Select-Object -First 1
        }   
    }
    if ($null -ne $matchedCompany){
      $matchedCompany = $matchedCompany.HuduCompany ?? $matchedCompany
      write-host "matched company using prematched companies: $($matchedCompany.name)"
      return $matchedCompany
    }    

    # then existing list
    $matchedCompany = $matchedCompany ?? $HuduCompanies | where-object {
            ($_.name -ieq $CompanyName) -or
            [bool]$(test-equiv -A $_.name -B $CompanyName)`
        } | Select-Object -First 1

    if ($true -eq $includenicknames){
        $matchedCompany =$matchedCompany ?? $HuduCompanies | where-object {
                ($_.nickname -ieq $CompanyName) -or
                [bool]$(test-equiv -A $_.nickname -B $CompanyName)`
            } | Select-Object -First 1
    }
    if ($null -ne $matchedCompany){
      $matchedCompany = $matchedCompany.HuduCompany ?? $matchedCompany
      write-host "matched company using companies array: $($matchedCompany.name)"
      return $matchedCompany
    }


    # finally API call
    if ($deepCompanySearch -eq $false){return $matchedCompany}

    $matchedCompany = $matchedCompany ?? $(Get-HuduCompanies -Name $CompanyName | select-object -first 1)
    if ($null -eq $matchedCompany){
          $matchedCompany = $matchedCompany ?? $(Get-HuduCompanies) | where-object {
            ($_.name -ieq $CompanyName) -or
            [bool]$(test-equiv -A $_.name -B $CompanyName) -or 
            ($normalizedCompanyName -ieq (normalize-companyName -Text $_.name))  -or
            ($normalizedCompanyName -icontains (normalize-companyName -Text $_.name)) 
        } | Select-Object -First 1
    }
    if ($null -ne $matchedCompany){
      write-host "matched company using API call: $($matchedCompany.name)"
      $matchedCompany = $matchedCompany.HuduCompany ?? $matchedCompany
      return $matchedCompany
    }
    $matchedCompany = $matchedCompany.HuduCompany ?? $matchedCompany
    return $matchedCompany
}

function Get-HuduFieldValue {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][object]$Asset,
    [Parameter(Mandatory)][string[]]$Labels
  )
  $labelsLC = $Labels | ForEach-Object { $_.ToLower() }
  $Asset.fields |
    Where-Object { $_.label -and $labelsLC -contains ([string]$_.label).ToLower() } |
    Select-Object -First 1 -ExpandProperty value
}

function Get-HuduAssetFromName {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [int]$AssetLayoutId,
        [array]$Assets
    )
    if ([string]::IsNullOrWhiteSpace($Name) -or -not $AssetLayoutId -or $AssetLayoutId -lt 1) { return $null }
    $matchedAsset = $null
    $matchedAsset = $Assets | where-object {
            ($_.name -ieq $Name) -or
            [bool]$(test-equiv -A $_.name -B $Name)`
        } | Select-Object -First 1
    $matchedAsset = $matchedAsset ?? 
        $(Get-HuduAssets -AssetLayoutId $AssetLayoutId -Name $CompanyName) ?? 
         (get-huduassets -AssetLayoutId $AssetLayoutId | where-object {[bool]$(test-equiv -A $_.name -B $Name)} | select-object -first 1)
    return $matchedCompany
}



function Set-ReleaseArtifact {
    Remove-Item -Path "$($(get-childitem -path "." -Recurse -Directory "artifacts" | Select-Object -first 1).fullname)\*.txt" -Force -ErrorAction SilentlyContinue
    Get-GitCheckoutInfo | Out-File "$($(get-childitem -path "." -Recurse -Directory "artifacts" | Select-Object -first 1).fullname)\$($(Get-Date -Format o | ForEach-Object { $_ -replace ":", "." })).txt" -Encoding utf8
}
function Get-ReleaseArtifact {
    $artifact = (Get-ChildItem -Path "." -Recurse -Directory "artifacts" | Select-Object -First 1 | Get-ChildItem -Filter "*.txt" | Select-Object -First 1)
    if (-not $(test-path $artifact.FullName)) {
        return $null
    }
    return "$(Get-Content -Path $artifact.FullName)"
}

function Get-GitCheckoutInfo {
    [CmdletBinding()]
    param(
        [string]$Path = (Get-Location).Path
    )
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return ($(Get-ReleaseArtifact) ?? "No Git installation found, cannot discern checkout info")
    }
    Push-Location -LiteralPath $Path
    try {
        $insideRepo = git rev-parse --is-inside-work-tree 2>$null
        if ($LASTEXITCODE -ne 0 -or $insideRepo -ne 'true') {
            return "Not inside a Git repository"
        }
        $commit = git rev-parse HEAD 2>$null
        $branch = git branch --show-current 2>$null
        if ([string]::IsNullOrWhiteSpace($branch)) {
            $branch = '(detached HEAD)'
        }
        $remoteUrl = git remote get-url origin 2>$null
        if ($LASTEXITCODE -ne 0) {
            $remoteUrl = $null
        }
        return "using commit $commit from branch $branch of repo $remoteUrl"
    }
    finally {
        Pop-Location
    }
}

function Set-MigrationRecord {
    [CmdletBinding()]
    param(
        [string]$HuduBaseUrl = $(Get-HuduBaseURL),
        [securestring]$HuduApiKey = $(Get-HuduApiKey),
        [string]$CheckOutinfo = $(Get-GitCheckoutInfo),
        [bool]$selfService = $([bool]::Parse(($env:selfservicemigration ?? "true"))),
        [string]$product = "ITBoost"

    )
    $response = $null
    $resolvedBaseUrl = $null
    $resolvedApiKey = $null
    $requestUri = $null

    try {
        if ([string]::IsNullOrWhiteSpace($HuduBaseUrl)) {
            throw "Hudu base URL is not set."
        }

        if ($null -eq $HuduApiKey) {
            throw "Hudu API key is not set."
        }

        $resolvedBaseUrl = $HuduBaseUrl.TrimEnd('/')
        $resolvedApiKey = (New-Object PSCredential 'user', $HuduApiKey).GetNetworkCredential().Password

        if ([string]::IsNullOrWhiteSpace($resolvedApiKey)) {
            throw "Resolved Hudu API key is empty."
        }
        $requestBody = @{
            product = $product
            self_service = $selfService
            version = $CheckOutinfo
        }
        $requestJson = $requestBody | ConvertTo-Json -Depth 5

        $requestUri = "$resolvedBaseUrl/api/v1/migrations"
        $response = Invoke-WebRequest `
            -Method Post `
            -Body $requestJson `
            -Uri $requestUri `
            -Headers @{ 'x-api-key' = $resolvedApiKey; 'Accept' = 'application/json' } `
            -ContentType 'application/json; charset=utf-8' `
            -SkipHttpErrorCheck `
            -ErrorAction Stop

        $statusCode = [int]$response.StatusCode
        if ($statusCode -lt 200 -or $statusCode -ge 300) {
            Write-Warning "Migration telemetry endpoint returned HTTP $statusCode at $requestUri. Response: $($response.Content)"
        }

     
    } catch {
       write-warning $_.exception.message
       return $false
    }

    return $true
}
