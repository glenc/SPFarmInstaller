# ---------------------------------------------------------------
# SharePoint Automated Installation Script
# ---------------------------------------------------------------

STEP 1: PREPARATION
1. Edit the settings in farmConfig.xml
2. Add your product key to installConfig.xml
3. Prepare your installation by copying the SharePoint bits to your server or setting up a share where they can be accessed by all servers in your farm.
4. [OPTIONAL] Run 00-download-prereqs.ps1 and move them to the proper location (be sure to set OfflineInstallation to "True" in your farmConfig.xml)

STEP 2: INSTALL SHAREPOINT BITS
Next you will install the SharePoint bits on each server in your farm.  This does NOT create a farm or configure SharePoint so it can be done simultaneously on each of your servers.

Connect to each server in your farm and perform the following steps:
1. Start a PowerShell console (run as administrator)
2. Execute the following commands:

	PS> Set-ExecutionPolicy RemoteSigned
	PS> .\01-install-bits.ps1 .\farmConfig.xml


STEP 3: CREATE THE FARM
To create the farm, follow these steps:
1. On your central admin server, run the following PowerShell Command:

	PS> .\02-create-or-join-farm.ps1 .\farmConfig.xml

2. Once the farm has been created, connect to each of the other servers in your farm (ONE AT A TIME) and execute the following PowerShell Command:

	PS> .\02-create-or-join-farm.ps1 .\farmConfig.xml

STEP 4: CONFIGURE THE FARM
The last step is to configure the farm including all service applications, web applications, etc.

1. Connect to your central admin server and run the following PowerShell command:

	PS > .\03-configure-farm.ps1 .\farmConfig.xml

