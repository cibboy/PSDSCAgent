@{

	# Script module or binary module file associated with this manifest.
	RootModule = 'PSDSCLog.psm1'

	# Version number of this module.
	ModuleVersion = '1.0.0'

	# ID used to uniquely identify this module
	GUID = '08916cc8-535e-4669-8af5-b1b042c41da9'

	# Author of this module
	Author = 'Gabriele Seppi'

	# Company or vendor of this module
	# CompanyName = ''

	# Copyright statement for this module
	Copyright = 'Gabriele Seppi'

	# Description of the functionality provided by this module
	Description = 'Adds a new message to the Microsoft-Windows-Desired State Configuration/Analytic event log'

	# Minimum version of the Windows PowerShell engine required by this module
	PowerShellVersion = '7.0'

	# Functions to export from this module
	FunctionsToExport = @('Get-PSDSCLog', 'Set-PSDSCLog', 'Test-PSDSCLog')

	# DSC resources to export from this module
	DscResourcesToExport = @('PSDSCLog')
}