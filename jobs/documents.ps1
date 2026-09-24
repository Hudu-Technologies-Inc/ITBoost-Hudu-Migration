$MinConfidence     = 75
$MaxFilesPerRow    = 200  # safety cap
$AllowConvert = $allowConvert ?? $false
$URLReplacement = @{}
if (-not $pattern) { $pattern = '(?is)(<!doctype\s+html|<html\b|<meta[^>]+charset\s*=\s*["'']?utf-?8|content=["''][^"'']*text/html)' }

if ($CleanupDupes -and $CleanupDupes -eq $true){Clear-DupeDocuments -huduarticles $(get-huduarticles) -huduuploads $(get-huduuploads)}
$DeleteDocsMode = $DeleteDocsMode ?? $false

function Get-DocumentHuduMediaUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$InputObject,
        [ValidateSet('Upload','PublicPhoto')][string]$MediaKind = 'Upload',
        [string]$HuduBaseUrl
    )

    $media = $InputObject
    if (Get-Command -Name Unwrap-HuduResultObject -ErrorAction SilentlyContinue) {
        $media = Unwrap-HuduResultObject -InputObject $media -WrapperNames @('upload', 'Upload', 'public_photo', 'PublicPhoto')
    } else {
        $media = $media.upload ?? $media.Upload ?? $media.public_photo ?? $media.PublicPhoto ?? $media
    }

    $url = $media.public_photo_url ?? $media.publicPhotoUrl ?? $media.public_url ?? $media.publicUrl ?? $media.url ?? $media.file_url ?? $media.fileUrl ?? $media.cdn_url ?? $media.cdnUrl
    if (-not $url -and $MediaKind -eq 'PublicPhoto') {
        $id = if (Get-Command -Name Get-HuduObjectId -ErrorAction SilentlyContinue) { Get-HuduObjectId -InputObject $media } else { $media.id ?? $media.Id }
        if ($id) { $url = "/public_photo/$id" }
    }

    if ($url -and (Get-Command -Name Convert-HuduMediaUrlToRelative -ErrorAction SilentlyContinue)) {
        $url = Convert-HuduMediaUrlToRelative -Url $url -HuduBaseUrl $HuduBaseUrl
    }

    return $url
}

function New-DocumentImagePublicPhoto {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][int]$ArticleId
    )

    if (-not (Get-Command -Name New-HuduPublicPhoto -ErrorAction SilentlyContinue)) {
        throw "New-HuduPublicPhoto is required for document image embeds; update HuduAPI before running the documents job."
    }

    $publicPhoto = New-HuduPublicPhoto -FilePath $FilePath -RecordType 'Article' -RecordId $ArticleId
    $url = Get-DocumentHuduMediaUrl -InputObject $publicPhoto -MediaKind PublicPhoto -HuduBaseUrl $HuduBaseURL
    if (-not $url) {
        throw "Public photo upload returned no usable URL for: $FilePath"
    }

    [pscustomobject]@{ PublicPhoto = $publicPhoto; Url = $url }
}
function Add-Replacement {
  param([string]$Key, [string]$Value)
  if ([string]::IsNullOrWhiteSpace($Key) -or [string]::IsNullOrWhiteSpace($Value)) { return }
  if (-not $URLReplacement.ContainsKey($Key)) { $URLReplacement[$Key] = $Value }
}

function Add-DocumentReplacementKeys {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string]$Url,
        [string[]]$SourceUrls = @()
    )

    $leaf = Split-Path -Leaf $FilePath
    $base = [IO.Path]::GetFileNameWithoutExtension($leaf)
    foreach ($key in @($leaf, $base, [uri]::EscapeDataString($leaf), [uri]::EscapeDataString($base))) {
        Add-Replacement $key $Url
    }

    foreach ($src in @($SourceUrls)) {
        if ([string]::IsNullOrWhiteSpace($src)) { continue }
        Add-Replacement $src $Url
        Add-Replacement (($src -split '[?#]', 2)[0]) $Url

        try {
            $uri = if ($src -match '^(?i)https?://') { [uri]$src } else { $null }
            if ($uri) {
                Add-Replacement $uri.AbsoluteUri $Url
                Add-Replacement $uri.AbsolutePath.TrimStart('/') $Url
                Add-Replacement ([IO.Path]::GetFileName($uri.AbsolutePath)) $Url
            } else {
                Add-Replacement ([IO.Path]::GetFileName(($src -split '[?#]', 2)[0])) $Url
            }
        } catch {}
    }
}

