 $companyassets=$(get-huduassets -CompanyId 8);
foreach ($p in $passwords){
    $passwordrequest=@{companyid = 8;}
    $matchedasset=$companyassets | where-object {$_.name -eq $p.name} | select-object -first 1
    if ($matchedasset) {
        $passwordrequest['passwordableid']=$matchedasset.id
        $passwordrequest['passwordabletype']="Asset"
    }
     if ($p.username) {$passwordrequest["username"]=$p.username}
    if ($p.password) {$passwordrequest.password=$p.password}
    if ($p.notes) {$passwordrequest.description = $p.notes}
    $passwordrequest["name"]=$p.name ?? "$($p.organization) password"
    New-HuduPassword @passwordrequest
}