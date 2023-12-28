<#
.Synopsis
Created on:   2023.12.12
Created by:   Martynas Atkocius
Filename:     migrate-sccm-app-to-intune-public.ps1

.Description
Script to migrate SCCM application to Intune.
Powershell module dependencies:
    - Win32App-Migration-Tool,
    - IntuneWin32App.

#>

#region User_Variables
$SiteCode = "BB1"
$SiteServer = "SCCM1.byteben.com"
$WorkingFolder = "C:\Win32AppMigrationTool"
$Win32AppMigrationModuleFolder = "C:\Github\repos\Win32App-Migration-Tool"
$TenantId = "domain.onmicrosoft.com"
$AADClientId = ""
#endregion User_Variables

#region Static_Variables
$AppDetailsFolder = "$WorkingFolder\Details"
$WorkingFolder_Root = $WorkingFolder # Used by Write-Log function
#endregion Static_Variables

#region Dependencies
Import-Module "$Win32AppMigrationModuleFolder\Win32AppMigrationTool.psd1" -Force
Import-Module IntuneWin32App -Force
Import-Module "$Win32AppMigrationModuleFolder\Private\Write-Log.ps1"
#endregion Dependencies


### APP EXPORTING ###

$CMAppName = "*chrome*"
New-Win32App -AppName $CMAppName -ProviderMachineName $SiteServer -SiteCode $SiteCode -WorkingFolder $WorkingFolder -ExportIcon -PackageApps


### APP IMPORTING TO INTUNE

### Helper functions
#region Helper_Functions
Function ConvertTo-IntuneOperator ([string]$Operator, [switch]$RegString = $false) {
    # Supported values for Intune operators are: equal, notEqual, greaterThanOrEqual, greaterThan, lessThanOrEqual or lessThan.
    # Respective SCCM values are: Equals, NotEquals, GreaterEquals, GreaterThan, LessEquals, LessThan
    # NB: Not all SCCM operators are supported in Intune. Additionally, reg string comparison only supports equal and notequal
    $outputOperator = "NotSupportedInIntune"
    if ($Operator -in ('Equals', 'NotEquals')) {
        $outputOperator = $Operator.TrimEnd('s')
    }
    elseif ($Operator -in ('GreaterEquals', 'LessEquals') -and -not $RegString) {
        $outputOperator = $Operator -replace 'Equals', 'ThanOrEqual'
    }
    elseif ($Operator -in ('GreaterThan', 'LessThan') -and -not $RegString) {
        $outputOperator = $Operator
    }
    return $outputOperator
}

