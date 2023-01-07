﻿<#
.SYNOPSIS
Get method for the resource. It simply returns the message.
#>
function Get-TargetResource {
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
		'PSReviewUnusedParameter',
		'',
		Justification = 'The get must ignore all input and return the message'
	)]
	Param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$ResourceId,

		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$ConfigurationName,

		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$JobId,

		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$Message
	)

	return @{
		Message = $Message
	}
}

<#
.SYNOPSIS
Set method for the resource. It writes a message to the Microsoft-Windows-Desired State Configuration/Analytic
event log using a syntax similar to the one created by the default Log resource.
#>
function Set-TargetResource {
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
		'PSUseShouldProcessForStateChangingFunctions',
		'',
		Justification = 'This is a set for a DSC resource'
	)]
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$ResourceId,

		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$ConfigurationName,

		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$JobId,

		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$Message
	)

	$JobId = $JobId # Format: {<guid>}
	$WMIMessageChannel = 1
	$ResourceId = $ResourceId # Format: [Log]<resource name>
	$MessageBody = "[$ConfigurationName]:                            $ResourceId $Message"

	Write-Verbose "Adding message $Message to Microsoft-Windows-Dsc/Analytic"
	New-WinEvent -ProviderName 'Microsoft-Windows-Dsc' -Id 4098 -Payload @($JobId, $WMIMessageChannel, $ResourceId, $MessageBody)
}

<#
.SYNOPSIS
Test method for the resource. It always return false as per documentation.
https://learn.microsoft.com/en-us/powershell/dsc/reference/resources/windows/logresource?view=dsc-1.1
#>
function Test-TargetResource {
	[CmdletBinding()]
	[OutputType([bool])]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
		'PSReviewUnusedParameter',
		'',
		Justification = 'The test must ignore all input and return false'
	)]
	Param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$ResourceId,

		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$ConfigurationName,

		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$JobId,

		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$Message
	)

	# Always return false: https://learn.microsoft.com/en-us/powershell/dsc/reference/resources/windows/logresource?view=dsc-1.1
	return $false
}

Export-ModuleMember -Function *-TargetResource