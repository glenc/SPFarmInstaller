# ---------------------------------------------------------------
# Configure Farm
# ---------------------------------------------------------------
# Run this script from your Central Administration server AFTER
# you have run 02-join-or-create-farm.ps1 on each SharePoint 
# server in your farm.
# ---------------------------------------------------------------

# load dependencies
$0 = $myInvocation.MyCommand.Definition
$dp0 = [System.IO.Path]::GetDirectoryName($0)
. "$dp0\lib\package.ps1"
. "$dp0\config.ps1"

Start-SPAssignment -Global | Out-Null

info "Configuring Farm Topology"
ConfigureTopology $Topology

info "Provisining Managed Metadata Applications"
ProvisionMetadataServiceApp $ManagedMetadataApplicationDefinitions

info "Provisioning User Profile Service Applications"
ProvisionUserProfileServiceApp $UserProfileServiceApplicationDefinitions


Stop-SPAssignment -Global | Out-Null