Function ConvertTo-IntuneAppDetectionArray ([PSCustomObject]$DetectionMethodDetails) {
    $DetectionRuleArray = @()
    foreach ($detectionMethod in $DetectionMethodDetails) {
        $detectionRule, $detectionParams = $null
        try {
            if ($detectionMethod.DetectionType -eq 'Script') {
                $detectionScriptFile = Resolve-Path -Path "$AppDetailsFolder\$($DetectionMethodDetails.ScriptFileName)"
                $detectionRule = New-IntuneWin32AppDetectionRuleScript -ScriptFile $detectionScriptFile.Path
            }
            elseif ($detectionMethod.DetectionType -in ('File', 'Folder')) {
                $detectionParams = @{
                    Path                 = $detectionMethod.SettingPath
                    FileOrFolder         = $detectionMethod.SettingFileOrFolderName
                    Check32BitOn64System = !([System.Convert]::ToBoolean($detectionMethod.SettingIs64Bit))
                }
                if (!($detectionMethod.PropertyPath)) {
                    # Existence rule
                    $detectionParams.Add('Existence', $true)
                    $detectionParams.Add('DetectionType', 'exists')
                }
                else {
                    # Comparison rule: DateModified, DateCreated, Version, Size
                    $ruleType = $detectionMethod.PropertyPath
                    $detectionMethodOperator = ConvertTo-IntuneOperator $detectionMethod.Operator
                    if ($detectionMethodOperator -ne 'NotSupportedInIntune') {
                        $detectionParams.Add($ruleType, $true)
                        $detectionParams.Add('Operator', $detectionMethodOperator)
                        if ($ruleType -in ('DateModified', 'DateCreated')) {
                            $detectionDateTimeValue = [datetime]$detectionMethod.ConstValue
                            $detectionParams.Add('DateTimeValue', $detectionDateTimeValue)
                        }
                        elseif ($ruleType -eq 'Version') {
                            $detectionParams.Add('VersionValue', $detectionMethod.ConstValue)
                        }
                        elseif ($ruleType -eq 'Size') {
                            # We can't directly convert a file size-based rule since in SCCM size is configured in bytes while in Intune - megabytes
                            Write-Log -Message "Cannot directly convert file size-based detection rules - rule skipped" -LogId $LogId -Severity 2
                            Write-Warning "Cannot directly convert file size-based detection rules - rule skipped"
                            continue
                        }
                    }
                    else {
                        # Detection rule operator not supported in Intune
                        Write-Log -Message ("Detection rule operator '{0}' not supported in Intune - rule skipped" -f $detectionMethodOperator) -LogId $LogId -Severity 2
                        Write-Warning ("Detection rule operator '{0}' not supported in Intune - rule skipped" -f $detectionMethodOperator)
                        continue
                    }
                }
                $detectionRule = New-IntuneWin32AppDetectionRuleFile @detectionParams
            }
            elseif ($detectionMethod.DetectionType -in ('RegistryKey', 'Registry')) {
                $detectionParams = @{
                    KeyPath              = $detectionMethod.SettingLocation
                    Check32BitOn64System = !([System.Convert]::ToBoolean($detectionMethod.SettingIs64Bit))
                }
                if ($detectionMethod.DetectionType -eq 'Registry') {
                    $detectionParams.Add('ValueName', $detectionMethod.SettingValueName)
                }
                if ($detectionMethod.PropertyPath -match 'exists') {
                    # Existence rule
                    $detectionParams.Add('Existence', $true)
                    $detectionParams.Add('DetectionType', 'exists')
                }
                else {
                    # Comparison rule: String, Integer, Version
                    $ruleType = $detectionMethod.DataType -replace 'Int64', 'Integer'
                    $detectionMethodOperator = ConvertTo-IntuneOperator $detectionMethod.Operator
                    if ($ruleType -eq 'String') {
                        $detectionMethodOperator = ConvertTo-IntuneOperator $detectionMethod.Operator -RegString
                    }
                    if ($detectionMethodOperator -ne 'NotSupportedInIntune') {
                        $detectionParams.Add($ruleType + 'Comparison', $true)
                        $detectionParams.Add($ruleType + 'ComparisonOperator', $detectionMethodOperator)
                        $detectionParams.Add($ruleType + 'ComparisonValue', $detectionMethod.ConstValue)
                    }
                    else {
                        # Detection rule operator not supported in Intune
                        Write-Log -Message ("Detection rule operator '{0}' not supported in Intune - rule skipped" -f $detectionMethodOperator) -LogId $LogId -Severity 2
                        Write-Warning ("Detection rule operator '{0}' not supported in Intune - rule skipped" -f $detectionMethodOperator)
                        continue
                    }
                }
                $detectionRule = New-IntuneWin32AppDetectionRuleRegistry @detectionParams
            }
            elseif ($detectionMethod.DetectionType -eq 'MSI') {
                $detectionParams = @{
                    ProductCode = $detectionMethod.SettingProductCode
                }
                if ($detectionMethod.PropertyPath) {
                    $detectionMethodOperator = ConvertTo-IntuneOperator $detectionMethod.Operator
                    $detectionParams.Add('ProductVersionOperator', $detectionMethodOperator)
                    $detectionParams.Add('ProductVersion', $detectionMethod.ConstValue)
                }
                $detectionRule = New-IntuneWin32AppDetectionRuleMSI @detectionParams
            }
            else {
                Write-Log -Message ("Warning: Unsupported or empty detection type '{0}'" -f $detectionMethod.LogicalName) -LogId $LogId -Severity 2
                Write-Host ("Warning: Unsupported or empty detection type '{0}'" -f $detectionMethod.LogicalName) -ForegroundColor Yellow
            }
            $DetectionRuleArray += $detectionRule
        }
        catch {
            Write-Log -Message ("Could not convert detection method '{0}'" -f $detectionMethod.LogicalName) -LogId $LogId -Severity 3
            Write-Warning -Message ("Could not convert detection method '{0}'" -f $detectionMethod.LogicalName)
            Write-Warning -Message ("Error message: '{0}'" -f $_.Exception.Message)
        }
    }
    return $DetectionRuleArray
}
#endregion Helper_Functions

