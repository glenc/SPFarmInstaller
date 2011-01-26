$libPath = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition)
. "$libPath\logging.ps1"
. "$libPath\security.ps1"
. "$libPath\farm.ps1"