# ---------------------------------------------------------------
# Configure Farm
# ---------------------------------------------------------------
# Run this script from your Central Administration server AFTER
# you have run 02-join-or-create-farm.ps1 on each SharePoint 
# server in your farm.
# ---------------------------------------------------------------

param
(
    [string]$InputFile = $(throw '- Need parameter input file (e.g. "farmConfig.xml")')
)

# load dependencies
$0 = $myInvocation.MyCommand.Definition
$dp0 = [System.IO.Path]::GetDirectoryName($0)
. "$dp0\lib\package.ps1"

try {

    [xml]$ConfigFile = Get-Content $InputFile
    $Config = $ConfigFile.Configuration

    LoadSharePointPowershell

    Start-SPAssignment -Global | Out-Null

    info "Configuring Farm Topology"
    ConfigureTopology $Config

    info "Provisining Managed Metadata Applications"
    ProvisionMetadataServiceApplications $Config
    
    info "Provisioning Enterprise Search Applications"
    ProvisionEnterpriseSearchServiceApplications $Config

    #info "Provisioning User Profile Service Applications"
    #ProvisionUserProfileServiceApplications $Config
    
    info "Provisioning Secure Store Service Applications"
    ProvisionSecureStoreServiceApplications $Config
    
    info "Provisioning State Service Applications"
    ProvisionStateServiceApplications $Config
    
    info "Provisioning Web Analytics Service Applications"
    ProvisionWebAnalyticsServiceApplications $Config

} catch {
    break
} finally {
    Stop-SPAssignment -Global | Out-Null
}