try {
    
    # Get application details from CSV files
    $AppDetails = Import-Csv -Path "$AppDetailsFolder\Applications.csv" -Encoding UTF8
    $DeploymentTypeDetails = Import-Csv -Path "$AppDetailsFolder\DeploymentTypes.csv" -Encoding UTF8
    $DetectionMethodDetails = Import-Csv -Path "$AppDetailsFolder\DetectionMethods.csv" -Encoding UTF8
    
    # Name, display name, description, version and publisher
    # $AppDisplayName = $AppDetails.Name
    $AppDisplayName = $AppDetails.DisplayName
    $AppDisplayName += if (-not $AppDisplayName.EndsWith('BB')) { ' BB' } # Add an optional suffix to the app name
    $AppDescription = $AppDetails.Description
    $AppVersion = $AppDetails.Version
    $AppPublisher = $AppDetails.Publisher
    
    # Install and uninstall command lines
    $InstallCommandLine = $DeploymentTypeDetails.InstallCommandLine
    $UninstallCommandLine = $DeploymentTypeDetails.UninstallCommandLine
    
    # Execution context and estimated installation time
    $InstallExperience = $DeploymentTypeDetails.ExecutionContext
    $InstallationTime = $DeploymentTypeDetails.ExecuteTime
    
    # App icon
    if ($AppDetails.IconPath) {
        $AppIconFile = Get-Item -Path $AppDetails.IconPath
        $AppIcon = New-IntuneWin32AppIcon -FilePath $AppIconFile.FullName
    }
    
    # Requirements
    # MIGRATION NOT IMPLEMENTED
    $RequirementRule = New-IntuneWin32AppRequirementRule -Architecture x64 -MinimumSupportedWindowsRelease W10_20H2
    
    # Detection
    $DetectionRuleArray = ConvertTo-IntuneAppDetectionArray -DetectionMethodDetails $DetectionMethodDetails
    
    # Scope tag
    $ScopeTagNameArray = @('YourScopeTagName')
    
    # Content (intunewin file)
    $IntuneWinFile = Get-Item "$WorkingFolder\Win32Apps\$($DeploymentTypeDetails.ApplicationName)\$($DeploymentTypeDetails.Name)\*.intunewin"
    $IntuneWinMetaData = Get-IntuneWin32AppMetaData -FilePath $IntuneWinFile.FullName
        
    
    ### Params for Add-IntuneWin32App
    $IntuneAppParams = @{
        'FilePath'                = $IntuneWinFile.FullName
        'DisplayName'             = $AppDisplayName
        'Description'             = $AppDescription
        'AppVersion'              = $AppVersion
        'Publisher'               = $AppPublisher
        'InstallCommandLine'      = $InstallCommandLine
        'UninstallCommandLine'    = $UninstallCommandLine
        'AllowAvailableUninstall' = $true
        'InstallExperience'       = $InstallExperience
        'RestartBehavior'         = 'suppress'
        'Icon'                    = $AppIcon
        'DetectionRule'           = $DetectionRuleArray
        'RequirementRule'         = $RequirementRule
        'ScopeTagName'            = $ScopeTagNameArray
    }

    $IntuneAppParamsForLog = $IntuneAppParams | select * -ExcludeProperty Icon | ConvertTo-Json
    Write-Log -Message "Importing application into Intune with the following parameters: `n$IntuneAppParamsForLog`n" -LogId $LogId
    Write-Host "Importing application into Intune with the following parameters: `n$IntuneAppParamsForLog`n" -ForegroundColor Green

    Connect-MSIntuneGraph -TenantID $TenantId -ClientID $AADClientId
    $AppRequest = Add-IntuneWin32App @IntuneAppParams -Verbose
    $AppRequest | select * -ExcludeProperty largeIcon

}
catch {
    $ErrorMsg = $_.Exception.Message
    Write-Log -Message ("Could not import into Intune: application '{0}'. Error message: '{1}'" -f $AppDisplayName, $ErrorMsg) -LogId $LogId -Severity 3
    Write-Warning -Message ("Could not import into Intune: application '{0}'. Error message: '{1}'" -f $AppDisplayName, $ErrorMsg)
}
