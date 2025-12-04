$MinConfidence     = 75
$MaxFilesPerRow    = 200  # safety cap
$AllowConvert = $allowConvert ?? $false
$URLReplacement = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
if (-not $pattern) { $pattern = '(?is)(<!doctype\s+html|<html\b|<meta[^>]+charset\s*=\s*["'']?utf-?8|content=["''][^"'']*text/html)' }


function Add-Replacement {
  param([string]$Key, [string]$Value)
  if ([string]::IsNullOrWhiteSpace($Key) -or [string]::IsNullOrWhiteSpace($Value)) { return }
  if (-not $URLReplacement.ContainsKey($Key)) { $URLReplacement[$Key] = $Value }
}
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
        $documentsForCompany = $groupeddocuments[$company]
        write-host "starting $company with $($documentsForCompany.count) docs"
        $matchedCompany = Get-HuduCompanyFromName -CompanyName $company -HuduCompanies $huduCompanies
        if (-not $matchedCompany -or -not $matchedCompany.id -or $matchedCompany.id -lt 1) { continue }
        foreach ($companydocument in $documentsForCompany){
            $matchedDocument = $null
            $matchedDocument = $allHududocuments | Where-Object {
                $_.company_id -eq $matchedCompany.id -and
                     $($(Test-NameEquivalent -A $_.name -B $companydocument.name) -or 
                     $([double]$(Get-SimilaritySafe -A $_.name -B $companydocument.name) -ge 0.90))} | Select-Object -first 1
            $matchedDocument = $matchedDocument ?? $($(Get-HuduArticles -CompanyId $matchedCompany.id -name $companydocument.name) | Select-Object -first 1)
            
                $newdocumentrequest=@{
                    Name="$($companydocument.name)".Trim()
                    CompanyID = $matchedCompany.id
                    Content="See Attachments for $($companydocument.name)"
                }
            if ($matcheddocument){
                Write-Host "matched $($companydocument.name) to doc in Hudu @ $($matchedDocument.url); updating"
                    # if (-not $ITBoostData.documents.ContainsKey('matches')) { $ITBoostData.documents['matches'] = @() }
                    # $ITBoostData.documents['matches'] += @{
                    #     CompanyName      = $companydocument.organization
                    #     CsvRow           = $companydocument.CsvRow
                    #     ITBID            = $companydocument.id
                    #     Name             = $companydocument.name
                    #     HuduID           = $matcheddocument.id
                    #     HuduObject       = $matcheddocument
                    #     HuduCompanyId    = $matcheddocument.company_id
                    #     PasswordsToCreate= ($companydocument.password ?? @())
                    # }
                    # continue
            } 
                $imagesCreated = @()
                $uploadsAdded  = @()
                $firstHtml = $null
                $OutFile = "$docs_folder\$($companydocument.resource_id).html"

                

                if ($matchedDocument){
                    $newdocumentrequest["Id"]=$matchedDocument.id
                }

                $match = Get-DocumentFilesForRow -Row $companydocument -RootDocs $RootDocs -FolderIndex $FolderIndex
                if (-not $match -or -not $match.files -or $match.files.Count -eq 0) {
                    Write-Host "WARN, no candidates for '$($companydocument.name)' ($($companydocument.organization))"
                    continue
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
                
                if ($AllowConvert -and $sofficePath) {
                    $uploadsNeeded     = $categorized | Where-Object { $_.Category -in @('NoConvert','Unknown') }
                    $convertJobsNeeded = $categorized | Where-Object { $_.Category -eq 'Allowed' }
                } else {
                    $uploadsNeeded     = $categorized | Where-Object { $_.Category -in @('NoConvert','Unknown','Allowed') }
                    $convertJobsNeeded = @()
                }


                foreach ($related in @(
                    @{name="convertables"; count=$convertJobsNeeded.count}
                    @{name="uploadables"; count=$uploadsNeeded.count}
                    @{name="images/graphics"; count=$imagesNeeded.count}
                    @{name="Web/HTML Docs"; count=$directDocsNeeded.count}
                )){Write-Host "$($related.name) - $($related.count) found for $($companydocument.name)"}

                $DocContents = "See Attachments for $($companydocument.name)"
                if ($directDocsNeeded.Count -gt 0) {
                try {
                      $firstHtmlPath = ($directDocsNeeded[0].File.FullName ?? $directDocsNeeded[0].File)
                    $DocContents   = Get-Content -LiteralPath $firstHtmlPath -Raw -Encoding UTF8
                    $firstHtml     = [pscustomobject]@{ Path = $firstHtmlPath; Content = $DocContents }
                } catch {
                    Write-Error "Error getting doc contents $_"
                }
                }
                $DocContents = As-HtmlString $DocContents

                # parse with COM safely



                if ($uploadsNeeded.count -lt 1 -and $imagesNeeded.count -lt 1 -and $convertJobsNeeded.count -lt 1 -and $DocContents -ilike "See Attachments for*"){
                    write-host "Doc with $($match.files) does not have any content or uploadables!"
                    continue
                }


                if (-not $matchedDocument){
                    $CreatedArticle = New-HuduArticle @newdocumentrequest
                    $newdocumentrequest["Id"] = $CreatedArticle.article.id ?? $CreatedArticle.id
                }

                # $FoundExistingLinks = Get-LinksFromHTML -htmlContent $DocContents -title "$($companydocument.name)"

                write-host "$($imagesNeeded.count) images needed for doc $($companydocument.name)"
                
                if ($true -eq $AllowConvert -and $sofficePath) {

                    # todo - convert
                }

                $existingRelated = Get-Huduuploads | where-object {$_.uploadable_type -eq "Article" -and [string]$_.uploadable_id -eq [string]$newdocumentrequest["Id"]}
                # IMAGES
                foreach ($imageUpload in $imagesNeeded) {
                    $existingupload = $existingRelated | where-object {Test-NameEquivalent -A $_.name -B "$([IO.Path]::GetFileName(($imageUpload.File.FullName ?? $imageUpload.File)))".Trim()} | select-object -first 1
                    if ($existingupload -and $existingupload.url){
                        Add-REplacement "$([IO.Path]::GetFileName(($up.File.FullName ?? $up.File)))" $existingupload.url
                        write-host "Existing image $($existingupload.url) for $($companydocument.name)"
                        continue
                    }

                    $srcPath = Get-AbsolutePath -PathOrInfo $imageUpload.File -BaseFolder $match.folder
                    if (-not (Test-Path -LiteralPath $srcPath)) { Write-Warning "Missing image: $srcPath"; continue }                    
                    $imgUp = New-HuduUpload -FilePath $srcPath `
                                            -Uploadable_Id $newdocumentrequest['Id'] `
                                            -Uploadable_Type 'Article'
                    $imgUp = $imgUp.upload ?? $imgUp
                    if (-not $imgUp) { Write-Host "Error on image $($imageUpload.File)"; continue }

                    $repUrl = $imgUp.public_photo_url ?? $imgUp.publicPhotoUrl ?? $imgUp.url
                    $fn     = Split-Path -Leaf $imageUpload.File
                    Add-Replacement $fn $repUrl
                    foreach ($src in @($imageUpload.SourceUrls)) { if ($src) { Add-Replacement $src $repUrl } }
                }

                # NON-IMAGE UPLOADS
                foreach ($up in $uploadsNeeded) {
                    $existingupload = $existingRelated | where-object {Test-NameEquivalent -A $_.name -B "$([IO.Path]::GetFileName(($up.File.FullName ?? $up.File)))".Trim()} | select-object -first 1
                    if ($existingupload -and $existingupload.url){
                        Add-REplacement "$([IO.Path]::GetFileName(($up.File.FullName ?? $up.File)))" $existingupload.url
                        write-host "Existing upload $($existingupload.url) for $($companydocument.name)"
                        continue
                    }

                    $srcPath = Get-AbsolutePath -PathOrInfo $up.File -BaseFolder $match.folder
                    if (-not (Test-Path -LiteralPath $srcPath)) { Write-Warning "Missing upload: $srcPath"; continue }

                    $u = New-HuduUpload -FilePath $srcPath `
                                        -Uploadable_Id $newdocumentrequest['Id'] `
                                        -Uploadable_Type 'Article'
                    $u = $u.upload ?? $u
                    if (-not $u) { Write-Host "Error on upload $($up.File)"; continue }

                    $repUrl = $u.url
                    $fn     = Split-Path -Leaf $up.File
                    Add-Replacement $fn $repUrl
                    foreach ($src in @($up.SourceUrls)) { if ($src) { Add-Replacement $src $repUrl } }
                }
                $DocContents.GetType().FullName
                $DocContents.Length
                if ($firstHtmlpath) {
                    $DocContents = Rewrite-InlineLinksAndImages -InFile $firstHtmlPath -Lookup $URLReplacement 
                } 
                $newdocumentrequest['Content'] = As-HtmlString $DocContents

                


                try {
                    Write-host "$($($newdocumentrequest | convertto-json).ToString())"
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