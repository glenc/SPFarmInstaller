# ---------------------------------------------------------------
# Install Bits
# ---------------------------------------------------------------
# This script will install the SharePoint bits on your SharePoint
# servers.  It does not create or join the machine to a farm.
# Run this on all of your SharePoint servers.
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

    info "-----------------------------------------"
    info "Installing SharePoint Bits"
    info "-----------------------------------------"

    info "Checking installation account"
    CheckInstallationAccount $Config

    info "Checking for SQL Access"
    CheckSQLAccess $Config

    info "Installing Prerequisites"
    InstallPrerequisites $Config

    info "Install SharePoint Bits"
    InstallSharePoint $Config

} catch {
    throw
    break
}