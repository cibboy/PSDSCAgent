<#
TODO: help
#>
function Invoke-DscConfiguration {
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory = $true)]
		[ValidateScript({Test-Path $_})]
		[string]$MofFilePath,

		[ValidateScript({
			if ($_) {
				return Test-Path "Cert:\LocalMachine\My\$_"
			}
			else {
				return $true
			}
		})]
		[string]$Thumbprint
	)

	# Convert the mof file into something usable.
	$configuration = ConvertFrom-MofFile -FilePath $MofFilePath -Thumbprint $Thumbprint
	# Compute the sequence of resources to invoke, considering dependencies.
	$plan = Get-DscResourceSequentialSorting -Configuration $configuration

	# Prepare map of execution results.
	$execution = @{}
	foreach ($r in $plan) {
		$execution[$r] = [PsCustomObject]@{
			Status = 'NotRun'
			RebootRequired = $false
		}
	}

	$status = 'Running'
	foreach ($r in $plan) {
		Write-Verbose "[$($configuration.Metadata.Name)] [ Start      ] [$r]"
		$resource = $configuration.Resources[$r]

		# Make sure dependencies completed ok.
		$canContinue = $true
		foreach ($d in $resource.Parameters['DependsOn']) {
			if ($execution[$d].Status -ne 'Ok') {
				$canContinue = $false
				Write-Warning "Resource $r cannot run because dependency $d is not met ($($execution[$d].Status))."
			}
		}
		
		# Test/set only if dependecies are met.
		if ($canContinue) {
			try {
				# Prepare parameters by removing unasable ones.
				$params = @{}
				foreach ($p in $resource.Parameters.Keys) {
					if ($p -ne 'DependsOn') {
						$params[$p] = $resource.Parameters[$p]
					}
				}

				$module = @{ ModuleName = $resource.Resource.ModuleName; ModuleVersion = $resource.Resource.ModuleVersion }

				# Test the status of the resource.
				Write-Verbose "[$($configuration.Metadata.Name)] [ Start Test ] [$r]"
				$test = Invoke-DscResource -Name $resource.Resource.Name -ModuleName $module -Method Test -Property $params -ErrorAction Stop
				if (!$test.InDesiredState) {
					Write-Verbose "[$($configuration.Metadata.Name)] [ End   Test ] [$r] Resource is not in desired state."
					Write-Verbose "[$($configuration.Metadata.Name)] [ End   Test ] [$r]"
					
					# If the resource has drifted, invoke it with set.
					Write-Verbose "[$($configuration.Metadata.Name)] [ Start Set  ] [$r]"
					$set = Invoke-DscResource -Name $resource.Resource.Name -ModuleName $module -Method Set -Property $params -ErrorAction Stop
					Write-Verbose "[$($configuration.Metadata.Name)] [ End   Set  ] [$r] Resource has been set to desired state."
					Write-Verbose "[$($configuration.Metadata.Name)] [ End   Set  ] [$r]"

					if ($set.RebootRequired) {
						# If reboot is required, reboot according to the configuration.
						#TODO
						$execution[$r].RebootRequired = $true
						Write-Warning 'Reboot is required.'
						# Note: if working with PSDesiredStateConfiguration v1, reboot may still be performed by the LCM.
					}
				}
				else {
					Write-Verbose "[$($configuration.Metadata.Name)] [ End   Test ] [$r]"
					Write-Verbose "[$($configuration.Metadata.Name)] [ End   Test ] [$r] Resource is in desired state."
				}

				$execution[$r].Status = 'Ok'
			}
			catch {
				# If testing or setting ends in error, remember that this resource did not complete.
				# This is necessary for later resources that may have a dependency on this one.
				Write-Error $_
				$execution[$r].Status = 'Failed'
				$status = 'Failed'
			}
		}
		else {
			$status = 'Failed'
		}

		Write-Verbose "[$($configuration.Metadata.Name)] [ End        ] [$r]"
	}

	if ($status -eq 'Failed') {
		Write-Error 'Invoke-DscConfiguration failed.'
	}
	else {
		Write-Verbose 'Invoke-DscConfiguration terminated successfully.'
	}
}