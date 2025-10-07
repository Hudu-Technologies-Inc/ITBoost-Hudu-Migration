$MinConfidence     = 75
$MaxFilesPerRow    = 200  # safety cap
$AllowConvert = $allowConvert ?? $false
$sofficePath = $null
if ($allowConvert -eq $true){
    $sofficePath=$(if ($true -eq $portableLibreOffice) {$(Get-LibrePortable -tmpfolder $tmpfolder)} else {$(Get-LibreMSI -tmpfolder $tmpfolder)})
}

if ($ITBoostData.ContainsKey("documents")){

    $groupeddocuments = $ITBoostData.documents.CSVData | Group-Object { $_.organization } -AsHashTable -AsString
    try {
        $allHududocuments = Get-HuduArticles
    } catch {
        $allHududocuments=@()
    }
    $rootDocs = Join-Path $ITBoostExportPath 'documents'
    $folderIndex = Build-DocFolderIndex -Root $rootDocs
    $docToFolder = foreach ($row in $ITBoostData.documents.CSVData) {
        $match = Resolve-DocFolder -Row $row -Index $folderIndex

        [pscustomobject]@{
            itb_id     = $row.id
            name       = $row.name
            locator    = $row.locator
            folder     = $match?.Path
            confidence = $match?.Confidence
            reason     = $match?.Reason
        }
    }
    Write-Host "unresolved folders? $($docToFolder | Sort-Object { -not $_.folder }, @{e='confidence';d=$true} | Format-Table -AutoSize)"


    foreach ($company in $groupeddocuments.Keys) {
        write-host "starting $company"
        $documentsForCompany = $groupeddocuments[$company]
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
        foreach ($companydocument in $documentsForCompany){
            $matchedDocument = $allHududocuments | Where-Object {
                $_.company_id -eq $matchedCompany.id -and
                     $($(Test-NameEquivalent -A $_.name -B $companydocument.name) -or 
                     $([double]$(Get-SimilaritySafe -A $_.name -B $companydocument.name) -ge 0.90))}
            if ($matcheddocument){
                    if (-not $ITBoostData.documents.ContainsKey('matches')) { $ITBoostData.documents['matches'] = @() }
                    $ITBoostData.documents['matches'] += @{
                        CompanyName      = $companydocument.organization
                        CsvRow           = $companydocument.CsvRow
                        ITBID            = $companydocument.id
                        Name             = $companydocument.name
                        HuduID           = $matcheddocument.id
                        HuduObject       = $matcheddocument
                        HuduCompanyId    = $matcheddocument.company_id
                        PasswordsToCreate= ($companydocument.password ?? @())
                    }
                    continue
            } else {
                $newdocumentrequest=@{
                    Name="$($companydocument.name)".Trim()
                    CompanyID = $matchedCompany.id
                    Content="in-transit"
                }

                $match = Get-DocumentFilesForRow -Row $row -RootDocs $RootDocs -FolderIndex $FolderIndex
                if (-not $match -or $match.count -lt 1){
                    Write-Host "WARN, no candidates for $($companydocument.name) for $($companydocument.organization)"
                }

                # categorize once (avoid recomputing)
                $categorized = $match.files | ForEach-Object {
                [pscustomobject]@{
                    File     = $_
                    Category = Get-ExtensionCategory $_
                }
                }
                $directDocsNeeded =  $($categorized | where-object {$_.Category -eq "Web"})
                $imagesNeeded = $($categorized | where-object {$_.Category -eq "Image"})
                
                if ($true -eq $AllowConvert){
                    $uploadsNeeded = $($categorized | where-object {$_.Category -eq "NoConvert" -or $_.Category -eq "Unknown"})
                    $convertJobsNeeded = $($categorized | where-object {$_.Category -eq "Allowed"})
                } else {
                    $uploadsNeeded = $($categorized | where-object {$_.Category -eq "NoConvert" -or $_.Category -eq "Unknown"  -or $_.Category -eq "Allowed"})
                    $convertJobsNeeded = @()
                }


                $DocContents = "See Attachments for $($companydocument.name)"
                
                if ($directDocsNeeded -and $directDocsNeeded.count -gt 0){
                    $firstHtml = $($WebFiles |
                    ForEach-Object {
                        try {
                        $p = $_.FullName ?? $_
                        $t = Get-Content -LiteralPath $p -Raw -ErrorAction Stop
                        if ($t -match $pattern) { [pscustomobject]@{ Path = $p; Content = $t } }
                        } catch {}
                    } |
                    Select-Object -First 1)
                    if ($FirstHTML.Content -and -not ([string]::IsNullOrEmpty($FirstHTML.Content))){
                        $DocContents = $FirstHTML.Content
                        foreach ($uploadDoc in $directDocsNeeded | where-object {$_.File -ne $firstHtml.Path} ){
                            $uploadsNeeded+=$uploadDoc
                        }
                    }
                }
                $CreatedArticle = New-HuduArticle @newdocumentrequest
                $newdocumentrequest["Id"] = $CreatedArticle.article.id ?? $CreatedArticle.id
                $newdocumentrequest["Content"] = $DocContents
                $FoundExistingLinks = Get-LinksFromHTML -htmlContent $DocContents -title "$($companydocument.name)"

                
                $imagesCreated =@()
                $uploadsAdded =@()
                write-host "$($imagesNeeded.count) images needed for doc $($companydocument.name)"
                
                if ($true -eq $AllowConvert -and $sofficePath) {

                    
                }

                foreach ($imageUpload in $imagesNeeded){
                    $image=$(New-HuduUpload -companyId $matchedCompany.id -FilePath $imageUpload.File -uploadable_id $($newdocumentrequest["Id"]) -uploadable_type "Article")
                    $image = $image.upload ?? $image
                    if ($image){
                        $imagesCreated+=$image
                    } else {
                        Write-Host "Error on image $imageupload"
                    }
                }
                foreach ($HuduUpload in $uploadsNeeded){
                    $upload=$(New-HuduUpload -companyId $matchedCompany.id -FilePath $HuduUpload.File -uploadable_id $($newdocumentrequest["Id"]) -uploadable_type "Article")
                    $upload = $image.upload ?? $image
                    if ($upload){
                        $uploadsAdded+=$upload
                    } else {
                        Write-Host "Error on upload $imageupload"
                    }
                 }


                


                try {
                    $newdocument = Set-HuduArticle @newdocumentrequest
                } catch {
                    write-host "Error creating location: $_"
                }
                if ($newdocument){
                    $ITBoostData.documents["matches"]+=@{
                        CompanyName=$companydocument.organization
                        CsvRow=$companydocument.CsvRow
                        ITBID=$companydocument.id
                        Name=$companydocument.name
                        HuduID=$newdocument.id
                        HuduObject=$newdocument
                        HuduCompanyId=$newdocument.company_id
                        PasswordsToCreate=$($companydocument.password ?? @())
                    }            
                }
            }
        }
    }
 else {write-host "no documents in CSV! skipping."} 

}