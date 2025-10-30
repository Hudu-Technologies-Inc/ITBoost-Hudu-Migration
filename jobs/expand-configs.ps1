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


            if (@("ALL","IPAM-Only") -contains $ConfigExpansionMethod){
            # 1) harvest observations for this company
            $obs = Collect-CompanyIpObservations -ConfigCollection $ConfigCollection

            if (-not $obs -or $obs.Count -eq 0) {
                Write-Host "No IP observations for company '$($matchedCompany.name)'; skipping IPAM."
                continue
            }

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

            Write-Host "Ensuring Zone for $($matchedCompany.name)"
            $zone = Ensure-HuduVlanZone -CompanyId $matchedCompany.id -ZoneName 'Auto-Imported'

            # 3) ensure networks exist
            $ensuredNetworks = New-Object System.Collections.Generic.List[object]
            foreach ($cidr in $cidrs) {
                Write-Host "Processing Networks for cidr $($cidr)"
                $net = Ensure-HuduNetwork -CompanyId $matchedCompany.id -Address $cidr -Name $cidr -Description 'Auto-imported from configurations'
                if ($net) { $ensuredNetworks.Add($net) | Out-Null }
            }

            # Gather VLANs from observations
            $seenVlans = @($obs | ForEach-Object { $_.VlanIds } | Where-Object { $_ } | Select-Object -Unique)

            # Decide ranges for the zone
            $ranges = if ($seenVlans.Count -gt 0) {
            Compress-IntsToRanges -Ints $seenVlans
            } else {
            # no VLAN hints → create a zone with a broad default
            '1-4094'
            }

            $zone = Ensure-HuduVlanZone -CompanyId $matchedCompany.id -ZoneName 'Auto-Imported' -Ranges $ranges

            # Create VLANs only if we actually saw any
            if ($seenVlans.Count -gt 0) {
            foreach ($vid in $seenVlans) {
                if ($zone -and $zone.id) {
                Ensure-HuduVlan -CompanyId $matchedCompany.id -VlanId $vid -ZoneId $zone.id -Name "VLAN $vid" | Out-Null
                } else {
                Ensure-HuduVlan -CompanyId $matchedCompany.id -VlanId $vid -Name "VLAN $vid" | Out-Null
                }
            }
            }

            # Ensure networks only if any were inferred/created
            $ensuredNetworks = New-Object System.Collections.Generic.List[object]
            foreach ($cidr in $cidrs) {
            $net = Ensure-HuduNetwork -CompanyId $matchedCompany.id -Address $cidr -Name $cidr -Description 'Auto-imported from configurations'
            if ($net) { $ensuredNetworks.Add($net) | Out-Null }
            }


            
            # Build index only if we have networks
            $index = @()
            if ($ensuredNetworks.Count -gt 0) {
            $index = Build-NetworkIndex -Networks $ensuredNetworks
            }

            # Only attempt lookup if we have an index and the function is in scope
            if ($index.Count -gt 0 -and (Get-Command Find-NetworkForIp -ErrorAction SilentlyContinue)) {
            foreach ($o in $obs) {
                if ($o.Gateways -contains $o.IP) {
                $n = Find-NetworkForIp -Ip $o.IP -NetworkIndex $index -CompanyId $matchedCompany.id
                if ($n) {
                    Write-Host "processing gateways for IP $($o.IP) in network $($n.address)"
                    # (optional: annotate/default-gw handling here)
                }
                }
            }
            }
            $index = if ($ensuredNetworks.Count -gt 0) { Build-NetworkIndex -Networks $ensuredNetworks } else { @() }

            if ($index.Count -gt 0) {
            # dedupe just the IPs you want to persist
            $targetIps = $obs | ForEach-Object { $_.IP } | Where-Object { $_ } | Sort-Object -Unique
            foreach ($ip in $targetIps) {
                $net = Find-NetworkForIp -Ip $ip -NetworkIndex $index -CompanyId $matchedCompany.id
                if ($null -eq $net) { continue }

                $status = 'active'   # or infer from your source
                Ensure-HuduIPAddress -Address $ip -CompanyId $matchedCompany.id -NetworkId $net.id -Status $status | Out-Null
            }
            }            

            if (@("ALL","RichText-Field") -contains $ConfigExpansionMethod){
                # build html table from observations --- this is the easy part, use $obs-ervations or network$index




            }




        


        }
    }
}}