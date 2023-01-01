<#
TODO: help
#>
function ConvertFrom-MofFile {
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory = $true)]
		[ValidateScript({ Test-Path $_ })]
		[string]$FilePath,

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
		[string]$Thumbprint
	)

	Begin {
		enum StatusType {
			None
			Metadata
			Credential
			Resource
			Array
		}

		function ResetParsingStatus {
			$script:ParsingStatus.Status = [StatusType]::None
			$script:ParsingStatus.PreviousStatus = [StatusType]::None
			$script:ParsingStatus.Properties = @{}
			$script:ParsingStatus.ActivePropertyName = $null
			$script:ParsingStatus.BlockId = $null
		}

		function StartMetadata {
			$script:ParsingStatus.Status = [StatusType]::Metadata
		}
		function EndMetadata {
			if ($script:ParsingStatus.Status -ne [StatusType]::Metadata) {
				throw 'Things got thrown out of sequence in initial metadata block.'
			}

			foreach ($p in $script:ParsingStatus.Properties.Keys) {
				$script:ParsingStatus.Result.Metadata | Add-Member -NotePropertyName $p -NotePropertyValue $script:ParsingStatus.Properties[$p]
			}

			ResetParsingStatus
		}
		function StartCredential {
			Param (
				[Parameter(Mandatory = $true)]
				[string]$Id
			)

			$script:ParsingStatus.Status = [StatusType]::Credential
			$script:ParsingStatus.BlockId = $Id
		}
		function EndCredential {
			$cred = [PsCustomObject]@{}
			foreach ($p in $script:ParsingStatus.Properties.Keys) {
				$cred | Add-Member -NotePropertyName $p -NotePropertyValue $script:ParsingStatus.Properties[$p]
			}
			$script:ParsingStatus.Result.Credentials.Add($script:ParsingStatus.BlockId, $cred)
		}
		function StartResource {
			Param (
				[Parameter(Mandatory = $true)]
				[string]$Id
			)

			$script:ParsingStatus.Status = [StatusType]::Resource
			$script:ParsingStatus.BlockId = $Id
		}
		function EndResource {
			$resource = [PsCustomObject]@{
				Id = $null
				Resource = [PsCustomObject]@{
					Name = $null
					ModuleName = $null
					ModuleVersion = $null
				}
				Parameters = @{}
			}
			foreach ($p in $script:ParsingStatus.Properties.Keys) {
				$value = $script:ParsingStatus.Properties[$p]

				if ($p -eq 'ConfigurationName') { continue }
				elseif ($p -eq 'ResourceID') { $resource.Id = $value }
				elseif ($p -eq 'SourceInfo') { $resource.Resource.Name = $value.Substring($value.LastIndexOf(':') + 1) }
				elseif ($p -eq 'ModuleName') { $resource.Resource.ModuleName = $value }
				elseif ($p -eq 'ModuleVersion') { $resource.Resource.ModuleVersion = $value }
				else { $resource.Parameters[$p] = $value }
			}

			$script:ParsingStatus.Result.Resources[$resource.Id] = $resource
			$script:ParsingStatus.Result.ResourceList += $resource.Id
		}
		function StartArray {
			$script:ParsingStatus.PreviousStatus = $script:ParsingStatus.Status
			$script:ParsingStatus.Status = [StatusType]::Array
			$script:ParsingStatus.Properties[$script:ParsingStatus.ActivePropertyName] = @()
		}
		function AddToArray {
			Param (
				[Parameter(Mandatory = $true)]
				$Object
			)

			$script:ParsingStatus.Properties[$script:ParsingStatus.ActivePropertyName] += $Object
		}
		function EndArray {
			$script:ParsingStatus.Status = $script:ParsingStatus.PreviousStatus
		}
		function ParsePropertyValue {
			[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
				'PSAvoidUsingConvertToSecureStringWithPlainText',
				'',
				Justification = 'Needed to convert encruypted credentials coming from the mof file'
			)]
			Param (
				[Parameter(Mandatory = $true)]
				[string]$Value,

				[string]$Thumbprint
			)

			# Remove string marks.
			if ($Value -like "'*'" -or $Value -like '"*"') { $Value = $Value.Substring(1, $Value.Length - 2) }

			# Note: int and bool are always converted. At least in Powershell 5 this is a problem, but it's
			# addressed later on (at the end of mof parsing) comparing the property type with the actual
			# resource implementation.
			# Try several parsings.
			# null
			if ($Value -eq 'NULL') {
				return $null
			}
			# Encrypted password
			if ($Value -like '-----BEGIN CMS-----\n*\n-----END CMS-----') {
				if (!$Thumbprint) {
					Write-Error 'This mof file has encrypted credentials, but a thumbprint for a decryption certificate has not been provided.'
					return $Value
				}

				try {
					$ret = $Value.Replace('\n', [Environment]::NewLine)
					$ret = (Unprotect-CmsMessage -Content $ret -To $Thumbprint)
					return $ret
				}
				catch {
					Write-Warning 'Unable to decrypt password.'
				}
			}
			# Object reference
			elseif ($Value -like '$*') {
				# If a password reference is found, return it. Otherwise continue with other type attempts.
				if ($null -ne $script:ParsingStatus.Result.Credentials[$Value]) {
					$password = ConvertTo-SecureString $script:ParsingStatus.Result.Credentials[$Value].Password -AsPlainText -Force
					return New-Object System.Management.Automation.PSCredential ($script:ParsingStatus.Result.Credentials[$Value].UserName, $password)
				}
			}
			# string (needs to revert escape charaters)
			elseif ($Value.GetType().Name -eq 'String') {
				$Value = $Value.Replace('\\', '\')
			}
			# int
			try {
				$ret = 0
				if ([int]::TryParse($Value, [ref]$ret)) {
					return $ret
				}
			}
			catch {}
			# bool
			try {
				$ret = $false
				if ([bool]::TryParse($Value, [ref]$ret)) {
					return $ret
				}
			}
			catch {}

			return $Value
		}
		function ParseGenericLine {
			Param (
				[Parameter(Mandatory = $true)]
				[string]$Line,

				[string]$Thumbprint
			)

			try {
				# Handle arrays differently from rest of properties.
				if ($script:ParsingStatus.Status -eq [StatusType]::Array) {
					# Remove comma at end of line.
					if ($Line -like '*,') {
						AddToArray (ParsePropertyValue -Value $Line.Substring(0, $Line.Length - 1) -Thumbprint $Thumbprint)
					}
					# Remove array end and return to resource.
					elseif ($Line -like '*};') {
						AddToArray (ParsePropertyValue -Value $Line.Substring(0, $Line.Length - 2) -Thumbprint $Thumbprint)
						EndArray
					}
					else {
						AddToArray (ParsePropertyValue -Value $Line -Thumbprint $Thumbprint)
					}
				}
				else {
					# "Split" on =
					$index = $Line.IndexOf('=')

					# Get property name.
					$name = $Line.Substring(0, $index).Trim()
					$script:ParsingStatus.ActivePropertyName = $name

					# Get property value.
					$value = $Line.Substring($index + 1).Trim()

					# Handle array property.
					if ($value -eq '{') {
						StartArray
					}
					# Handle inline array.
					elseif ($value -like '{*};') {
						$value = $value.Substring(1, $value.Length - 3)
						StartArray
						foreach ($v in $value.Split(',')) { AddToArray $v }
						EndArray
					}
					else {
						# Remove final semicolon from value.
						if ($value -like '*;') { $value = $value.Substring(0, $value.Length - 1).Trim() }
						$script:ParsingStatus.Properties[$name] = (ParsePropertyValue -Value $value -Thumbprint $Thumbprint)
					}
				}
			}
			catch {
				Write-Warning "Unrecognized line $Line"
			}
		}
		function StartBlock {
			Param (
				[Parameter(Mandatory = $true)]
				[string]$Line
			)

			# Get name of instance.
			$name = $Line.Replace('instance of ', '')
			$id = ''
			$as = $name.IndexOf(' as ')
			if ($as -gt 0) {
				$id = $name.Substring($as + 4)
				$name = $name.Substring(0, $as)
			}

			# Distinguish between resource, credential and metadata.
			if ($name -eq 'OMI_ConfigurationDocument') { StartMetadata }
			elseif ($name -eq 'MSFT_Credential') { StartCredential -Id $id }
			else { StartResource -Id $id }
		}
		function EndBlock {
			if ($script:ParsingStatus.Status -eq [StatusType]::None) {
				throw "Things got thrown out of sequence in $in."
			}

			# Ending property array.
			if ($script:ParsingStatus.Status -eq [StatusType]::Array) {
				$script:ParsingStatus.ActivePropertyName = $null
				$script:ParsingStatus.Status = [StatusType]::Resource
			}
			else {
				# Ending metadata at the end of the document.
				if ($script:ParsingStatus.Status -eq [StatusType]::Metadata) { EndMetadata }
				# Ending credential block.
				elseif ($script:ParsingStatus.Status -eq [StatusType]::Credential) { EndCredential }
				# Ending resource block.
				elseif ($script:ParsingStatus.Status -eq [StatusType]::Resource) { EndResource }

				ResetParsingStatus
			}
		}
	}

	Process {
		$script:ParsingStatus = [PsCustomObject]@{
			Status = [StatusType]::None
			PreviousStatus = [StatusType]::None
			Properties = @{}
			ActivePropertyName = $null
			BlockId = $null
			ActualResources = @{}

			Result = [PsCustomObject]@{
				Metadata = [PsCustomObject]@{}
				Credentials = @{}
				Resources = @{}
				ResourceList = @()
			}
		}

		$mof = Get-Content $FilePath

		foreach ($l in $mof) {
			$l = $l.Trim()
			# Skip empty lines.
			if ($l -eq '') { continue }

			# Start of metadata at the beginning of the document.
			if ($l -eq '/*') { StartMetadata }
			# End of metadata at the beginning of the document.
			elseif ($l -eq '*/') { EndMetadata }
			# Start of property block.
			elseif ($l -like 'instance of *') { StartBlock -Line $l }
			# End of property block.
			elseif ($l -eq '};') { EndBlock }
			# Start of property block (after instance of).
			elseif ($l -eq '{') {
				# Left curly brace indicates beginning of block. Make sure we are actually into one.
				if ($script:ParsingStatus.Status -eq [StatusType]::None) {
					throw 'Things got thrown out of sequence at the beginning of a block.'
				}
			}
			# All the rest.
			else { ParseGenericLine -Line $l -Thumbprint $Thumbprint }
		}

		# Fix parameter types for those properties which were converted into bool or int
		# but are actually strings.
		# This part assumes the resource is actually available. TODO: avoid this requirement
		# It's not really optimized, as avoiding parsing would probably be better.
		foreach ($rk in $script:ParsingStatus.Result.Resources.Keys) {
			$r = $script:ParsingStatus.Result.Resources[$rk]

			$module = @{ ModuleName = $r.Resource.ModuleName; ModuleVersion = $r.Resource.ModuleVersion }
			if ($module['ModuleName'] -eq 'PSDesiredStateConfiguration' -and $module['ModuleVersion'] -eq '1.0') {
				$module['ModuleVersion'] = '1.1'
			}

			# Load actual resrouce definition.
			$key = "$($r.Resource.Name)_$($module['ModuleName'])_$($module['ModuleVersion'])"
			$actual = $script:ParsingStatus.ActualResources[$key]
			if ($null -eq $actual) { $actual = Get-DscResource $r.Resource.Name -Module $module -ErrorAction SilentlyContinue -Verbose:$false }

			# If actual resource found, look for used properties, looking for bool or int that were converted
			# but are actually strings.
			if ($actual) {
				$newParams = @{}

				foreach ($pk in $r.Parameters.Keys) {
					$p = $r.Parameters[$pk]
					$actualP = $actual.Properties | Where-Object { $_.Name -eq $pk }

					if ($actualP) {
						# Direct bool or int to string.
						if (($p.GetType().Name -eq 'Boolean' -or $p.GetType().Name -like 'Int*') -and $actualP.PropertyType -eq '[string]') {
							$p = $p.ToString()
						}
						# Array of bool or int to array of strings.
						elseif ($p -is [array] -and $actualP.PropertyType -eq '[string[]]') {
							for ($i = 0; $i -lt $p.Count; $i++) {
								$p[$i] = $p[$i].ToString()
							}
						}
					}

					$newParams[$pk] = $p
				}

				$script:ParsingStatus.Result.Resources[$rk].Parameters = $newParams
			}
		}

		return [PsCustomObject]@{
			Metadata = $script:ParsingStatus.Result.Metadata
			ResourceList = $script:ParsingStatus.Result.ResourceList
			Resources = $script:ParsingStatus.Result.Resources
		}
	}

	End {}
}