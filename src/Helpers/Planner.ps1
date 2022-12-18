<#
TODO: help
#>
function Get-DscResourceSequentialSorting {
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory = $true)]
		[ValidateScript({
			return ($null -ne $_.ResourceList -and $null -ne $_.Resources)
		})]
		[PsCustomObject]$Configuration
	)

	$script:plan = @()

	# Recursive function to compute an orderd sequence of resources, considering
	# out-of-order dependencies.
	# This approach does not identify loops, but that is performed by the mof compiler in
	# Windows Powershell, so for now we're ok.
	function HandleDependencies {
		[CmdletBinding()]
		Param (
			[Parameter(Mandatory = $true)]
			[string]$ResourceId,

			[Parameter(Mandatory = $true)]
			[PsCustomObject]$Configuration
		)

		$props = $Configuration.Resources[$ResourceId].Parameters

		if ($null -ne $props['DependsOn'] -and $props['DependsOn'].Count -gt 0) {
			# Dependencies found, make sure to add those first.
			foreach ($d in $props['DependsOn']) {
				HandleDependencies -ResourceId $d -Configuration $Configuration
			}
		}
		
		# If no dependencies are found, or dependencies have been recursively added
		# to the plane, add the id to the sequence if not already in (base case).
		if ($script:plan -notcontains $ResourceId) {
			$script:plan += $ResourceId
		}
	}

	foreach ($r in $Configuration.ResourceList) {
		HandleDependencies -ResourceId $r -Configuration $Configuration
	}

	return $script:plan
}