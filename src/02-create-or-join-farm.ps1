# ---------------------------------------------------------------
# Join or Create Farm
# ---------------------------------------------------------------
# First run this script on your Central Admin Server.  The first
# run will create your SharePoint Farm.  Next run this script
# on each of your SharePoint Servers to join them to the farm.
# ---------------------------------------------------------------

# load dependencies
$0 = $myInvocation.MyCommand.Definition
$dp0 = [System.IO.Path]::GetDirectoryName($0)
. "$dp0\lib\package.ps1"
. "$dp0\config.ps1"

info "Creating and configuring (or joining) farm"

Start-SPAssignment -Global | Out-Null

if (IsJoinedToFarm $Farm -eq $false) {
    $isNewFarm = CreateOrJoinFarm $Farm
    
    if ($isNewFarm -eq $true) {
        InitializeNewFarm $Farm
    }
    
} else {
    info "This server is already connect to the Farm."
}

Stop-SPAssignment -Global | Out-Null