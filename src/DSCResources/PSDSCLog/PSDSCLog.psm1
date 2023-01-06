<#
.SYNOPSIS
Get method for the resource. It simply returns the message.
#>
function Get-PSDSCLog {
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
		'PSReviewUnusedParameter',
		'',
		Justification = 'The get should ignore all input and return the message itself'
	)]
	Param(
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
function Set-PSDSCLog {
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
		'PSUseShouldProcessForStateChangingFunctions',
		'',
		Justification = 'This is a set for a DSC resource'
	)]
	[CmdletBinding()]
	Param(
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

	New-WinEvent -ProviderName 'Microsoft-Windows-Dsc' -Id 4098 -Payload @($JobId, $WMIMessageChannel, $ResourceId, $MessageBody)
}

<#
.SYNOPSIS
Test method for the resource. It always return false as per documentation.
https://learn.microsoft.com/en-us/powershell/dsc/reference/resources/windows/logresource?view=dsc-1.1
#>
function Test-PSDSCLog {
	[CmdletBinding()]
	[OutputType([bool])]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
		'PSReviewUnusedParameter',
		'',
		Justification = 'The test must ignore all input and return false'
	)]
	Param(
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

[DscResource()]
class PSDSCLog {
	[DscProperty(Key)]
	[string] $ResourceId

	[DscProperty(Mandatory)]
	[string] $ConfigurationName

	[DscProperty(Mandatory)]
	[string] $JobId

	[DscProperty(Mandatory)]
	[string] $Message

	[PSDSCLog] Get() {
		$get = Get-PSDSCLog -ResourceId $this.ResourceId -ConfigurationName $this.ConfigurationName -JobId $this.JobId -Message $this.Message
		return $get
	}

	[void] Set() {
		Set-PSDSCLog -ResourceId $this.ResourceId -ConfigurationName $this.ConfigurationName -JobId $this.JobId -Message $this.Message
	}

	[bool] Test() {
		$test = Test-PSDSCLog -ResourceId $this.ResourceId -ConfigurationName $this.ConfigurationName -JobId $this.JobId -Message $this.Message
		return $test
	}
}