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
    
    info "Provisioning State Service Applications"
    ProvisionStateServiceApplications $Config
    
    info "Provision WSS Usage Applications"
    ProvisionWSSUsageServiceApplications $Config
    
    info "Creating Web Applications"
    ProvisionWebApplications $Config

    info "Provisioning Secure Store Service Applications"
    ProvisionSecureStoreServiceApplications $Config

    info "Provisining Managed Metadata Applications"
    ProvisionMetadataServiceApplications $Config
    
    info "Provisioning Enterprise Search Applications"
    ProvisionEnterpriseSearchServiceApplications $Config
    
    info "Provisioning User Profile Service Applications"
    ProvisionUserProfileServiceApplications $Config
    
    info "Provisioning Web Analytics Service Applications"
    ProvisionWebAnalyticsServiceApplications $Config
    
    info "Provisioning Business Data Connectivity Applications"
    ProvisionBusinessDataConnectivityApplications $Config
    
    info "Provisioning Access Services Applications"
    ProvisionAccessServicesApplications $Config
    
    info "Provisioning Visio Graphics Applications"
    ProvisionVisioGraphicsApplications $Config
    
    info "Provisioning Excel Services Applications"
    ProvisionExcelServicesApplications $Config
    
    info "Configuring Session State"
    ConfigureSessionStateService $Config
    
    info "################################################"
    info "The Farm has been configured."
    warn "Remember to remove the farm account from the local"
    warn "administrators group on all of your servers"
    info ""
    info "To ensure that the User Profile Sync can be run"
    info "leave the farm account in the administrators group"
    info "on your synchronization server"
    info ""
    info "Finally, please reboot all servers in your farm"
    info "one last time."
    info "################################################"

} catch {
    Write-Output $_
    break
} finally {
    Stop-SPAssignment -Global | Out-Null
}