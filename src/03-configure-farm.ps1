# ---------------------------------------------------------------
# Configure Farm
# ---------------------------------------------------------------
# Run this script from your Central Administration server AFTER
# you have run 02-join-or-create-farm.ps1 on each SharePoint 
# server in your farm.
# ---------------------------------------------------------------

# Load Configuration
&./config.ps1

# Load Global Functions
&./lib/common.ps1

info "Installing SharePoint"

Start-SPAssignment -Global | Out-Null

&./lib/config-Topology.ps1
&./lib/create-app-MMS.ps1

Stop-SPAssignment -Global | Out-Null