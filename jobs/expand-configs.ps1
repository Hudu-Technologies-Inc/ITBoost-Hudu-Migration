$configsMap = @{
model="model"
  modelo                   = "model"
configuration_type="configuration type"
resource_type="resource type"
configuration_status="configuration status"
hostname="hostname"
ptimary_ip="primary ip"
default_gateway="default gateway"
mac_address="macAddress"
serial_number="serial number"
asset_tag="asset tag"
manufacturer="manufacturer"
operating_system="operating system"
operating_system_notes="operating system notes"
position="position"
notes="notes"
installed_at="installed at"
purchased_at="purchased at"
warranty_expires_at="warranty expires at"
contact="contact"
configuration_interfaces="configuration interfaces"
}

function Build-RowMergedMap {
  <#
    From a set of raw CSV rows and your configsMap, pick the first meaningful value
    seen for each mapped label. Returns @{ <Label> = <Value> }.
  #>
  param(
    [Parameter(Mandatory)][hashtable]$ConfigsMap,
    [Parameter(Mandatory)][object[]]$Rows
  )

  $result = @{}
  foreach ($csvKey in $ConfigsMap.Keys) {
    $label = [string]$ConfigsMap[$csvKey]
    if ([string]::IsNullOrWhiteSpace($label)) { continue }

    $picked = $null
    foreach ($r in $Rows) {
      # handle both exact and “variant” key spellings (e.g., mac_address vs macAddress)
      $candidate = $r.$csvKey
      if ($null -eq $candidate) {
        # try a loose fallback: search by case-insensitive property name
        $prop = ($r.PSObject.Properties | Where-Object { Test-NameEquivalent -A $_.Name -B $csvKey }).Value
        $candidate = $prop
      }

      if ($null -ne (Get-FirstPresent $candidate)) { $picked = $candidate; break }
    }

    if ($null -ne $picked) {
      # string trim
      if ($picked -is [string]) { $picked = $picked.Trim() }
      $result[$label] = $picked
    }
  }

  return $result
}


$configsLayout = $allHuduLayouts | Where-Object { ($(Get-NeedlePresentInHaystack -needle "config" -haystack $_.name) -or $(Get-NeedlePresentInHaystack -needle "people" -Haystack $_.name)) } | Select-Object -First 1; $configsLayout = $configsLayout.asset_layout ?? $configsLayout
$ConfigExpansionMethod = $ConfigExpansionMethod ?? $(Select-ObjectFromList -message "Which Expansion Method for Config Data?" -objects @("IPAM-Only","RichText-Field","ALL"))
$ConfigurationsHaveBeenApplied = $true
$ConfigsRichTextOverviewField = "Additional Information"

$FieldsAsArrays = @(
    "primary_ip",
    "default_gateway",
    "mac_address",
    "hostname",
    "configuration_interfaces"
)

