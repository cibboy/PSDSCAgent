﻿<#
.SYNOPSIS
Creates a new PSDrive for later use, using a standard name, or removes it.
#>
function HandleSource {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true)]
		[ValidateSet('Map', 'Unmap')]
		[string]$Operation,

		[string]$SourcePath,

		[PsCredential]$Credential
	)

	if ($Operation -eq 'Map') {
		$params = @{
			Name = '__PSDSCFile'
			PSProvider = 'FileSystem'
			Root = $SourcePath
			Verbose = $false
		}
		if ($null -ne $Credential -and $Credential -ne [PsCredential]::Empty) {
			$params['Credential'] = $Credential
		}

		$null = New-PSDrive @params
	}

	else {
		Remove-PSDrive -Name '__PSDSCFile'
	}
}

<#
.SYNOPSIS
Get method for the resource. It gets some basic information about the specified path.
#>
function Get-TargetResource {
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
		'PSReviewUnusedParameter',
		'',
		Justification = 'The get considers only the key property DestinationPath'
	)]
	Param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$DestinationPath,

		# Validation set includes 'Directory' in order to allow for proper parameter
		# return on get when a folder is selected (due to how DSC handles return object
		# validation).
		[ValidateSet('Archive', 'Hidden', 'ReadOnly', 'System', 'Directory')]
		[string[]]$Attributes,

		[ValidateSet('CreatedDate', 'ModifiedDate', 'SHA-1', 'SHA-256', 'SHA-512')]
		[string]$Checksum,

		[string]$Contents,

		[PsCredential]$Credential,

		[ValidateSet('Absent', 'Present')]
		[string]$Ensure = 'Present',

		[bool]$Force = $false,

		[bool]$Recurse = $false,

		[string]$SourcePath,

		[ValidateSet('Directory', 'File')]
		[string]$Type = 'File',

		[bool]$MatchSource = $false
	)

	$ret = @{
		DestinationPath = $DestinationPath
		Attributes = $null
		Checksum = $null
		Contents = $null
		CreatedDate = $null
		Credential = $null
		Ensure = ''
		Force = $null
		MatchSource = $null
		ModifiedDate = $null
		Recurse = $null
		Size = $null
		SourcePath = $null
		SubItems = $null
		Type = $null
	}

	$item = Get-Item -Path $DestinationPath -Force -ErrorAction SilentlyContinue

	if ($item) {
		# Parse attributes into a string array.
		$attrs = $item.Attributes.ToString().ToLowerInvariant().Split(', ', [StringSplitOptions]::RemoveEmptyEntries)
		$attributes = @()
		foreach ($a in $attrs) {
			# Make sure only valid attributes are included.
			if (@('archive', 'hidden', 'readonly', 'system', 'directory') -contains $a) {
				$attributes += $a
			}
		}

		$type = 'file'
		$size = $item.Length

		# Directory. Size is 0.
		if ($attributes -contains 'directory') {
			$type = 'directory'
			$size = 0
		}

		# Populate properties.
		$ret['Attributes'] = $attributes
		$ret['CreatedDate'] = $item.CreationTime
		$ret['Ensure'] = 'present'
		$ret['ModifiedDate'] = $item.LastWriteTime
		$ret['Size'] = $size
		$ret['Type'] = $type
	}
	else {
		$ret['Ensure'] = 'absent'
	}

	return $ret
}

<#
.SYNOPSIS
Set method for the resource. It tries to mimic the behavior of the default File resource.
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
		[string]$DestinationPath,

		[ValidateSet('Archive', 'Hidden', 'ReadOnly', 'System')]
		[string[]]$Attributes,

		[ValidateSet('CreatedDate', 'ModifiedDate', 'SHA-1', 'SHA-256', 'SHA-512')]
		[string]$Checksum,

		[string]$Contents,

		[PsCredential]$Credential,

		[ValidateSet('Absent', 'Present')]
		[string]$Ensure = 'Present',

		[bool]$Force = $false,

		[bool]$Recurse = $false,

		[string]$SourcePath,

		[ValidateSet('Directory', 'File')]
		[string]$Type = 'File',

		[bool]$MatchSource = $false
	)

	# Handling a single file.
	if ($Type -eq 'File') {
		if ($PSBoundParameters.ContainsKey('SourcePath') -and $PSBoundParameters.ContainsKey('Contents')) {
			#TODO: throw?
		}

		# Copy from source.
		if ($PSBoundParameters.ContainsKey('SourcePath')) {
			#TODO
			# If the source is missing, throw
		}
		# Create with content.
		elseif ($PSBoundParameters.ContainsKey('Contents')) {
			#TODO
		}
		# Just ensure present or absent.
		else {
			#TODO
		}
	}

	# Handling a directory.
	else {
		if ($PSBoundParameters.ContainsKey('Contents')) {
			#TODO: throw?
		}

		# Copy from source.
		if ($PSBoundParameters.ContainsKey('SourcePath')) {
			#TODO
			# If the source is missing, create the destination folder and don't throw
		}
		# Just ensure present or absent.
		else {
			#TODO
		}
	}
}

