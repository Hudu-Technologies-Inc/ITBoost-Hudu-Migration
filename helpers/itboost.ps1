
function Set-PasswordsFromEmbeddedCSVobjects {
    param (
        [hashtable]$itboostdata,
        [validateset("organizations","contacts","configurations","ssl-certificates","domains","documents","locations" )][string]$keyname
    )


    $objectswithpasswords = $itboostdata."$($keyname)".csvdata | Where-Object {$_.password -ne $null -and $_.password -ne "" -and $_.password -ne "[]"}

    $groupedObjectsWithPasswords = $objectswithpasswords | Group-Object { $_.organization } -AsHashTable -AsString

    $configsLayout = Get-HuduAssetLayouts | Where-Object { $_.name -ieq "configs" } | Select-Object -First 1; $configsLayout = $configsLayout.asset_layout ?? $configsLayout;
    $LocationLayout = $locationlayout ?? $(Get-HuduAssetLayouts | Where-Object { $_.name -ieq "location" -or $_.name -ieq "locations" } | Select-Object -First 1); $LocationLayout = $LocationLayout.asset_layout ?? $LocationLayout;
    $contactsLayout = $contactsLayout ?? $($(get-huduassetlayouts) | Where-Object { $_.name -ieq "people" -or $_.name -ieq "contacts" } | Select-Object -First 1); $contactsLayout = $contactslayout.asset_layout ?? $contactslayout;
    $embeddedpassescreated = @()
    foreach ($company in $groupedObjectsWithPasswords.Keys) {
        $couldbeglobal = $false
        $passwordableType = "None"
        if ([string]::IsNullOrWhiteSpace($company)) {
            $matchedCompany = $internalCompany
            $couldbeglobal = $true
            Write-Host "No company specified for some passwords, assigning to internal company" -ForegroundColor Yellow
        }
        else {
            $matchedCompany = Get-HuduCompanyFromName -CompanyName $company -HuduCompanies $huduCompanies -existingIndex ($ITBoostData.organizations["matches"] ?? $null)

            if (-not $matchedCompany -or -not $matchedCompany.id -or $matchedCompany.id -lt 1) {
                $matchedCompany = $internalCompany
                $couldbeglobal = $true
            }
        }

        if ($keyname -eq "organizations") {
            $companyObjects = @()
            $passwordableType = "None"  
        } elseif ($keyname -eq "contacts"){
            $companyObjects = Get-HuduAssets -CompanyId $matchedCompany.id -AssetLayoutId $contactslayout.id
            $passwordableType = "Asset"  
        } elseif ($keyname -eq "configurations"){
            $companyObjects = Get-HuduAssets -CompanyId $matchedCompany.id -AssetLayoutId $configsLayout.id
            $passwordableType = "Asset"  
        } elseif ($keyname -eq "ssl-certificates" -or $keyname -eq "domains"){
            $companyobjects = get-huduwebsites | where-object {$_.company_id -eq $matchedcompany.id}
            $passwordableType = "Website"
        } elseif ($keyname -eq "documents"){
            if ($true -eq $couldbeglobal){
                $companyobjects = get-huduarticles | where-object {$null -eq $_.company_id -or $_.company_id -eq $matchedcompany.id}
            } else {
                $companyobjects = get-huduarticles -companyId $matchedcomany.id
            }
            $passwordableType = "Article"
        } elseif ($keyname -eq "locations"){
            $companyObjects = Get-HuduAssets -CompanyId $matchedCompany.id -AssetLayoutId $LocationLayout.id
            $passwordableType = "Asset"  
        }
        Write-Host "Starting $keyname pass-embeds for company '$($matchedCompany.name)' with $($companyObjects.Count)"

        foreach ($objectWithPasswords in $groupedObjectsWithPasswords[$company]) {
            $matchedObj = $companyObjects | Where-Object {
                Test-Equiv -A $_.name -B $objectWithPasswords.name
            } | Select-Object -First 1

            $passwordsEmbedded = @(safedecode $objectWithPasswords.password)

            Write-Host "Matched $keyname '$($matchedObj.name)' has $($passwordsEmbedded.Count) passwords"

            foreach ($configsPassword in $passwordsEmbedded) {
                $newPasswordRequest = @{
                    Name      = "$($configsPassword.passwordName)".Trim()
                    CompanyId = $matchedCompany.id
                    Password  = $configsPassword.password
                }
                $existingpass = $null; $existingPass = get-hudupasswords -CompanyId $matchedCompany.id | Where-Object {
                    $_.name -ieq $newPasswordRequest.Name -and $_.passwordable_type -ieq $passwordableType
                } | Select-Object -First 1
                $existingpass = $existingpass.asset_password ?? $existingpass
                if ($existingPass) {
                    Write-Host "Password '$($newPasswordRequest.Name)' already exists for company '$($matchedCompany.name)' and type '$passwordableType', skipping creation." -ForegroundColor Yellow
                    continue
                }


                if (-not [string]::IsNullOrEmpty($configsPassword.userName)) {
                    $newPasswordRequest.Username = $configsPassword.userName
                }

                if (-not [string]::IsNullOrEmpty($configsPassword.server)) {
                    $newPasswordRequest.URL = $configsPassword.server   # or Website/Host/etc. based on your cmdlet
                }

                if ($matchedObj) {
                    $newPasswordRequest.passwordable_id = $matchedObj.id
                    $newPasswordRequest.passwordable_type = "Asset"
                }

                Write-Host ($newPasswordRequest | ConvertTo-Json -Depth 99)

                try {
                    $newPass = New-HuduPassword @newPasswordRequest
                    $embeddedpassescreated+=$newPass
                    Write-Host ("Created: {0}" -f ($newPass | ConvertTo-Json -Depth 5))
                }
                catch {
                    Write-Host ("Error creating password for config '{0}': {1}" -f $objectWithPasswords.name, $_.Exception.Message) -ForegroundColor Red
                }
            }
        }
    }
    return $embeddedpassescreated

}