if ($ITBoostData.ContainsKey("configurations") -and $true -eq $ConfigurationsHaveBeenApplied){
    $namesSeen = @()   
    $huduCompanies = $huduCompanies ?? $(get-huducompanies)
    $configsLayout = Get-HuduAssetLayouts -id $configsLayout.id; $configsLayout = $configsLayout.asset_layout ?? $configsLayout
    if (@("ALL","RichText-Field") -contains $ConfigExpansionMethod){
            $OverviewField = $configsLayout.fields | where-object {$_.label -eq $ConfigsRichTextOverviewField -and $_.field_type -eq "RichText"} | Select-Object -First 1
            if ($OverviewField){
                Write-Host "Additional Data richtext field is $($OverviewField.label) / $($OverviewField.id)"
            } else {
                $UpdateFields=@()
                foreach ($f in $configsLayout.fields){
                    $UpdateFields+=$f
                }
                $UpdateFields+=@{label=$ConfigsRichTextOverviewField; field_type = "RichText"; show_in_list = $true; expiration=$false; required=$false; position=259;}
                Set-HuduAssetLayout -id $configsLayout.id -fields $UpdateFields
                $configsLayout = Get-HuduAssetLayouts -id $configsLayout.id; $configsLayout = $configsLayout.asset_layout ?? $configsLayout
            }
    }
    $allHuduConfigs = Get-HuduAssets -AssetLayoutId $configsLayout.id


    $configsFields = $configsLayout.fields
    $uniqueCompanies = $ITBoostData.configurations.CSVData |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.organization) } | Select-Object -ExpandProperty organization -Unique

    $ByCompanyById     = @{}
    $ByCompanyBySerial = @{}
    Write-Host "Processing and joining data from CSV for $($ITBoostData.configurations.CSVData) rows; please be patient, this can take a long time."

    foreach ($row in $ITBoostData.configurations.CSVData) {
        if ([string]::IsNullOrWhiteSpace($row.organization)) { continue }
        $co = $row.organization.Trim()

        if (-not $ByCompanyById.ContainsKey($co))     { $ByCompanyById[$co]     = @{} }
        if (-not $ByCompanyBySerial.ContainsKey($co)) { $ByCompanyBySerial[$co] = @{} }

        if ($row.id) {
            if (-not $ByCompanyById[$co].ContainsKey($row.id)) { $ByCompanyById[$co][$row.id] = @() }
            $ByCompanyById[$co][$row.id] += $row
        }

        if ($row.serial_number) {
            if (-not $ByCompanyBySerial[$co].ContainsKey($row.serial_number)) { $ByCompanyBySerial[$co][$row.serial_number] = @() }
            $ByCompanyBySerial[$co][$row.serial_number] += $row
        }
    }
    $uniqueCompanies = @($ByCompanyById.Keys + $ByCompanyBySerial.Keys | Select-Object -Unique)

    Write-Host "Joining config data for $($uniqueCompanies.count) companies, $($ConfigsGroupedBySerial.Keys.Count) serials"
    
    foreach ($company in $uniqueCompanies) {

        Write-Host "starting $company"

        $matchedCompany = $huduCompanies | Where-Object {
            ($_.name -eq $company) -or
            [bool](Test-NameEquivalent -A $_.name     -B "*$company*") -or
            [bool](Test-NameEquivalent -A $_.nickname -B "*$company*")
        } | Select-Object -First 1
        $matchedCompany = $matchedCompany ?? (Get-HuduCompanies -Name $company | Select-Object -First 1)
        if (-not $matchedCompany.id) { Write-Host "NO COMPANY matched for $company"; continue }

        $groupsForCompany = $ByCompanyById[$company]
        if (-not $groupsForCompany) { Write-Host "No ID groups for $company"; continue }

        foreach ($kv in $groupsForCompany.GetEnumerator()) {
            $groupId = $kv.Key
            $rows    = $kv.Value

            if ($rows.Count -le 1) {
                Write-Host "Not enough configs to merge for $groupId, expanding singularly"
            }
            $individual = $rows[0]

            $matchedConfig = $allHuduConfigs |
                Where-Object { $_.company_id -eq $matchedCompany.id -and (Test-NameEquivalent -A $_.name -B $individual.name) } |
                Select-Object -First 1
            $matchedConfig = $matchedConfig ?? (Get-HuduAssets -AssetLayoutId $configsLayout.id -CompanyId $matchedCompany.id -Name $individual.name | Select-Object -First 1)

            if (-not $matchedConfig) {
                Write-Host "No Match Found in all of configs for $groupId"
                continue
            }

            $ConfigCollection = @()
            foreach ($matchedById in $rows) {
                $configCollectionEntry = @{}
                foreach ($collectionProp in $FieldsAsArrays) {
                    $configCollectionEntry[$collectionProp] = $matchedById.$collectionProp
                }
                $ConfigCollection += $configCollectionEntry
            }
            $ensuredNetworks = New-Object System.Collections.Generic.List[object]
            $EnsuredIPAddresses = New-Object System.Collections.Generic.List[object]

            if (@("ALL","IPAM-Only") -contains $ConfigExpansionMethod){
            # 1) harvest observations for this company
            $obs = Collect-CompanyIpObservations -ConfigCollection $ConfigCollection

            if (-not $obs -or $obs.Count -eq 0) {
                Write-Host "No IP observations for company '$($matchedCompany.name)'; skipping IPAM."
            } else {

            # 2) propose CIDRs
            $cidrs = Guess-NetworksFromObservations -Observations $obs
            Write-Host "$($cidrs.count) observed cidrs in org $($matchedCompany.name)"
            if (-not $cidrs -or $cidrs.Count -eq 0) {
                Write-Host "No candidate networks inferred for '$($matchedCompany.name)';"
            } else {
                Write-Host "Inferred $($cidrs.Count) candidate networks for $($matchedCompany.name): $($cidrs -join ', ')"
            }

            #### LONE PUBLIC HOST
            if (($cidrs.Count -eq 0) -and ($obs.Count -gt 0)) {
                $publicSingles = $obs | Where-Object { -not (Test-Rfc1918 -Ip $_.IP) } |
                                            Select-Object -ExpandProperty IP -Unique
                foreach ($p in $publicSingles) {
                    $net = Ensure-HuduNetwork -CompanyId $matchedCompany.id -Address $p -Description 'Auto-imported (public host)'
                    if ($net) { $ensuredNetworks.Add($net) | Out-Null }
                }
            }

            foreach ($cidr in $cidrs) {
                Write-Host "Processing Networks for cidr $($cidr)"
                $net = Ensure-HuduNetwork -CompanyId $matchedCompany.id -Address $cidr -Name $cidr -Description 'Auto-imported from configurations'
                if ($net) { $ensuredNetworks.Add($net) | Out-Null }
            }
            $index = @()
            if ($ensuredNetworks.Count -gt 0) {
                $index = Build-NetworkIndex -Networks $ensuredNetworks
            }

            }
            $index = if ($ensuredNetworks.Count -gt 0) { Build-NetworkIndex -Networks $ensuredNetworks } else { @() }

            if ($index.Count -gt 0) {
            $targetIps = $obs | ForEach-Object { $_.IP } | Where-Object { $_ } | Sort-Object -Unique
            foreach ($ip in $targetIps) {
                $net = Find-NetworkForIp -Ip $ip -NetworkIndex $index -CompanyId $matchedCompany.id
                if ($null -eq $net) { continue }

                $status = 'active'   
                $ipObj = Ensure-HuduIPAddress -Address $ip -CompanyId $matchedCompany.id -AssetId $matchedconfig.id -NetworkId $net.id -Status $status
                if ($ipObj) { $EnsuredIPAddresses.Add($ipObj) | Out-Null }
            }
            }}

            if (@("ALL","RichText-Field") -contains $ConfigExpansionMethod){
                $fieldsRequest=@()
                foreach ($f in $configsLayout.fields | where-object {$_.label -ne $ConfigsRichTextOverviewField}){
                    $value = $($matchedconfig.fields | where-object {Test-NameEquivalent -A $_.label -B $f.label} | Select-Object -First 1)?.value ?? $null
                    $value = $value ?? $(Build-RowMergedMap -ConfigsMap $configsMap -Rows $rows)["$($f.label)"]
                    if ($null -ne $value){
                    
                        $fieldsRequest+=@{$f.label = $value}
                    }
                }


                if ($obs) {
                # Build the “interfaces” mini-table from your collection
                $obsHtml = Convert-ObjectsToHtmlTable -Items $obs -Title 'Observed IPs'

                $summaryMap = @{
                Observed                 = $obsHtml
                gateways                 = $ConfigCollection["default_gateway"]
                configuration_interfaces = $ConfigCollection["configuration_interfaces"]
                interfaces               = $ConfigCollection["primary_ip"]
                }

                if ($ensuredNetworks -and $ensuredNetworks.Count -ge 1) {
                $netHtml = Convert-ObjectsToHtmlTable -Items $ensuredNetworks -Title 'Networks' -Columns @('name','company_id','url')
                $summaryMap["Networks"] = $netHtml
                }
                if ($EnsuredIPAddresses -and $EnsuredIPAddresses.Count -ge 1) {
                $ipHtml = Convert-ObjectsToHtmlTable -Items $EnsuredIPAddresses -Title 'IP Addresses' -Columns @('address','status','url')
                $summaryMap["Addresses"] = $ipHtml
                }

                $richTextOverview = Convert-MapToHtmlTable -Title "$ConfigsRichTextOverviewField for $($matchedConfig.name)" -Map $summaryMap  -RawHtmlValueKeys @('Observed','Networks','Addresses') 

                $fieldsRequest += @{ $ConfigsRichTextOverviewField = $richTextOverview }
                }

                
                Set-HuduASset -id $matchedconfig.id -fields $fieldsRequest
            }
        }
    }
}