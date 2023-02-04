
<#
.SYNOPSIS
It performs the actual call to Invoke-DscResource taking care of proper setup and output.

.DESCRIPTION
It performs the actual call to Invoke-DscResource taking care of proper setup and output.
It prepares a proper set of resource parameters, by adding those necessary and removing those that cannot be used.
It maps binary resources to the internal powershell implementation.
It handles output in a consistent way between Windows Powershell and Powershell Core.

.PARAMETER Resource
The resource definition used for calling Invoke-DscResource.

.PARAMETER Method
The method to call. Valid values are Get, Set and Test.

.PARAMETER JobId
An ID for the calling execution.
#>
function Invoke-WrappedDscResource {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true)]
		[PsCustomObject]$Resource,
		[Parameter(Mandatory = $true)]
		[ValidateSet('Get', 'Set', 'Test')]
		[string]$Method,
		[Parameter(Mandatory = $true)]
		[string]$JobId
	)

	Begin { }

	Process {
		#region -- Parameter setup --
		# Prepare parameters by removing unasable ones.
		$params = @{}
		foreach ($p in $Resource.Parameters.Keys) {
			if ($p -ne 'DependsOn') {
				$params[$p] = $Resource.Parameters[$p]
			}
		}

		# Prepare module information.
		$module = @{ ModuleName = $Resource.Resource.ModuleName; ModuleVersion = $Resource.Resource.ModuleVersion }
		# If module is default PSDesiredStateConfiguration, make it a string as using a hashmap
		# can create issues with versions and PsDscRunAsCredential.
		if ($module['ModuleName'] -eq 'PSDesiredStateConfiguration') {
			$module = 'PSDesiredStateConfiguration'
		}

		$resourceName = $Resource.Resource.Name

		# Deviate Log resource to internal implementation. This applies also to standard PSDesiredStateConfiguration 1.1
		# in Windows Powershell as it looks like the test method of the original binary resource always return $true
		# when invoked with Invoke-DscResource.
		if ($resourceName -eq 'Log' -and $Resource.Resource.ModuleName -eq 'PSDesiredStateConfiguration') {
			$module = 'PSDSCAgent'
			$resourceName = 'PSDSCLog'

			# Add "fake" parameters needed to emulate the original resource.
			$params['Resource'] = $Resource.Id
			$params['JobId'] = "{$JobId}"
		}

		# Modern DSC supports verbose as a resource parameter.
		if (
			$script:PSDSCAgentEnvironment.PowershellCore -and
			(($PSCmdlet.MyInvocation.BoundParameters['Verbose'].IsPresent) -or $VerbosePreference -eq 'Continue')
		) {
			$params['Verbose'] = $true
			$params['ErrorAction'] = 'Stop'
		}

		# Prepare Invoke-DscResource parameters.
		$invokeParams = @{
			Name = $resourceName
			ModuleName = $module
			Property = $params
			ErrorAction = 'Stop'
		}

		# Windows Powershell supports verbose output as a parameter of Invoke-DscResource.
		# VerbosePreference must be set to SilentlyContinue to prevent it to be printed on
		# console regardless of redirection and hide module importing.
		# At the same time, we must prevent the usage of these settings with modern DSC, as
		# it would become too verbose.
		$ps5VerbosePreference = $null
		if (
			!$script:PSDSCAgentEnvironment.PowershellCore -and
			(($PSCmdlet.MyInvocation.BoundParameters['Verbose'].IsPresent) -or $VerbosePreference -eq 'Continue')
		) {
			$invokeParams['Verbose'] = $true
			$ps5VerbosePreference = $VerbosePreference
			$VerbosePreference = 'SilentlyContinue'
		}
		#endregion -- Parameter setup --

		# Invoke DSC resource.
		$exception = $null
		try {
			Invoke-DscResource @invokeParams -OutVariable 'invokeOutput' -Method $Method 4>&1 | Out-Null
		}
		catch {
			$exception = $_
		}

		# Reset verbose preferences on Windows Powershell.
		if ($null -ne $ps5VerbosePreference) {
			$VerbosePreference = $ps5VerbosePreference
			$ps5VerbosePreference = $null
		}

		#region -- Output handling --
		$ret = $null
		foreach ($o in $invokeOutput) {
			#region -- Recover actual Invoke-DscResource output --
			# Test: true/false if in desired state.
			if ($o.GetType().Name -eq 'InvokeDscResourceTestResult') {
				# Powershell Core.
				$ret = $o.InDesiredState
				continue
			}
			elseif ($o.GetType().Name -eq 'Boolean') {
				# Windows Powershell.
				$ret = $o
				continue
			}

			# Set: true/false if it requires reboot.
			if ($o.GetType().Name -eq 'InvokeDscResourceSetResult') {
				# Powershell Core.
				$ret = $o.RebootRequired
				continue
			}
			elseif ($o.GetType().Name -eq 'Boolean') {
				# Windows Powershell.
				$ret = $o
				continue
			}

			# Get: actual object.
			if ($o.GetType().Name -eq 'Hashtable' -or $o.GetType().Name -eq 'CimInstance') {
				# Powershell Core (Hashtable) and Windows Powershell (CimInstance).
				$ret = $o
				continue
			}
			#endregion -- Recover actual Invoke-DscResource output --

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
		#endregion -- Output handling --

		if ($exception) {
			throw $exception
		}

		return $ret
	}

	End { }
}