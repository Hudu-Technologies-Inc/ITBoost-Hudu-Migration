$PassProps = @{
resource_type= "PasswordType"
username = "Username"
password= "Password"
notes = "Description"
server = "URL"
}


if ($ITBoostData.ContainsKey("passwords")){
    $passwords = $ITBoostData.passwords.CSVData | Group-Object { $_.organization } -AsHashTable -AsString
    try {
        $allHudupasswords = Get-HuduPasswords
    } catch {
        $allHudupasswords=@()
    }
    foreach ($company in $passwords.Keys) {
        write-host "starting $company"
        $passwordsForCompany = $passwords[$company]
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
            $companypasswords =  Get-HuduPasswords -companyId $matchedCompany.id
            $companyAssets = Get-HuduAssets -CompanyId $matchedCompany.id
            $companyArticles = Get-HuduArticles -CompanyId $matchedCompany.id
            $companyWebsites = Get-HuduWebsites | where-object {$_.company_id -eq $matchedCompany.id}
        foreach ($companyPass in $passwordsForCompany){
                $matchedpassword = $companypasswords | Where-Object {Test-NameEquivalent -A $_.name -$companyPass.name} | select-object -first 1
                $matchedAsset =  $companyAssets | where-object {Test-NameEquivalent -A $_.name -B $companyPass.name} | select-object -first 1
                $matchedArticle = $companyArticles | where-object {Test-NameEquivalent -A $_.name -B $companyPass.name} | select-object -first 1
                $matchedWebsites= $companyWebsites | Where-Object {Test-NameEquivalent -A $($companyPass.server ?? $companypass.name) -B $_.name} | select-object -first 1
                    $NewPasswordRequest=@{
                    Name="$($companyPass.name)".Trim()
                    CompanyID = $matchedCompany.id
                }
                if ($matchedpassword){
                Write-host "matched pass $($matchedpassword.name)"
                $NewPasswordRequest["Id"] = $matchedpassword.id
                }

                if ($matchedAsset){
                    $asset = $matchedasset.asset ?? $matchedAsset
                    $NewPasswordRequest["passwordable_id"]=$asset.id
                    $NewPasswordRequest["passwordable_type"]="Asset"
                }
                elseif ($matchedArticle){
                    $NewPasswordRequest["passwordable_id"]=$matchedArticle.id
                    $NewPasswordRequest["passwordable_type"]="Article"
                elseif ($matchedWebsites){
                    $NewPasswordRequest["passwordable_id"]=$matchedCompany.id
                    $NewPasswordRequest["passwordable_type"]="Company"
                }
                foreach ($prop in $PassProps.keys){
                    if ([string]::IsNullOrEmpty($companypass.$prop)){continue}
                    $keyname = $PassProps[$prop]
                    $NewPasswordRequest[$keyname]=$companypass.$prop
                }


                try {
                    if ($NewPasswordRequest.ContainsKey("Id") -and $NewPasswordRequest["Id"] -gt 0){
                    $newpass = Set-HuduPassword @NewPasswordRequest
                    } else {
                    $newpass = New-HuduPassword @NewPasswordRequest
                    }
                } catch {
                    write-host "Error creating location: $_"
                }

            }
        }
    }
}