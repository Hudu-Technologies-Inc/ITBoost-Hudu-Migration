# Hudu Destinatio Reference Section
<#
# {
  "id": 169,
  "label": "Role",
  "show_in_list": false,
  "field_type": "ListSelect",
  "required": false,
  "hint": "",
  "min": null,
  "max": null,
  "linkable_id": 5,
  "expiration": false,
  "options": "",
  "multiple_options": true,
  "list_id": 8,
  "column_width": "variable",
  "position": 1,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
# {
  "id": 170,
  "label": "IP Address",
  "show_in_list": false,
  "field_type": "Website",
  "required": null,
  "hint": "Management IP Address",
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
  "id": 171,
  "label": "Configuration",
  "show_in_list": false,
  "field_type": "RichText",
  "required": null,
  "hint": "Copy & Paste the Configuration",
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
  "id": 172,
  "label": "Subscription/Support Renewal",
  "show_in_list": false,
  "field_type": "Date",
  "required": false,
  "hint": "",
  "min": null,
  "max": null,
  "linkable_id": 5,
  "expiration": true,
  "options": "",
  "multiple_options": null,
  "list_id": null,
  "column_width": "variable",
  "position": 6,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
# {
  "id": 173,
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
  "position": 7,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
## Labels


#>

$flexisMap = @{
    'Internal_IP_Address' = 'IP Address'
    'Manufacturer' = 'Manufacturer'


}# smoosh source label items to destination smooshable
$smooshLabels = @(
'Model_#' 
'Port_0' 
'Port_1' 
'Port_2' 
'Port_3' 
'Port_4' 
'Port_5' 
'Port_6' 
'Port_7' 
'ITBNotes' 
'resource_id' 
'resource_type'     
'Serial_#' 
'SNMP_Info' 
'WG_Read-Only_or_Other_Firewall_Password' 
'WG_Read-Write_Password'
'Subscription/Support Renewal'
)
$smooshToDestinationLabel = "Notes"
$jsonSourceFields = @()
$nameField = "Name (Scheme:  Name - Location)"