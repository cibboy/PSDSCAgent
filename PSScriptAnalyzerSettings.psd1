@{
	# https://github.com/PowerShell/PSScriptAnalyzer/blob/development/RuleDocumentation

	Severity = @('Error', 'Warning', 'Information')
	ExcludeRules = @(
		'PSAvoidUsingEmptyCatchBlock',
		'PSUseToExportFieldsInManifest'
	)
	Rules = @{
		PSAvoidAssignmentToAutomaticVariable = @{
			Enable = $true
		}
		PSUseCompatibleSyntax = @{
			Enable = $true
			TargetVersions = @('5.1', '7.0', '7.1', '7.2', '7.3')
		}
		PSPlaceOpenBrace = @{
			Enable = $true
			OnSameLine = $true
			NewLineAfter = $true
			IgnoreOneLineBlock = $true
		}
		PSPlaceCloseBrace = @{
			Enable = $true
			NoEmptyLineBefore = $true
			IgnoreOneLineBlock = $true
			NewLineAfter = $true
		}
		PSUseConsistentIndentation = @{
			Enable = $true
			IndentationSize = 4
			Kind = 'tab'
		}
		PSUseConsistentWhitespace = @{
			Enable = $true
			CheckInnerBrace = $true
			CheckOpenBrace = $true
			CheckOpenParen = $true
			CheckOperator = $true
			CheckPipe = $true
			CheckPipeForRedundantWhitespace = $true
			CheckSeparator = $true
			CheckParameter = $true
			IgnoreAssignmentOperatorInsideHashTable = $true
		}
		PSProvideCommentHelp = @{
			Enable = $true
			ExportedOnly = $false
			BlockComment = $true
			VSCodeSnippetCorrection = $true
			Placement = 'before'
		}
	}
}
