$flexiFields = @(
    @{label = 'AP(s)'; field_type = 'Text'; show_in_list = 'false'; position = 1; required = 'false'; hint = 'AP(s) from script'},
    @{label = 'CsvRow'; field_type = 'Text'; show_in_list = 'false'; position = 2; required = 'false'; hint = 'CsvRow from script'},
    @{label = 'id'; field_type = 'Text'; show_in_list = 'false'; position = 3; required = 'false'; hint = 'id from script'},
    @{label = 'Internal SSID'; field_type = 'Text'; show_in_list = 'false'; position = 4; required = 'false'; hint = 'Internal SSID from script'},
    @{label = 'INTERNAL SSID KEY'; field_type = 'Text'; show_in_list = 'false'; position = 5; required = 'false'; hint = 'INTERNAL SSID KEY from script'},
    @{label = 'ITBNotes'; field_type = 'Text'; show_in_list = 'false'; position = 6; required = 'false'; hint = 'ITBNotes from script'},
    @{label = 'LAN(s) \ VLAN(s)'; field_type = 'Text'; show_in_list = 'false'; position = 7; required = 'false'; hint = 'LAN(s) \ VLAN(s) from script'},
    @{label = 'Location'; field_type = 'Text'; show_in_list = 'false'; position = 8; required = 'false'; hint = 'Location from script'},
    @{label = 'Name (Scheme:  Name - Location)'; field_type = 'Text'; show_in_list = 'false'; position = 9; required = 'false'; hint = 'Name (Scheme:  Name - Location) from script'},
    @{label = 'Notes'; field_type = 'Text'; show_in_list = 'false'; position = 10; required = 'false'; hint = 'Notes from script'},
    @{label = 'organization'; field_type = 'Text'; show_in_list = 'false'; position = 11; required = 'false'; hint = 'organization from script'},
    @{label = 'password'; field_type = 'Text'; show_in_list = 'false'; position = 12; required = 'false'; hint = 'password from script'},
    @{label = 'resource id'; field_type = 'Text'; show_in_list = 'false'; position = 13; required = 'false'; hint = 'resource_id from script'},
    @{label = 'resource type'; field_type = 'Text'; show_in_list = 'false'; position = 14; required = 'false'; hint = 'resource_type from script'}
)

$flexisMap = @{
    'AP(s)' = 'AP(s)'
    'CsvRow' = 'CsvRow'
    'id' = 'id'
    'Internal_SSID' = 'Internal SSID'
    'INTERNAL_SSID_KEY' = 'INTERNAL SSID KEY'
    'ITBNotes' = 'ITBNotes'
    'LAN(s)_\_VLAN(s)' = 'LAN(s) \ VLAN(s)'
    'Location' = 'Location'
    'Name_(Scheme:__Name_-_Location)' = 'Name (Scheme:  Name - Location)'
    'Notes' = 'Notes'
    'organization' = 'organization'
    'password' = 'password'
    'resource_id' = 'resource id'
    'resource_type' = 'resource type'
}