<#
.SYNOPSIS
Test method for the resource. It tries to mimic the behavior of the default File resource.
#>
function Test-TargetResource {
	[CmdletBinding()]
	[OutputType([bool])]
	<#[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
		'PSReviewUnusedParameter',
		'',
		Justification = 'The test must ignore all input and return false'
	)]#>
	Param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$DestinationPath,

		[ValidateSet('Archive', 'Hidden', 'ReadOnly', 'System')]
		[string[]]$Attributes,

		[ValidateSet('CreatedDate', 'ModifiedDate', 'SHA-1', 'SHA-256', 'SHA-512')]
		[string]$Checksum,

		[string]$Contents,

		[PsCredential]$Credential,

		[ValidateSet('Absent', 'Present')]
		[string]$Ensure = 'Present',

		[bool]$Force = $false,

		[bool]$Recurse = $false,

		[string]$SourcePath,

		[ValidateSet('Directory', 'File')]
		[string]$Type = 'File',

		[bool]$MatchSource = $false
	)

	# Order of importance: present/absent > source/content > checksum > attributes

	#TODO: how do Attributes get in the mix? (they get ignored with ensure absent as per documentation)
	#TODO: add proper verbose output.

	$presentDestination = Test-Path $DestinationPath

	# Basic checks: cross Ensure-present/absent.
	if ($Ensure -eq 'Present' -and !$presentDestination) { return $false }
	if ($Ensure -eq 'Absent' -and $presentDestination) { return $false }

	# Handling a single file.
	if ($Type -eq 'File') {
		if ($PSBoundParameters.ContainsKey('SourcePath') -and $PSBoundParameters.ContainsKey('Contents')) {
			#TODO: throw
		}

		# If present and Ensure is 'Present', continue with checks.
		if ($Ensure -eq 'Present' -and $presentDestination) {
			# Copy from source.
			if ($PSBoundParameters.ContainsKey('SourcePath')) {
				$sourceFolder = Split-Path $SourcePath
				$fileName = Split-Path $SourcePath -Leaf

				# Map source folder.
				HandleSource -Operation Map -SourcePath $sourceFolder -Credential $Credential

				$source = "__PSDSCFile:\$fileName"
				$presentSource = Test-Path $source

				$ret = $false

				# Further checks can be avoided if the source is not present.
				if ($presentSource) {
					$sourceCheck = $null
					$destinationCheck = $null

					# No checksum requested: based on file name presence/absence.
					if ($null -eq $Checksum -or $Checksum -eq '') {
						$sourceCheck = $presentSource
						$destinationCheck = $presentDestination
					}
					# For SHA-* checksums, get source and destination checksum.
					elseif ($Checksum -in @('SHA-1', 'SHA-256', 'SHA-512')) {
						$sourceCheck = (Get-FileHash $source -Algorithm $Checksum).Hash
						$destinationCheck = (Get-FileHash $DestinationPath -Algorithm $Checksum).Hash
					}
					# Otherwise get source and destination date (creation or last edit).
					else {
						$sourceItem = Get-Item $source
						$destinationItem = Get-Item $DestinationPath

						if ($Checksum -eq 'CreatedDate') {
							$sourceCheck = $sourceItem.CreationTimeUtc
							$destinationCheck = $destinationItem.CreationTimeUtc
						}
						else {
							$sourceCheck = $sourceItem.LastWriteTimeUtc
							$destinationCheck = $destinationItem.LastWriteTimeUtc
						}
					}

					$ret = ($sourceCheck -eq $destinationCheck)
				}

				# Unmap source folder.
				HandleSource -Operation Unmap

				return $ret
			}
			# Create with content.
			elseif ($PSBoundParameters.ContainsKey('Contents')) {
				$present = Test-Path $DestinationPath

				# If Contents is specified, but Ensure is 'Absent', Ensure wins.
				if ($Ensure -eq 'Absent' -and $present) { return $false }

				if ($Ensure -eq 'Present') {
					if (!$present) { return $false }
					else {
						$content = Get-Content $DestinationPath -Raw
						return ($content -eq $Contents)
					}
				}

				return $true
			}
			# Only Ensure 'Present'; already checked.
			else {
				return $true
			}
		}

		# Otherwise requesting absent and the file is absent.
		else {
			return $true
		}
	}

	# Handling a directory.
	else {
		if ($PSBoundParameters.ContainsKey('Contents')) {
			#TODO: throw
		}

		# Copy from source.
		if ($PSBoundParameters.ContainsKey('SourcePath')) {
			HandleSource -Operation Map -SourcePath $SourcePath -Credential $Credential

			#TODO

			HandleSource -Operation Unmap
		}
		# Just ensure present or absent.
		else {
			$present = Test-Path $DestinationPath

			if ($Ensure -eq 'Present' -and !$present) { return $false }
			if ($Ensure -eq 'Absent' -and $present) { return $false }

			return $true
		}
	}

	return $true
}

Export-ModuleMember -Function *-TargetResource