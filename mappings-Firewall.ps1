$flexiFields = @(
    @{label = 'CsvRow'; field_type = 'Text'; show_in_list = 'false'; position = 1; required = 'false'; hint = 'CsvRow from script'},
    @{label = 'id'; field_type = 'Text'; show_in_list = 'false'; position = 2; required = 'false'; hint = 'id from script'},
    @{label = 'Internal IP Address'; field_type = 'Text'; show_in_list = 'false'; position = 3; required = 'false'; hint = 'Internal IP Address from script'},
    @{label = 'ITBNotes'; field_type = 'Text'; show_in_list = 'false'; position = 4; required = 'false'; hint = 'ITBNotes from script'},
    @{label = 'Location'; field_type = 'Text'; show_in_list = 'false'; position = 5; required = 'false'; hint = 'Location from script'},
    @{label = 'Management'; field_type = 'Text'; show_in_list = 'false'; position = 6; required = 'false'; hint = 'Management from script'},
    @{label = 'Manufacturer'; field_type = 'Text'; show_in_list = 'false'; position = 7; required = 'false'; hint = 'Manufacturer from script'},
    @{label = 'Model #'; field_type = 'Text'; show_in_list = 'false'; position = 8; required = 'false'; hint = 'Model # from script'},
    @{label = 'Name (Scheme:  Name - Location)'; field_type = 'Text'; show_in_list = 'false'; position = 9; required = 'false'; hint = 'Name (Scheme:  Name - Location) from script'},
    @{label = 'Notes:'; field_type = 'Text'; show_in_list = 'false'; position = 10; required = 'false'; hint = 'Notes: from script'},
    @{label = 'organization'; field_type = 'Text'; show_in_list = 'false'; position = 11; required = 'false'; hint = 'organization from script'},
    @{label = 'password'; field_type = 'Text'; show_in_list = 'false'; position = 12; required = 'false'; hint = 'password from script'},
    @{label = 'Port 0'; field_type = 'Text'; show_in_list = 'false'; position = 13; required = 'false'; hint = 'Port 0 from script'},
    @{label = 'Port 1'; field_type = 'Text'; show_in_list = 'false'; position = 14; required = 'false'; hint = 'Port 1 from script'},
    @{label = 'Port 2'; field_type = 'Text'; show_in_list = 'false'; position = 15; required = 'false'; hint = 'Port 2 from script'},
    @{label = 'Port 3'; field_type = 'Text'; show_in_list = 'false'; position = 16; required = 'false'; hint = 'Port 3 from script'},
    @{label = 'Port 4'; field_type = 'Text'; show_in_list = 'false'; position = 17; required = 'false'; hint = 'Port 4 from script'},
    @{label = 'Port 5'; field_type = 'Text'; show_in_list = 'false'; position = 18; required = 'false'; hint = 'Port 5 from script'},
    @{label = 'Port 6'; field_type = 'Text'; show_in_list = 'false'; position = 19; required = 'false'; hint = 'Port 6 from script'},
    @{label = 'Port 7'; field_type = 'Text'; show_in_list = 'false'; position = 20; required = 'false'; hint = 'Port 7 from script'},
    @{label = 'resource id'; field_type = 'Text'; show_in_list = 'false'; position = 21; required = 'false'; hint = 'resource_id from script'},
    @{label = 'resource type'; field_type = 'Text'; show_in_list = 'false'; position = 22; required = 'false'; hint = 'resource_type from script'},
    @{label = 'Serial #'; field_type = 'Text'; show_in_list = 'false'; position = 23; required = 'false'; hint = 'Serial # from script'},
    @{label = 'SNMP Info'; field_type = 'Text'; show_in_list = 'false'; position = 24; required = 'false'; hint = 'SNMP Info from script'},
    @{label = 'WG Read-Only or Other Firewall Password'; field_type = 'Text'; show_in_list = 'false'; position = 25; required = 'false'; hint = 'WG Read-Only or Other Firewall Password from script'},
    @{label = 'WG Read-Write Password'; field_type = 'Text'; show_in_list = 'false'; position = 26; required = 'false'; hint = 'WG Read-Write Password from script'}
)

$flexisMap = @{
    'CsvRow' = 'CsvRow'
    'id' = 'id'
    'Internal_IP_Address' = 'Internal IP Address'
    'ITBNotes' = 'ITBNotes'
    'Location' = 'Location'
    'Management' = 'Management'
    'Manufacturer' = 'Manufacturer'
    'Model_#' = 'Model #'
    'Name_(Scheme:__Name_-_Location)' = 'Name (Scheme:  Name - Location)'
    'Notes:' = 'Notes:'
    'organization' = 'organization'
    'password' = 'password'
    'Port_0' = 'Port 0'
    'Port_1' = 'Port 1'
    'Port_2' = 'Port 2'
    'Port_3' = 'Port 3'
    'Port_4' = 'Port 4'
    'Port_5' = 'Port 5'
    'Port_6' = 'Port 6'
    'Port_7' = 'Port 7'
    'resource_id' = 'resource id'
    'resource_type' = 'resource type'
    'Serial_#' = 'Serial #'
    'SNMP_Info' = 'SNMP Info'
    'WG_Read-Only_or_Other_Firewall_Password' = 'WG Read-Only or Other Firewall Password'
    'WG_Read-Write_Password' = 'WG Read-Write Password'
}# smoosh source label items to destination smooshable
$smooshLabels = @()
$smooshToDestinationLabel = $null
$jsonSourceFields = @()
