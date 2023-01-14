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
		if (!$script:PSDSCAgentEnvironment.PowershellCore) {
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

		$totalStart = Get-Date
		if ($Mode -eq 'Apply') { Write-Verbose (Get-LCMLikeVerboseMessage -Phase 'StartSet') }
		else { Write-Verbose (Get-LCMLikeVerboseMessage -Phase 'StartTest') }

		$status = 'Running'
		foreach ($r in $plan) {
			Write-Verbose (Get-LCMLikeVerboseMessage -Phase 'StartResource' -ResourceId $r)

			$resource = $configuration.Resources[$r]

			#TODO: refactor the function. Split test and set into separate private functions to simplify code management.

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
			if ($resource.Resource.Name -in ('File', 'WaitForAll', 'WaitForAny', 'WaitForSome') -and $resource.Resource.ModuleName -eq 'PSDesiredStateConfiguration' -and $script:PSDSCAgentEnvironment.PowershellCore) {
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

					$resourceName = $resource.Resource.Name

					# Deviate Log resource to internal implementation. This applies also to standard PSDesiredStateConfiguration 1.1
					# in Windows Powershell as it looks like the test method of the original binary resource always return $true.
					if ($resourceName -eq 'Log' -and $resource.Resource.ModuleName -eq 'PSDesiredStateConfiguration') {
						$module = 'PSDSCAgent'
						$resourceName = 'PSDSCLog'

						# Add "fake" parameters needed to emulate the original resource.
						$params['Resource'] = $r
						$params['JobId'] = "{$jobId}"
					}

					# Modern DSC supports verbose.
					if (
						$script:PSDSCAgentEnvironment.PowershellCore -and
						(($PSCmdlet.MyInvocation.BoundParameters['Verbose'].IsPresent) -or $VerbosePreference -eq 'Continue')
					) {
						$params['Verbose'] = $true #TODO: ps7 requires verbose on the resource for verbose output; ps5 doesn't support this
					}

					# Prepare Invoke-DscResource parameters.
					$invokeParams = @{
						Name = $resourceName
						ModuleName = $module
						Property = $params
						ErrorAction = 'Stop'
					}
					#TODO: ps5 requires verbose here for proper verbose output, but verbosepreference must be set to silentlycontinue; ps7 becomes superverbose
					#TODO: also, if verbosepreference is silentlycontinue (no -verbose in calling this function), ps5 still outputs verbose, ps7 doesn't
					#TODO: finally, this way ps5 skips verbose output of module loading (while ps7 outputs it if using it here -.-)
					$ps5VerbosePreference = $null
					if (
						!$script:PSDSCAgentEnvironment.PowershellCore -and
						(($PSCmdlet.MyInvocation.BoundParameters['Verbose'].IsPresent) -or $VerbosePreference -eq 'Continue')
					) {
						$invokeParams['Verbose'] = $true
						$ps5VerbosePreference = $VerbosePreference
						$VerbosePreference = 'SilentlyContinue'
					}

					$resourceStart = Get-Date

					# Test the status of the resource.
					Write-Verbose (Get-LCMLikeVerboseMessage -Phase 'StartTest' -ResourceId $r)
					$test = $true
					Invoke-DscResource @invokeParams -OutVariable 'invokeOutput' -Method Test 4>&1 | Out-Null
					if ($null -ne $ps5VerbosePreference) {
						$VerbosePreference = $ps5VerbosePreference
						$ps5VerbosePreference = $null
					}
					#TODO: improve output rendering and code reuse.
					foreach ($o in $invokeOutput) {
						# Recover actual Invoke-DscResource output.
						if ($o.GetType().Name -eq 'InvokeDscResourceTestResult') {
							# Powershell Core
							$test = $o.InDesiredState
							continue
						}
						elseif ($o.GetType().Name -eq 'Boolean') {
							# Windows Powershell
							$test = $o
							continue
						}

						# Distinguish between text output and verbose output.
						$m = $o
						if ($o.GetType().Name -eq 'VerboseRecord') {
							$m = $o.Message
						}

						# Verbose output with proper formatting.
						if (!$script:PSDSCAgentEnvironment.PowershellCore) {
							# Intercept resource verbose output (starts with [<computer name>], but it's without LCM:).
							if ($m -like "[[]$($env:COMPUTERNAME)[]]:  *") {
								$m = $m.Substring($m.IndexOf('DirectResourceAccess]') + 22)
							}
							else {
								continue
							}
						}
						Write-Verbose (Get-LCMLikeVerboseMessage -Phase 'Message' -ResourceId $r -Message $m)
					}

					$resourceEnd = Get-Date
					$timeDiff = $resourceEnd - $resourceStart

					if (!$test) {
						$execution[$r].Status = 'Failed'

						Write-Verbose (Get-LCMLikeVerboseMessage -Phase 'EndTest' -ResourceId $r -TimeSpan $timeDiff)

						if ($Mode -eq 'Apply') {
							$ps5VerbosePreference = $null
							if (
								!$script:PSDSCAgentEnvironment.PowershellCore -and
								(($PSCmdlet.MyInvocation.BoundParameters['Verbose'].IsPresent) -or $VerbosePreference -eq 'Continue')
							) {
								$invokeParams['Verbose'] = $true
								$ps5VerbosePreference = $VerbosePreference
								$VerbosePreference = 'SilentlyContinue'
							}

							$resourceStart = Get-Date

							# If the resource has drifted, invoke it with set.
							Write-Verbose (Get-LCMLikeVerboseMessage -Phase 'StartSet' -ResourceId $r)
							$reboot = $false
							Invoke-DscResource @invokeParams -OutVariable 'invokeOutput' -Method Set 4>&1 | Out-Null
							if ($null -ne $ps5VerbosePreference) {
								$VerbosePreference = $ps5VerbosePreference
								$ps5VerbosePreference = $null
							}
							#TODO: improve output rendering and code reuse.
							foreach ($o in $invokeOutput) {
								# Recover actual Invoke-DscResource output.
								if ($o.GetType().Name -eq 'InvokeDscResourceSetResult') {
									# Powershell Core
									$reboot = $o.RebootRequired
									continue
								}
								elseif ($o.GetType().Name -eq 'Boolean') {
									# Windows Powershell
									$reboot = $o
									continue
								}

								# Distinguish between text output and verbose output.
								$m = $o
								if ($o.GetType().Name -eq 'VerboseRecord') {
									$m = $o.Message
								}

								# Verbose output with proper formatting.
								if (!$script:PSDSCAgentEnvironment.PowershellCore) {
									# Intercept resource verbose output (starts with [<computer name>], but it's without LCM:).
									if ($m -like "[[]$($env:COMPUTERNAME)[]]:  *") {
										$m = $m.Substring($m.IndexOf('DirectResourceAccess]') + 22)
									}
									else {
										continue
									}
								}
								Write-Verbose (Get-LCMLikeVerboseMessage -Phase 'Message' -ResourceId $r -Message $m)
							}

							$execution[$r].Status = 'Ok'

							$resourceEnd = Get-Date
							$timeDiff = $resourceEnd - $resourceStart

							Write-Verbose (Get-LCMLikeVerboseMessage -Phase 'EndSet' -ResourceId $r -TimeSpan $timeDiff)

							if ($reboot) {
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

						Write-Verbose (Get-LCMLikeVerboseMessage -Phase 'EndTest' -ResourceId $r -TimeSpan $timeDiff)
						Write-Verbose (Get-LCMLikeVerboseMessage -Phase 'SkipSet' -ResourceId $r)
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

			Write-Verbose (Get-LCMLikeVerboseMessage -Phase 'EndResource' -ResourceId $r)
		}

		$totalEnd = Get-Date
		$timeDiff = $totalEnd - $totalStart
		if ($Mode -eq 'Apply') { Write-Verbose (Get-LCMLikeVerboseMessage -Phase 'EndSet' -TimeSpan $timeDiff) }
		else { Write-Verbose (Get-LCMLikeVerboseMessage -Phase 'EndTest' -TimeSpan $timeDiff) }

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

			#TODO: validation must behave like LCM, thus return a pscustomobject like this:
			#InDesiredState             : bool
			#ResourcesInDesiredState    : @(<list of resource ids (format: [<type>]<name>))
			#ResourcesNotInDesiredState : @(<list of resource ids (format: [<type>]<name>))
			#ReturnValue                : int (0 if no errors)
			#PSComputerName             : string (localhost since there is no remote capability yet)
			return $true
		}
	}

	End {}
}