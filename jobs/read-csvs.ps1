$CSVFiles= Get-ChildItem -Path $ITBoostExportPath -Recurse -depth 2 -File -Filter "*.csv"
foreach ($f in $CSVFiles){
    try {
        $csvData=$(Import-Csv $f.FullName | Select-Object @{Name='CsvRow'; Expression={ $i++ }}, *)
    } catch {continue}
    if ($csvData){
        $keyName=$($f.name -ireplace ".csv","")
        write-host "importing $keyName from $($f.FullName)"
        $ITBoostData[$keyName]=@{
            CSVData=$csvData
            AttachmentsPath=$(join-path -Path $f.directory.fullname "attachments\$keyName")
            DocumentsPath=$(join-path -Path $f.directory.fullname "documents\$keyName")
            Matches=@()
        }
    }
}


# $allProps=@()
# $uniqueProps=@()
# foreach ($key in $itboostdata.keys){
#     $Props = Get-CSVProperties $itboostdata.$key.csvdata
#     if ($props -eq $null -or $props.count -lt 1){continue}
#     $allProps+=$props
# }
# $uniqueProps = $allProps | select-object -unique
# $uniqueProps | Sort-Object | format-list -force