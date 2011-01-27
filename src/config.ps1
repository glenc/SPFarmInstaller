# ---------------------------------------------------------------
# Installation Options
# ---------------------------------------------------------------
$OfflineInstallation      = $false
$PathToBits               = "bits"
$PathToInstallConfig      = "config.xml"


# ---------------------------------------------------------------
# Basic Farm Configuration
# ---------------------------------------------------------------
$Farm = @{
    "DatabaseServer"        = "SQLDEV2008";
    "ConfigDB"              = "SP_Config";
    "CentralAdminPort"      = 65001;
    "CentralAdminContentDB" = "SP_AdminContent";
    "Passphrase"            = "Share!Point";
    
    "FarmSvcAccount"        = "pico\svc.sp2010-farm";
    "FarmSvcPwd"            = "***";
}

$Topology = @{
    "WebFrontEndServers"        = "SP2010-FARM-01", "SP2010-FARM-02";
    "ManagedMetadataServers"    = "SP2010-FARM-01";
    "UserProfileServiceServers" = "SP2010-FARM-01";
    "SearchQueryServers"        = "SP2010-FARM-01", "SP2010-FARM-02";
    "SearchIndexServers"        = "SP2010-FARM-02";
    "SandboxSolutionServers"    = "SP2010-FARM-01"
}


# ---------------------------------------------------------------
# Service Applications
# ---------------------------------------------------------------
# Define Service Applications below

# ---------------------------------------------------------------
# Managed Metadata Applications

$mmsApp1 = @{
    "Name"              = "Managed Metadata";
    "DBName"            = "MMS_DB";
    "AppPoolName"       = "MMS_AppPool";
    "AppPoolAccount"    = "AppPoolAcct";
    "AppPoolAccountPwd" = "test";
    "Partitioned"       = $false;
    "AdminAccount"      = "";
    "Permissions"       = @{
                            "MMS_AppPool" = "Full Access to Term Store"; 
                            "asdf"        = "Full Access to Term Store" 
                           }
}

# All MMS Definitions
$ManagedMetadataApplicationDefinitions = $mmsApp1


# ---------------------------------------------------------------
# User Profile Service Applications

$upsApp1 = @{
    "Name"              = "User Profile Service";
    "AppPoolName"       = "MMS_AppPool";
    "AppPoolAccount"    = "AppPoolAcct";
    "AppPoolAccountPwd" = "test";
    "ProfileDB"         = "SP_Profiles";
    "ProfileSyncDB"     = "SP_ProfileSync";
    "SocialDB"          = "SP_Social";
    "MySiteUrl"         = "/mysites";
    "MySitePort"        = "80";
    "Permissions"       = @{
                            "Farm Account"   = "Full Control";
                            "My Site App Pool" = "Full Control";
                            "Content Access" = "Retrieve People Data for Search Crawlers";
                           }
}

$UserProfileServiceApplicationDefinitions = $upsApp1