# ---------------------------------------------------------------
# Join or Create Farm
# ---------------------------------------------------------------
# First run this script on your Central Admin Server.  The first
# run will create your SharePoint Farm.  Next run this script
# on each of your SharePoint Servers to join them to the farm.
# ---------------------------------------------------------------

param 
(
    [string]$InputFile = $(throw '- Need parameter input file (e.g. "farmConfig.xml")')
)

# load dependencies
$0 = $myInvocation.MyCommand.Definition
$dp0 = [System.IO.Path]::GetDirectoryName($0)
. "$dp0\lib\package.ps1"

[xml]$ConfigFile = Get-Content $InputFile
$Config = $ConfigFile.Configuration

info "-----------------------------------------"
info "Creating and configuring (or joining) farm"
info "-----------------------------------------"

LoadSharePointPowershell

Start-SPAssignment -Global | Out-Null

if (IsJoinedToFarm $config -eq $false) {
    $isNewFarm = CreateOrJoinFarm $Config
    
    if ($isNewFarm -eq $true) {
        InitializeNewFarm $Config
    }
    
} else {
    info "This server is already connect to the Farm."
}

Stop-SPAssignment -Global | Out-Null