function Add-GlobalImageReplacements {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RawHtml,
        [Parameter(Mandatory)][int]$ArticleId,
        [Parameter(Mandatory)][string]$ITBoostExportPath
    )

    $pattern = @"
(?<attr>src|href)\s*=\s*(?<q>["'])(?<url>(?:https?:\/\/[^"']+)?(?:\.{1,2}\/)*global\/doc\/images\/(?<name>[^"\/?#]+)(?:\?[^"']*)?)(?<q2>\k<q>)
"@

    $rx = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $matches = @($rx.Matches($RawHtml))
    if ($matches.Count -eq 0) {
        Write-Host "Found 0 global images"
        return @{}
    }

    $sourceUrlsByName = @{}
    foreach ($m in $matches) {
        $name = $m.Groups['name'].Value
        $url = $m.Groups['url'].Value
        if (-not $sourceUrlsByName.ContainsKey($name)) { $sourceUrlsByName[$name] = @() }
        $sourceUrlsByName[$name] = @($sourceUrlsByName[$name] + $url | Sort-Object -Unique)
    }

    $imageNames = $sourceUrlsByName.Keys | Sort-Object -Unique
    Write-Host "Found $($imageNames.Count) global images: $($imageNames -join ', ')"

    $byName = @{}
    Get-ChildItem -Path $ITBoostExportPath -File -Recurse -ErrorAction Stop | ForEach-Object {
        if (-not $byName.ContainsKey($_.Name)) { $byName[$_.Name] = $_.FullName }
    }

    $newUrlByName = @{}
    foreach ($name in $imageNames) {
        $srcPath = $byName[$name]
        if (-not $srcPath -or -not (Test-Path -LiteralPath $srcPath)) {
            Write-Warning "Missing global image file for: $name"
            continue
        }

        try {
            $uploaded = New-DocumentImagePublicPhoto -FilePath $srcPath -ArticleId $ArticleId
            Add-DocumentReplacementKeys -FilePath $srcPath -Url $uploaded.Url -SourceUrls $sourceUrlsByName[$name]
            $newUrlByName[$name] = $uploaded.Url
            Write-Host "Uploaded global image $name -> $($uploaded.Url)"
        } catch {
            Write-Warning "Failed to upload global image '$name' as a public photo: $($_.Exception.Message)"
        }
    }

    return $newUrlByName
}

function Get-UnresolvedDocumentImageSources {
    [CmdletBinding()]
    param([AllowNull()][string]$Html)

    if ([string]::IsNullOrWhiteSpace($Html)) { return @() }

    $srcPattern = '(?is)<img\b[^>]*\bsrc\s*=\s*["'']?(?<src>[^"''\s>]+)'
    @([regex]::Matches($Html, $srcPattern) | ForEach-Object {
        $src = $_.Groups['src'].Value
        if (
            -not [string]::IsNullOrWhiteSpace($src) -and
            $src -notmatch '^(?i)(https?:|data:|blob:|cid:|/public_photo/|/file/)' -and
            $src -notmatch '^(?i)#'
        ) {
            $src
        }
    } | Sort-Object -Unique)
}
$sofficePath = $null
if ($allowConvert -eq $true){
    $sofficePath=$(if ($true -eq $portableLibreOffice) {$(Get-LibrePortable -tmpfolder $tmpfolder)} else {$(Get-LibreMSI -tmpfolder $tmpfolder)})
}

# load companies index if available
$ITBoostData.organizations["matches"] = $ITBoostData.organizations["matches"] ?? $(get-content $companiesIndex -Raw | convertfrom-json -depth 99) ?? @()

if (-not $ITBoostData.ContainsKey("documents") -or -not $ITBoostData.documents.CSVData){write-host "no documents recorded in ITBoost data, skipping"; return}
if (-not $ITBoostData.documents.ContainsKey('matches')) { $ITBoostData.documents['matches'] = @() }
$ITBoostData.documents['matches'] = @($ITBoostData.documents['matches'] ?? @())

