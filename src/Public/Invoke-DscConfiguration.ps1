<#
TODO: help
#>
function Invoke-DscConfiguration {
	[CmdletBinding()]
	[OutputType([bool])]
	[OutputType([void])]
	Param (
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
		# Make sure Invoke-DscResource is enabled in Powershell Core, since
		# it's an experimental feature and it's disabled by default.
		if ($script:PSDSCAgentEnvironment.PowershellCore) {
			if (-not (Get-ExperimentalFeature PSDesiredStateConfiguration.InvokeDscResource -Verbose:$false | Select-Object -ExpandProperty Enabled)) {
				throw 'Experimental feature PSDesiredStateConfiguration.InvokeDscResource must be enabled to use this command. Use "Enable-ExperimentalFeature PSDesiredStateConfiguration.InvokeDscResource" and restart the Powershell session.'
			}
		}

		# If running in a session that uses DSC 1.1, warn if the LCM is configured
		# in a way that might interfere.
		if (!$script:PSDSCAgentEnvironment.ModernDSC) {
			$lcm = Get-DscLocalConfigurationManager -Verbose:$false

			if ($lcm.RefreshMode -ine 'Disabled') {
				Write-Warning 'It is strongly suggested that the LCM is disabled when using the PSDSCAgent.'
			}

			if ($lcm.RebootNodeIfNeeded) {
				Write-Warning 'It is strongly suggested that the LCM not control the reboot, so the PSDSCAgent can handle it.'
			}
		}
	}

	Process {
		# Convert the mof file into something usable.
		$configuration = ConvertFrom-MofFile -FilePath $MofFilePath -Thumbprint $Thumbprint
		# Compute the sequence of resources to invoke, considering dependencies.
		$plan = Get-DscResourceSequentialSorting -Configuration $configuration

		# Prepare a job id.
		$jobId = (New-Guid).Guid.ToUpperInvariant()

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
			if ($script:PSDSCAgentEnvironment.PowershellCore) { Write-Verbose "[$($configuration.Metadata.Name)] [ Start      ] [$r]" }
			$resource = $configuration.Resources[$r]

			# Make sure dependencies completed ok.
			$canContinue = $true
			foreach ($d in $resource.Parameters['DependsOn']) {
				if ($execution[$d].Status -ne 'Ok' -and $Mode -eq 'Apply') {
					$canContinue = $false
					Write-Warning "Resource $r cannot run because dependency $d is not met ($($execution[$d].Status))."
				}
			}

			# Temporarily avoid errors for resources that need custom implementation (not a full solution
			# since dependencies will not be executed).
			if ($resource.Resource.Name -in ('File', 'WaitForAll', 'WaitForAny', 'WaitForSome') -and $resource.Resource.ModuleName -eq 'PSDesiredStateConfiguration' -and $script:PSDSCAgentEnvironment.ModernDSC) {
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

					# Prepare module information.
					$module = @{ ModuleName = $resource.Resource.ModuleName; ModuleVersion = $resource.Resource.ModuleVersion }
					# If module is default PSDesiredStateConfiguration, make it a string as using a hashmap
					# can create issues with versions and PsDscRunAsCredential.
					if ($module['ModuleName'] -eq 'PSDesiredStateConfiguration') {
						$module = 'PSDesiredStateConfiguration'
					}

					# Deviate Log resource to internal implementation if on modern DSC.
					if ($resource.Resource.Name -eq 'Log' -and $resource.Resource.ModuleName -eq 'PSDesiredStateConfiguration' -and $script:PSDSCAgentEnvironment.ModernDSC) {
						$module = 'PSDSCAgent'
						$resource.Resource.Name = 'PSDSCLog'

						# Add "fake" parameters needed to emulate the original resource.
						$params['ResourceId'] = $r
						$params['ConfigurationName'] = $configuration.Metadata.Name
						$params['JobId'] = "{$jobId}"
					}

					# Modern DSC supports verbose.
					if (
						$script:PSDSCAgentEnvironment.ModernDSC -and
						(($PSCmdlet.MyInvocation.BoundParameters['Verbose'].IsPresent) -or $VerbosePreference -eq 'Continue')
					) {
						$params['Verbose'] = $true
					}

					# Prepare Invoke-DscResource parameters.
					$invokeParams = @{
						Name = $resource.Resource.Name
						ModuleName = $module
						Property = $params
						ErrorAction = 'Stop'
						OutVariable = 'invokeOutput'
					}

					# Test the status of the resource.
					if ($script:PSDSCAgentEnvironment.PowershellCore) { Write-Verbose "[$($configuration.Metadata.Name)] [ Start Test ] [$r]" }
					Invoke-DscResource @invokeParams -Method Test 4>&1 | Out-Null #TODO: breaks verbose output in PS5
					$test = $null
					#TODO: improve output rendering and code reuse.
					foreach ($o in $invokeOutput) {
						# Recover actual Invoke-DscResource output.
						if ($o.GetType().Name -eq 'InvokeDscResourceTestResult') {
							$test = $o
							continue
						}

						# Distinguish between text output and verbose output.
						$m = $o
						if ($o.GetType().Name -eq 'VerboseRecord') {
							$m = $o.Message
						}

						# Verbose output with proper formatting.
						if ($script:PSDSCAgentEnvironment.PowershellCore) {
							Write-Verbose "[$($configuration.Metadata.Name)]                [$r] $m"
						}
					}

					if (!$test.InDesiredState) {
						$execution[$r].Status = 'Failed'

						if ($script:PSDSCAgentEnvironment.PowershellCore) {
							Write-Verbose "[$($configuration.Metadata.Name)] [ End   Test ] [$r] Resource is not in desired state."
							Write-Verbose "[$($configuration.Metadata.Name)] [ End   Test ] [$r]"
						}

						if ($Mode -eq 'Apply') {
							# If the resource has drifted, invoke it with set.
							if ($script:PSDSCAgentEnvironment.PowershellCore) { Write-Verbose "[$($configuration.Metadata.Name)] [ Start Set  ] [$r]" }
							Invoke-DscResource @invokeParams -Method Set 4>&1 | Out-Null #TODO: breaks verbose output in PS5
							$set = $null
							#TODO: improve output rendering and code reuse.
							foreach ($o in $invokeOutput) {
								# Recover actual Invoke-DscResource output.
								if ($o.GetType().Name -eq 'InvokeDscResourceSetResult') {
									$set = $o
									continue
								}

								# Distinguish between text output and verbose output.
								$m = $o
								if ($o.GetType().Name -eq 'VerboseRecord') {
									$m = $o.Message
								}

								# Verbose output with proper formatting.
								if ($script:PSDSCAgentEnvironment.PowershellCore) {
									Write-Verbose "[$($configuration.Metadata.Name)]                [$r] $m"
								}
							}

							$execution[$r].Status = 'Ok'

							if ($script:PSDSCAgentEnvironment.PowershellCore) {
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
						$execution[$r].Status = 'Ok'

						if ($script:PSDSCAgentEnvironment.PowershellCore) {
							Write-Verbose "[$($configuration.Metadata.Name)] [ End   Test ] [$r]"
							Write-Verbose "[$($configuration.Metadata.Name)] [ End   Test ] [$r] Resource is in desired state."
						}
					}
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

			if ($script:PSDSCAgentEnvironment.PowershellCore) { Write-Verbose "[$($configuration.Metadata.Name)] [ End        ] [$r]" }
		}

		if ($status -eq 'Failed') {
			Write-Error 'Invoke-DscConfiguration failed.'
		}
		else {
			Write-Verbose 'Invoke-DscConfiguration terminated successfully.'
		}

		# If validation mode is requested, return true or false according to configuration drift.
		if ($Mode -eq 'Validate') {
			foreach ($r in $plan) {
				if ($execution[$r].Status -ne 'Ok') {
					return $false
				}
			}

			return $true
		}
	}

	End {}
}