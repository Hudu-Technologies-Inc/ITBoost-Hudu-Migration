
foreach ($passwordSet in @(
    @{Type="Company"; Passwords=$ITBoostData.organizations.Matches.PasswordsToCreate},
    @{Type="Location"; Passwords=$ITBoostData.locations.Matches.PasswordsToCreate},
    @{Type="Contact"; Passwords=$ITBoostData.contacts.Matches.PasswordsToCreate},
    @{Type="Website"; Passwords=$ITBoostData.domains.Matches.PasswordsToCreate}
)) {
    Write-Host "$($passwordSet.Passwords.count) embedded passwords to add for type - $($passwordSet.type)"
}

foreach ($pass in $ITBoostData.passswords.csvdata){
    $matchedCompany = $huduCompanies | where-object {($_.name -eq $pass.name) -or [bool]$(Test-NameEquivalent -A $_.name -B $company)} | Select-Object -First 1
    $matchedCompany=$matchedCompany ?? $(Select-ObjectFromList -objects $huduCompanies -message "Which company to match for source company, named $company")
    $matchedPass = $allHuduPasswords | where-object {Test-NameEquivalent -A $_.name -B $pass.name} | Select-Object -First 1

    if ($matchedPass){
        $ITBoostData.passwords.Matches+=@{
            HuduID=$matchedPass.ID
            ITBID=$pass.id
            Company=$matchedCompany
            CompanyName=$pass.organization
            CsvRow=$pass.CsvRow
        }
    } else {
        $NewPasswordRequest = @{
            Name=$pass.name
            CompanyId=$matchedCompany.id
            Password=$pass.password
            Description="Imported from ITBoost."
        }
        if (-not [string]::IsNullOrEmpty($pass.notes)){$NewPasswordRequest["Description"]="$($NewPasswordRequest["Description"]); $($pass.notes)"}
        if (-not [string]::IsNullOrEmpty($pass.username)){$NewPasswordRequest["UserName"]=$pass.username}
        if (-not [string]::IsNullOrEmpty($pass.server)){
            $NewPasswordRequest.description="$($NewPasswordRequest.Description); Server: $($server)"
            $matchedAsset = Get-HuduAssets -CompanyId $matchedCompany.id | where-object {Test-NameEquivalent -A $_.name -B $pass.server -and $_.fields.values.ToLowerInvariant() -contains $pass.server.ToLowerInvariant()} | Select-Object -First 1
            if ($matchedAsset){
                $NewPasswordRequest["PasswordableType"]=$matchedAsset.asset_layout_id
                $NewPasswordRequest["PasswordableID"]=$matchedAsset.id
            }
        }
        if (-not [string]::IsNullOrEmpty($pass.username)){
            $matchedContact = Get-HuduAssets -AssetLayoutId $contactslayout.id -CompanyId $matchedCompany.id | Where-Object {Test-NameEquivalent -A $_.name -B $pass.username -or Test-NameEquivalent -A $_.name -B $pass.name } | Select-Object -First 1
            if ($matchedContact){
                $NewPasswordRequest["PasswordableType"]=$contactslayout.id
                $NewPasswordRequest["PasswordableID"]=$matchedcontact.id
            } 
        }
        try {
            $newPassword = $(New-HuduPassword @NewPasswordRequest).asset_password
        } catch {
            Write-Host "Error during password create $_"
        }
        if ($newPassword){
            $ITBoostData.passwords.Matches+=@{
                HuduID=$NewPassword.ID
                ITBID=$pass.id
                Company=$matchedCompany
                CompanyName=$pass.organization
                CsvRow=$pass.CsvRow
            }
        }
    }
}