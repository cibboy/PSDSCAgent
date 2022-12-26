# Get public and private function definition files.
$Helpers = @(Get-ChildItem -Path $PSScriptRoot\Helpers -Recurse -Filter "*.ps1") | Sort-Object Name
#$Private = @(Get-ChildItem -Path $PSScriptRoot\Private -Recurse -Filter "*.ps1") | Sort-Object Name
$Public = @(Get-ChildItem -Path $PSScriptRoot\Public -Recurse -Filter "*.ps1") | Sort-Object Name

# Dots source the helper files.
foreach ($import in $Helpers) {
	try {
		. $import.FullName
		Write-Verbose -Message "Imported helper function file $($import.FullName)"
	}
	catch {
		Write-Error -Message "Failed to import helper function file $($import.FullName): $_"
	}
}

# Dots source the private files.
<#foreach ($import in $Private) {
	try {
		. $import.FullName
		Write-Verbose -Message "Imported private function $($import.FullName)"
	}
	catch {
		Write-Error -Message "Failed to import private function $($import.FullName): $_"
	}
}#>

# Dots source the public files.
foreach ($import in $Public) {
	try {
		. $import.FullName
		Write-Verbose -Message "Imported public function $($import.FullName)"
	}
	catch {
		Write-Error -Message "Failed to import public function $($import.FullName): $_"
	}
}

# Export functions of public files.
Export-ModuleMember -Function $Public.BaseName