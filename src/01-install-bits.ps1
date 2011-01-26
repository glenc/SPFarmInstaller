# ---------------------------------------------------------------
# Install Bits
# ---------------------------------------------------------------
# This script will install the SharePoint bits on your SharePoint
# servers.  It does not create or join the machine to a farm.
# Run this on all of your SharePoint servers.
# ---------------------------------------------------------------

# load dependencies
$0 = $myInvocation.MyCommand.Definition
$dp0 = [System.IO.Path]::GetDirectoryName($0)
. "$dp0\lib\package.ps1"
. "$dp0\config.ps1"

info "Installing SharePoint Bits"

info "Checking installation account"
CheckInstallationAccount $Farm

info "Checking for SQL Access"
CheckSQLAccess $Farm

info "Installing Prerequisites"
InstallPrerequisites $PathToBits $OfflineInstallation

info "Install SharePoint Bits"
InstallSharePoint $PathToBits $PathToInstallConfig