<#
.SYNOPSIS
It initializes the environment with important module imports and preparation of script-wide variables.
#>
function Initialize-PSDSCAgentEnvironment {
	[CmdletBinding()]
	Param ()

	$script:PSDSCAgentEnvironment = [PSCustomObject]@{
		PowershellCore = $true
	}

	# Differentiate between Windows Powershell and Powershell Core.
	if ($PSVersionTable.PSVersion.Major -le 5) { $script:PSDSCAgentEnvironment.PowershellCore = $false }

	# Check whether PSDesiredStateConfiguration version 2+ is available.
	$psdscVersion = [version]'1.1';
	$modernDsc = $false
	foreach ($m in (Get-Module 'PSDesiredStateConfiguration' -ListAvailable -Verbose:$false)) {
		if ($m.Version.Major -gt 1) {
			$modernDSC = $true
			$psdscVersion = $m.Version
			break
		}
	}

	# Make sure PSDesiredStateConfiguration version 2+ is available if we're running in Powershell Core.
	if ($script:PSDSCAgentEnvironment.PowershellCore -and !$modernDSC) {
		throw 'Powershell Core requires at least PSDesiredStateConfiguration 2.0.0'
	}

	# Import PSDesiredStateConfiguration version 2+ if availabe and we're in Powershell Core.
	if ($script:PSDSCAgentEnvironment.PowershellCore -and $modernDSC) {
		Import-Module -Name 'PSDesiredStateConfiguration' -RequiredVersion $psdscVersion
	}
}