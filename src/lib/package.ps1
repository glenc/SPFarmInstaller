$libPath = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition)
. "$libPath\util.ps1"
. "$libPath\security.ps1"
. "$libPath\farm.ps1"