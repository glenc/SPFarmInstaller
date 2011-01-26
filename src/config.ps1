# ---------------------------------------------------------------
# Installation Options
# ---------------------------------------------------------------
$OfflineInstallation = $false
$PathToBits = "bits"
$PathToInstallConfig = "config.xml"


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




# ---------------------------------------------------------------
# Service Applications
# ---------------------------------------------------------------

# ---------------------------------------------------------------
# Managed Metadata Applications
# ---------------------------------------------------------------

# MMS Definitions
$ManagedMetadataApplication1 = @{
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
$global:ManagedMetadataApplicationDefinitions = $ManagedMetadataApplication1


# ---------------------------------------------------------------
# Farm Topology
# ---------------------------------------------------------------
$global:CentralAdminServer          = "SP2010-FARM-01"
$global:WebFrontEndServers          = "SP2010-FARM-01", "SP2010-FARM-02"
$global:ManagedMetadataAppServers   = "SP2010-FARM-02"
$global:SearchQueryServers          = "SP2010-FARM-01", "SP2010-FARM-02"
$global:SearchIndexServers          = "SP2010-FARM-02"