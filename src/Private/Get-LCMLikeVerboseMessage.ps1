<#
.SYNOPSIS
It returns a string representing the verbose output of a specific phase in the execution
of a DSC configuration, mimicking the output provided by the LCM.

.DESCRIPTION
It returns a string representing the verbose output of a specific phase in the execution
of a DSC configuration, mimicking the output provided by the LCM.

.PARAMETER Phase
The phase the execution is in. It defines the "metadata" to show before actual messages.

.PARAMETER ResourceId
The id of the resource currently executing.

.PARAMETER Message
An optional message to add (usually used for output from resources).
#>
function Get-LCMLikeVerboseMessage {
	[CmdletBinding()]
	[OutputType([string])]
	Param (
		[Parameter(Mandatory = $true)]
		[ValidateSet('StartResource', 'EndResource', 'StartTest', 'EndTest', 'StartSet', 'EndSet', 'SkipSet', 'Message')]
		[string]$Phase,

		[string]$ResourceId = '',

		[string]$Message = '',

		[object]$TimeSpan = $null
	)

	# Build proper phase output.
	$p1 = ''
	$p2 = ''
	switch ($Phase) {
		'StartResource' {
			$p1 = 'Start'
			$p2 = 'Resource'
			break
		}
		'EndResource' {
			$p1 = 'End'
			$p2 = 'Resource'
			break
		}
		'StartTest' {
			$p1 = 'Start'
			$p2 = 'Test'
			break
		}
		'EndTest' {
			$p1 = 'End'
			$p2 = 'Test'
			break
		}
		'StartSet' {
			$p1 = 'Start'
			$p2 = 'Set'
			break
		}
		'EndSet' {
			$p1 = 'End'
			$p2 = 'Set'
			break
		}
		'SkipSet' {
			$p1 = 'Skip'
			$p2 = 'Set'
			break
		}
		Default {}
	}
	$p1 = $p1.PadRight(8, ' ')
	$p2 = $p2.PadRight(8, ' ')
	$p = $p1 + $p2
	if ($Phase -eq 'Message') { $p = "  $p  " }
	else { $p = "[ $p ]" }

	# Build final output.
	$ret = "[$env:COMPUTERNAME]:  $p "
	if ($ResourceId) { $ret += " [$ResourceId]" }
	if ($Message) { $ret += " $Message" }
	if ($TimeSpan) { $ret += " in $('{0:N4}' -f $TimeSpan.TotalSeconds) seconds." }

	return $ret
}