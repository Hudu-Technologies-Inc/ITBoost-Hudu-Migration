$CanConvertExtensions = @('.pdf','.doc','.docx','.xls','.xlsx','.ppt','.htm','.html','.pptx','.txt','.rtf','.jpg','.jpeg','.png')
$ImageTypes           = @('.png', '.jpeg', '.jpg', '.gif', '.svg', '.bmp')
$Direct2Doc           = @('.html','.htm')   # both with leading dot

$DisallowedForConvert = @(
  '.mp3','.wav','.flac','.aac','.ogg','.wma','.m4a',
  '.dll','.so','.lib','.bin','.class','.pyc','.pyo','.o','.obj',
  '.exe','.msi','.bat','.cmd','.sh','.jar','.app','.apk','.dmg','.iso','.img',
  '.zip','.rar','.7z','.tar','.gz','.bz2','.xz','.tgz','.lz',
  '.mp4','.avi','.mov','.wmv','.mkv','.webm','.flv',
  '.psd','.ai','.eps','.indd','.sketch','.fig','.xd','.blend',
  '.ds_store','.thumbs','.lnk','.heic'
)

# --- case-insensitive sets ---
$cmp = [StringComparer]::OrdinalIgnoreCase

$CanConvertSet     = [Collections.Generic.HashSet[string]]::new($cmp)
$ImageSet          = [Collections.Generic.HashSet[string]]::new($cmp)
$NonConvertableSet = [Collections.Generic.HashSet[string]]::new($cmp)
$Direct2DocSet     = [Collections.Generic.HashSet[string]]::new($cmp)

# CAST to [string[]] so the right overload is picked
$CanConvertSet.UnionWith([string[]]$CanConvertExtensions)
$ImageSet.UnionWith([string[]]$ImageTypes)
$NonConvertableSet.UnionWith([string[]]$DisallowedForConvert)
$Direct2DocSet.UnionWith([string[]]$Direct2Doc)
# Libre Set-Up
$portableLibreOffice=$false
$LibreFullInstall="https://www.libreoffice.org/donate/dl/win-x86_64/25.2.4/en-US/LibreOffice_25.2.4_Win_x86-64.msi"
$LibrePortaInstall="https://download.documentfoundation.org/libreoffice/portable/25.2.3/LibreOfficePortable_25.2.3_MultilingualStandard.paf.exe"

# Poppler Setup
$includeHiddenText=$true
$includeComplexLayouts=$true
$PopplerBins=$(join-path $project_workdir "tools\poppler")
$PDFToHTML=$(join-path $PopplerBins "pdftohtml.exe")

function Set-HuduInstance { 
    $HuduBaseURL = $HuduBaseURL ?? 
        $((Read-Host -Prompt 'Set the base domain of your Hudu instance (e.g https://myinstance.huducloud.com)') -replace '[\\/]+$', '') -replace '^(?!https://)', 'https://'
    $HuduAPIKey = $HuduAPIKey ?? "$(read-host "Please Enter Hudu API Key")"
    while ($HuduAPIKey.Length -ne 24) {
        $HuduAPIKey = (Read-Host -Prompt "Get a Hudu API Key from $($settings.HuduBaseDomain)/admin/api_keys").Trim()
        if ($HuduAPIKey.Length -ne 24) {
            Write-Host "This doesn't seem to be a valid Hudu API key. It is $($HuduAPIKey.Length) characters long, but should be 24." -ForegroundColor Red
        }
    }
    New-HuduAPIKey $HuduAPIKey
    New-HuduBaseURL $HuduBaseURL
}

function Get-HuduModule {
    param (
        [string]$HAPImodulePath = "C:\Users\$env:USERNAME\Documents\GitHub\HuduAPI\HuduAPI\HuduAPI.psm1",
        [bool]$use_hudu_fork = $true
        )

    if ($true -eq $use_hudu_fork) {
        if (-not $(Test-Path $HAPImodulePath)) {
            $dst = Split-Path -Path (Split-Path -Path $HAPImodulePath -Parent) -Parent
            Write-Host "Using Lastest Master Branch of Hudu Fork for HuduAPI"
            $zip = "$env:TEMP\huduapi.zip"
            Invoke-WebRequest -Uri "https://github.com/Hudu-Technologies-Inc/HuduAPI/archive/refs/heads/master.zip" -OutFile $zip
            Expand-Archive -Path $zip -DestinationPath $env:TEMP -Force 
            $extracted = Join-Path $env:TEMP "HuduAPI-master" 
            if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
            Move-Item -Path $extracted -Destination $dst 
            Remove-Item $zip -Force
        }
    } else {
        Write-Host "Assuming PSGallery Module if not already locally cloned at $HAPImodulePath"
    }

    if (Test-Path $HAPImodulePath) {
        Import-Module $HAPImodulePath -Force
        Write-Host "Module imported from $HAPImodulePath"
    } elseif ((Get-Module -ListAvailable -Name HuduAPI).Version -ge [version]'2.4.4') {
        Import-Module HuduAPI
        Write-Host "Module 'HuduAPI' imported from global/module path"
    } else {
        Install-Module HuduAPI -MinimumVersion 2.4.5 -Scope CurrentUser -Force
        Import-Module HuduAPI
        Write-Host "Installed and imported HuduAPI from PSGallery"
    }
}
function Get-HuduVersionCompatible {
    param (
        [version]$RequiredHuduVersion = [version]"2.37.1",
        $DisallowedVersions = @([version]"2.37.0")
    )
    Write-Host "Required Hudu version: $requiredversion" -ForegroundColor Blue
    try {
        $HuduAppInfo = Get-HuduAppInfo
        $CurrentHuduVersion = $HuduAppInfo.version

        if ([version]$CurrentHuduVersion -lt [version]$RequiredHuduVersion) {
            Write-Host "This script requires at least version $RequiredHuduVersion and cannot run with version $CurrentHuduVersion. Please update your version of Hudu." -ForegroundColor Red
            exit 1
        }
    } catch {
        write-host "error encountered when checking hudu version for $(Get-HuduBaseURL) - $_"
    }
    Write-Host "Hudu Version $CurrentHuduVersion is compatible"  -ForegroundColor Green
}

function Get-PSVersionCompatible {
    param (
        [version]$RequiredPSversion = [version]"7.5.1"
    )

    $currentPSVersion = (Get-Host).Version
    Write-Host "Required PowerShell version: $RequiredPSversion" -ForegroundColor Blue

    if ($currentPSVersion -lt $RequiredPSversion) {
        Write-Host "PowerShell $RequiredPSversion or higher is required. You have $currentPSVersion." -ForegroundColor Red
        exit 1
    } else {
        Write-Host "PowerShell version $currentPSVersion is compatible." -ForegroundColor Green
    }
}