$groupeddocuments = $ITBoostData.documents.CSVData | Group-ObjectSafeHashTable { $_.organization } -BlankKey "$internalCompanyName"
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
    if ([string]::IsNullOrWhiteSpace($company)) { $matchedcompany = $internalcompany } else {
        $matchedCompany = $null
        $matchedCompany = $(Get-HuduCompanyFromName -CompanyName $company -HuduCompanies $huduCompanies -deepCompanySearch $true -existingIndex $($ITBoostData.organizations["matches"] ?? $null))
    }


    if (-not $matchedCompany -or -not $matchedCompany.id -or $matchedCompany.id -lt 1) { 
        $matchedCompany = $internalcompany ?? $(Get-HuduCompanies -id $internalCompanyId) ?? $($(Read-Host "No match for company '$company', enter internal company id or press enter to skip") | ForEach-Object { Get-HuduCompany -id $_ })
     }
     $matchedCompany = $matchedCompany.company ?? $matchedCompany
    if (-not $matchedCompany -or -not $matchedCompany.id -or $matchedCompany.id -lt 1) { 
        $matchedcompany = $internalcompany
    }
    foreach ($companydocument in $documentsForCompany){
        $matchedDocument = $null
        $matchedDocument = $allHududocuments | Where-Object {
            $_.company_id -eq $matchedCompany.id -and $(test-equiv -A $_.name -B $companydocument.name)} | Select-Object -first 1

        $matchedDocument = $matchedDocument ?? $($(Get-HuduArticles -CompanyId $matchedCompany.id -name $companydocument.name) | Select-Object -first 1)
        if ($matcheddocument){
            if ($true -eq $skiponmatch){continue}
            # Write-Host "matched $($companydocument.name) to doc in Hudu @ $($matchedDocument.url); updating"
                $ITBoostData.documents['matches'] += @{
                    CompanyName      = $companydocument.organization
                    ITBID            = $companydocument.id
                    Name             = $companydocument.name
                    HuduID           = $matcheddocument.id
                    HuduObject       = $matcheddocument
                    HuduCompanyId    = $matcheddocument.company_id
                }
                continue

            if ($DeleteDocsMode -and $true -eq $DeleteDocsMode){
                if (-not $matchedDocument -or -not $matchedDocument.id -or $matchedDocument.id -lt 1){continue}
                write-host "Deleting uploads fo $($matcheddocument.id)"
                foreach ($u in $(Get-HuduUploads | where-object {$_.uploadable_type -eq 'Article' -and $_.uploadable_id -eq $matcheddocument.id})){
                        Invoke-HuduRequest -Method delete -Resource "/api/v1/uploads/$($u.id)"
                }
                write-host "Deleting doc $($matcheddocument.id)"
                if ($matcheddocument.Archived -eq $true){continue}
                
                try {
                    Remove-HuduArticle -Id $matchedDocument.id -Confirm:$false
                } catch {
                    Set-HuduArticleArchive -Id $matchedDocument.id
                }
            }

        }
            if ($DeleteDocsMode -and $true -eq $DeleteDocsMode){continue}

            $imagesCreated = @()
            $uploadsAdded  = @()
            $firstHtml = $null
            $firstHtmlPath = $null
            $OutFile = "$debug_folder\$($companydocument.resource_id).html"
            $URLReplacement = @{}

            
            $newdocumentrequest=@{
                Name="$($companydocument.name)".Trim()
                CompanyID = $matchedCompany.id
                Content="in-transit"
            }
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
            if (-not $newdocumentrequest["Id"]) {
                Write-Warning "Could not create or resolve article id for '$($companydocument.name)', skipping media and content update"
                continue
            }

            # $FoundExistingLinks = Get-LinksFromHTML -htmlContent $DocContents -title "$($companydocument.name)"

            write-host "$($imagesNeeded.count) images needed for doc $($companydocument.name)"
            
            if ($true -eq $AllowConvert -and $sofficePath) {

                # todo - convert
            }

            # $existingRelated = Get-Huduuploads | where-object {$_.uploadable_type -eq "Article" -and [string]$_.uploadable_id -eq [string]$newdocumentrequest["Id"]}
            # IMAGES
            foreach ($imageUpload in $imagesNeeded) {
                # $existingupload = $existingRelated | where-object {test-equiv -A $_.name -B "$([IO.Path]::GetFileName(($imageUpload.File.FullName ?? $imageUpload.File)))".Trim()} | select-object -first 1
                # if ($existingupload -and $existingupload.url){
                #     Add-REplacement "$([IO.Path]::GetFileName(($up.File.FullName ?? $up.File)))" $existingupload.url
                #     write-host "Existing image $($existingupload.url) for $($companydocument.name)"
                #     continue
                # }

                $srcPath = Get-AbsolutePath -PathOrInfo $imageUpload.File -BaseFolder $match.folder
                if (-not (Test-Path -LiteralPath $srcPath)) { Write-Warning "Missing image: $srcPath"; continue }                    
                try {
                    $imgUp = New-DocumentImagePublicPhoto -FilePath $srcPath -ArticleId $newdocumentrequest['Id']
                    Add-DocumentReplacementKeys -FilePath $srcPath -Url $imgUp.Url -SourceUrls $imageUpload.SourceUrls
                    $imagesCreated += $imgUp.PublicPhoto
                } catch {
                    Write-Warning "Error on image $($imageUpload.File): $($_.Exception.Message)"
                    continue
                }
            }

            if ($firstHtmlPath) {
                $globalImageReplacements = Add-GlobalImageReplacements -RawHtml $DocContents -ArticleId $newdocumentrequest['Id'] -ITBoostExportPath $ITBoostExportPath
                if ($globalImageReplacements.Count -gt 0) {
                    Write-Host "$($globalImageReplacements.Count) global images prepared for doc $($companydocument.name)"
                }
            }

            # NON-IMAGE UPLOADS
            foreach ($up in $uploadsNeeded) {
                # $existingupload = $existingRelated | where-object {test-equiv -A $_.name -B "$([IO.Path]::GetFileName(($up.File.FullName ?? $up.File)))".Trim()} | select-object -first 1
                # if ($existingupload -and $existingupload.url){
                #     Add-REplacement "$([IO.Path]::GetFileName(($up.File.FullName ?? $up.File)))" $existingupload.url
                #     write-host "Existing upload $($existingupload.url) for $($companydocument.name)"
                #     continue
                # }

                $srcPath = Get-AbsolutePath -PathOrInfo $up.File -BaseFolder $match.folder
                if (-not (Test-Path -LiteralPath $srcPath)) { Write-Warning "Missing upload: $srcPath"; continue }

                $u = New-HuduUpload -FilePath $srcPath `
                                    -Uploadable_Id $newdocumentrequest['Id'] `
                                    -Uploadable_Type 'Article'
                $u = $u.upload ?? $u
                if (-not $u) { Write-Host "Error on upload $($up.File)"; continue }

                $repUrl = Get-DocumentHuduMediaUrl -InputObject $u -MediaKind Upload -HuduBaseUrl $HuduBaseURL
                Add-DocumentReplacementKeys -FilePath $srcPath -Url $repUrl -SourceUrls $up.SourceUrls
                $uploadsAdded += $u
            }
            if ($firstHtmlpath) {
                $DocContents = Rewrite-InlineLinksAndImages -InFile $firstHtmlPath -Lookup $URLReplacement 
            } 
            $unresolvedImageSources = Get-UnresolvedDocumentImageSources -Html $DocContents
            if ($unresolvedImageSources.Count -gt 0) {
                Write-Warning "Skipping final content update for '$($companydocument.name)' because unresolved local image sources remain: $($unresolvedImageSources -join ', ')"
                continue
            }
            $newdocumentrequest['Content'] = As-HtmlString $DocContents

            try {
                Write-host "$($($newdocumentrequest | convertto-json).ToString())"
                $newdocument = $null
                $newdocument = Set-HuduArticle @newdocumentrequest
                $newdocument = $newdocument.article ?? $newdocument
            } catch {
                write-host "Error creating location: $_"
            }
            if ($null -ne $newdocument){
                write-host "created document $($companydocument.name) with ID $($newdocument.id) for company $($matchedCompany.name)"
                $ITBoostData.documents["matches"]+=@{
                    CompanyName=$companydocument.organization
                    ITBID=$companydocument.id
                    Name=$companydocument.name
                    HuduID=$newdocument.id
                    HuduObject=$newdocument
                    HuduCompanyId=$($matchedcompany.id ?? $newdocument.company_id)
                    PasswordsToCreate=$($companydocument.password ?? @())
                }            
        }
    }
}
($ITBoostData.documents["matches"] ?? @()) | convertto-json -depth 99 | out-file $($(join-path $debug_folder -ChildPath "MatchedDocuments.json")) -Force
    
