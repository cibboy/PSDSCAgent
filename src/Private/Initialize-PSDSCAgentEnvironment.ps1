<#
.SYNOPSIS
It initializes the environment with important module imports and preparation of script-wide variables.
#>
function Initialize-PSDSCAgentEnvironment {
	[CmdletBinding()]
	Param ()

	$script:PSDSCAgentEnvironment = [PSCustomObject]@{
		PowershellCore = $true
		ModernDSC = $false
	}

	# Differentiate between Windows Powershell and Powershell Core.
	if ($PSVersionTable.PSVersion.Major -le 5) { $script:PSDSCAgentEnvironment.PowershellCore = $false }

	# Check whether PSDesiredStateConfiguration version 2+ is available.
	$psdscVersion = [version]'1.1';
	foreach ($m in (Get-Module 'PSDesiredStateConfiguration' -ListAvailable -Verbose:$false)) {
		if ($m.Version.Major -gt 1) {
			$script:PSDSCAgentEnvironment.ModernDSC = $true
			$psdscVersion = $m.Version
			break
		}
	}

	# Import PSDesiredStateConfiguration version 2+ if availabe and we're in Powershell Core.
	if ($script:PSDSCAgentEnvironment.PowershellCore -and $script:PSDSCAgentEnvironment.ModernDSC) {
		Import-Module -Name 'PSDesiredStateConfiguration' -RequiredVersion $psdscVersion
	}
}