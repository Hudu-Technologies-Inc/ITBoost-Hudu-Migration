# Hudu Destinatio Reference Section
<#
# {
  "id": 132,
  "label": "Site Name",
  "show_in_list": false,
  "field_type": "Text",
  "required": null,
  "hint": "Site Name - e.g. Denver",
  "min": null,
  "max": null,
  "linkable_id": 5,
  "expiration": false,
  "options": "",
  "multiple_options": null,
  "list_id": null,
  "column_width": "variable",
  "position": 1,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
# {
  "id": 133,
  "label": "IP Address",
  "show_in_list": false,
  "field_type": "Text",
  "required": null,
  "hint": "",
  "min": null,
  "max": null,
  "linkable_id": 5,
  "expiration": false,
  "options": "",
  "multiple_options": null,
  "list_id": null,
  "column_width": "variable",
  "position": 2,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
# {
  "id": 134,
  "label": "Make/Model",
  "show_in_list": false,
  "field_type": "Text",
  "required": null,
  "hint": "",
  "min": null,
  "max": null,
  "linkable_id": 5,
  "expiration": false,
  "options": "",
  "multiple_options": null,
  "list_id": null,
  "column_width": "variable",
  "position": 3,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
# {
  "id": 135,
  "label": "Deployment",
  "show_in_list": false,
  "field_type": "ListSelect",
  "required": null,
  "hint": "How is this printer deployed to users?",
  "min": null,
  "max": null,
  "linkable_id": 5,
  "expiration": false,
  "options": "",
  "multiple_options": true,
  "list_id": 17,
  "column_width": "variable",
  "position": 4,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
# {
  "id": 136,
  "label": "Published to Active Directory (AD)",
  "show_in_list": false,
  "field_type": "CheckBox",
  "required": null,
  "hint": "Is this printer published to Active Directory?",
  "min": null,
  "max": null,
  "linkable_id": 5,
  "expiration": false,
  "options": "",
  "multiple_options": null,
  "list_id": null,
  "column_width": "variable",
  "position": 5,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
# {
  "id": 137,
  "label": "Drivers Path",
  "show_in_list": false,
  "field_type": "Text",
  "required": null,
  "hint": "e.g. \\\\fileshare\\support\\drivers\\hp\\thisprinter",
  "min": null,
  "max": null,
  "linkable_id": 5,
  "expiration": false,
  "options": "",
  "multiple_options": null,
  "list_id": null,
  "column_width": "variable",
  "position": 6,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
# {
  "id": 138,
  "label": "Support Information",
  "show_in_list": false,
  "field_type": "RichText",
  "required": null,
  "hint": "Enter details to printer support company",
  "min": null,
  "max": null,
  "linkable_id": 5,
  "expiration": false,
  "options": "",
  "multiple_options": null,
  "list_id": null,
  "column_width": "variable",
  "position": 7,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
# {
  "id": 139,
  "label": "Notes",
  "show_in_list": false,
  "field_type": "RichText",
  "required": null,
  "hint": "",
  "min": null,
  "max": null,
  "linkable_id": 5,
  "expiration": false,
  "options": "",
  "multiple_options": null,
  "list_id": null,
  "column_width": "variable",
  "position": 8,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
## Labels-only
(        | ForEach-Object {
    "# -  ()"
}) -join "
"
#>
<#
    'Company_Password' = ' '
    'CsvRow' = ' '
    'Drivers_Path' = ' '
    'empty' = ' '
    'id' = ' '
    'ITBNotes' = ' '
    'Location' = ' '
    'MAC_Address' = ' '
    'Name_(Scheme:__Name_-_Location)' = ' '
    'Notes:' = ' '
    'organization' = ' '
    'password' = ' '
    'Printer_Host' = ' '
    'Printer_IP_Address' = ' '
    'Printer_Type' = ' '
    'resource_id' = ' '
    'resource_type' = ' '
    'Serial_No.' = ' '
    'UNC_Path' = ' '
    'Username' = ' '#>
$flexisMap = @{
    'Drivers_Path' = 'Drivers Path'
    'Printer_IP_Address' = 'IP Address'
    'Printer_Type' = 'Printer Access'
    'Serial_No.' = 'MAC Address'
}# smoosh source label items to destination smooshable
$smooshLabels =  @("Notes:","Drivers_Path","UNC_Path","Username","Printer_Host")
$smooshToDestinationLabel = "Notes"
$jsonSourceFields = @()

# where to get name from on source?
$nameField = "Name_(Scheme:__Name_-_Location)"
