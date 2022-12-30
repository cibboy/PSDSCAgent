<#
TODO: help
#>
function Invoke-DscConfiguration {
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory = $true)]
		[ValidateScript({ Test-Path $_ })]
		[string]$MofFilePath,

		[ValidateScript(
			{
				if ($_) {
					return Test-Path "Cert:\LocalMachine\My\$_"
				}
				else {
					return $true
				}
			}
		)]
		[string]$Thumbprint,

		[ValidateSet('Apply', 'Validate')]
		$Mode = 'Apply'
	)

	Begin {
		$PowershellCore = $true
		if ($PSVersionTable.PSVersion.Major -le 5) { $PowershellCore = $false }

		$ModernDSC = $false
		foreach ($m in (Get-Module PSDesiredStateConfiguration -ListAvailable)) {
			if ($m.Version.Major -gt 1) {
				$ModernDSC = $true
				break
			}
		}

		# Make sure Invoke-DscResource is enabled in Powershell Core, since
		# it's an experimental feature and it's disabled by default.
		if ($PowershellCore) {
			if (-not (Get-ExperimentalFeature PSDesiredStateConfiguration.InvokeDscResource | Select-Object -ExpandProperty Enabled)) {
				throw 'Experimental feature PSDesiredStateConfiguration.InvokeDscResource must be enabled to use this command. Use "Enable-ExperimentalFeature PSDesiredStateConfiguration.InvokeDscResource" and restart the Powershell session.'
			}
		}

		# If running in a session that uses DSC 1.1, warn if the LCM is configured
		# in a way that might interfere.
		if (!$ModernDSC) {
			$lcm = Get-DscLocalConfigurationManager

			if ($lcm.RefreshMode -ine 'Disabled') {
				Write-Warning 'It is strongly suggested that the LCM is disabled when using the PSDSCAgent.'
				#TODO: make sure that Get-DscResource works when the LCM is disabled
			}

			if ($lcm.RebootNodeIfNeeded) {
				Write-Warning 'It is strongly suggested that the LCM not control the reboot, so the PSDSCAgent handle it.'
				#TODO: make sure that this setting actually has impact if the LCM is in disabled
			}
		}
	}

	Process {
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
			if ($PowershellCore) { Write-Verbose "[$($configuration.Metadata.Name)] [ Start      ] [$r]" }
			$resource = $configuration.Resources[$r]

			# Make sure dependencies completed ok.
			$canContinue = $true
			foreach ($d in $resource.Parameters['DependsOn']) {
				if ($execution[$d].Status -ne 'Ok') {
					$canContinue = $false
					Write-Warning "Resource $r cannot run because dependency $d is not met ($($execution[$d].Status))."
				}
			}

			# Temporarily avoid errors for resources that need custom implementation (not a full solution
			# since dependencies will not be executed).
			if ($resource.Resource.Name -in ('File', 'Log', 'WaitForAll', 'WaitForAny', 'WaitForSome') -and $ModernDSC) {
				Write-Warning "Resource $r is of type $($resource.Resource.Name) and cannot be run Powershell Core."
				$canContinue = $false
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

					# Modern DSC supports verbose.
					if ($ModernDSC -and ($PSCmdlet.MyInvocation.BoundParameters['Verbose'].IsPresent) -or $VerbosePreference -eq 'Continue') {
						$params['Verbose'] = $true
					}

					$module = @{ ModuleName = $resource.Resource.ModuleName; ModuleVersion = $resource.Resource.ModuleVersion }
					if ($module['ModuleName'] -eq 'PSDesiredStateConfiguration' -and $module['ModuleVersion'] -eq '1.0') {
						$module['ModuleVersion'] = '1.1'
					}

					# Test the status of the resource.
					if ($PowershellCore) { Write-Verbose "[$($configuration.Metadata.Name)] [ Start Test ] [$r]" }
					$test = Invoke-DscResource -Name $resource.Resource.Name -ModuleName $module -Method Test -Property $params -ErrorAction Stop

					if (!$test.InDesiredState) {
						if ($PowershellCore) {
							Write-Verbose "[$($configuration.Metadata.Name)] [ End   Test ] [$r] Resource is not in desired state."
							Write-Verbose "[$($configuration.Metadata.Name)] [ End   Test ] [$r]"
						}

						if ($Mode -eq 'Apply') {
							# If the resource has drifted, invoke it with set.
							if ($PowershellCore) { Write-Verbose "[$($configuration.Metadata.Name)] [ Start Set  ] [$r]" }
							$set = Invoke-DscResource -Name $resource.Resource.Name -ModuleName $module -Method Set -Property $params -ErrorAction Stop

							if ($PowershellCore) {
								Write-Verbose "[$($configuration.Metadata.Name)] [ End   Set  ] [$r] Resource has been set to desired state."
								Write-Verbose "[$($configuration.Metadata.Name)] [ End   Set  ] [$r]"
							}

							if ($set.RebootRequired) {
								# If reboot is required, reboot according to the configuration.
								#TODO
								$execution[$r].RebootRequired = $true
								Write-Warning 'Reboot is required.'
								# Note: if working with PSDesiredStateConfiguration v1, reboot may still be performed by the LCM.
							}
						}
					}
					else {
						if ($PowershellCore) {
							Write-Verbose "[$($configuration.Metadata.Name)] [ End   Test ] [$r]"
							Write-Verbose "[$($configuration.Metadata.Name)] [ End   Test ] [$r] Resource is in desired state."
						}
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

			if ($PowershellCore) { Write-Verbose "[$($configuration.Metadata.Name)] [ End        ] [$r]" }
		}

		if ($status -eq 'Failed') {
			Write-Error 'Invoke-DscConfiguration failed.'
		}
		else {
			Write-Verbose 'Invoke-DscConfiguration terminated successfully.'
		}
	}

	End {}
}