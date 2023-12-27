<#
.Synopsis
Created on:   2023.11.26
Created by:   Martynas Atkocius
Filename:     Get-DetectionMethodInfo.ps1

.Description
Function to get deployment type detection methods from ConfigMgr
Doesn't support grouped detection methods

.PARAMETER LogId
The component (script name) passed as LogID to the 'Write-Log' function. 
This parameter is built from the line number of the call from the function up the

.PARAMETER ApplicationName
The name of the application

.PARAMETER DeploymentTypeName
The name of the deployment type
#>
function Get-DetectionMethodInfo {
    param (
        [Parameter(Mandatory = $false, ValuefromPipeline = $false, HelpMessage = "The component (script name) passed as LogID to the 'Write-Log' function")]
        [string]$LogId = $($MyInvocation.MyCommand).Name,
        [Parameter(Mandatory = $true, ValueFromPipeline = $false, HelpMessage = 'The name of the application')]
        [string]$ApplicationName,
        [Parameter(Mandatory = $true, ValueFromPipeline = $false, HelpMessage = 'The name of the deployment type')]
        [string]$DeploymentTypeName
    )
    begin {

        # Create an empty array to store the detection methods
        $detectionMethods = @()
    }
    process {

        try {

            # Get a detection provider from app SDMPackageXML
            $cmApp = Get-CMApplication -ApplicationName $ApplicationName
            [xml]$appXML = $cmApp.SDMPackageXML
            $deploymentTypeXML = $appXML.AppMgmtDigest.DeploymentType | where { $_.Title.InnerText -eq $DeploymentTypeName }
            $detectionProvider = $deploymentTypeXML.Installer.DetectAction.Provider
            
            if ($detectionProvider -eq 'Script') {
                
                Write-Log -Message ("There is 1 script detection method for deployment type '{0}'" -f $DeploymentTypeName) -LogId $LogId
                Write-Host ("There is 1 script detection method for deployment type '{0}'" -f $DeploymentTypeName) -ForegroundColor Cyan

                $detectionScriptBody = $deploymentTypeXML.Installer.DetectAction.Args.Arg.Where({ $_.Name -eq 'ScriptBody' }).InnerText

                # Add detection method details to a new PSCustomObject
                $detectionObject = [PSCustomObject]@{
                    ApplicationName         = $ApplicationName
                    Application_LogicalName = $appXML.AppMgmtDigest.Application.LogicalName
                    DeploymentTypeName      = $DeploymentTypeName
                    DTLogicalName           = $deploymentTypeXML.LogicalName
                    DetectionType           = 'Script'
                    ScriptFileName          = ($deploymentTypeXML.LogicalName + '.ps1')
                    ScriptBody              = $detectionScriptBody
                }

                Write-Log -Message ("ApplicationName = '{0}', Application_LogicalName = '{1}', DeploymentTypeName = '{2}', DTLogicalName = '{3}', DetectionType = '{4}', ScriptFileName = '{5}', `
                    ScriptBody = '{6}'" -f `
                        $ApplicationName, `
                        $appXML.AppMgmtDigest.Application.LogicalName, `
                        $DeploymentTypeName, `
                        $deploymentTypeXML.LogicalName, `
                        'Script', `
                        ($deploymentTypeXML.LogicalName + '.ps1'), `
                        $detectionScriptBody) -LogId $LogId

                # Output the detection object
                Write-Host "`n$detectionObject`n" -ForegroundColor Green

                # Add the detection object to the array
                $detectionMethods += $detectionObject
            }
            elseif ($detectionProvider -eq 'Local') {

                # Get all detection methods into an array
                $cmAppDT = Get-CMDeploymentType -ApplicationName $ApplicationName -DeploymentTypeName $DeploymentTypeName
                $appDetectionArray = @(Get-CMDeploymentTypeDetectionClause -InputObject $cmAppDT)

                Write-Log -Message ("The total number of (local) detection methods for deployment type '{0}' is '{1}'" -f $DeploymentTypeName, $appDetectionArray.Count) -LogId $LogId
                Write-Host ("The total number of (local) detection methods for deployment type '{0}' is '{1}'" -f $DeploymentTypeName, $appDetectionArray.Count) -ForegroundColor Cyan

                foreach ($method in $appDetectionArray) {

                    # If there's an OR connector, throw a warning since Intune doesn't support it
                    if ($method.Connector -eq 'Or') {
                        Write-Log -Message ("Detection methods for deployment type '{0}' contain OR connector that's not supported in Intune" -f $DeploymentTypeName) -LogId $LogId -Severity 2
                        # Write-Host ("Detection methods for deployment type '{0}' contain OR connector that's not supported in Intune" -f $DeploymentTypeName) -ForegroundColor Cyan
                        Write-Warning -Message ("Detection methods for deployment type '{0}' contain OR connector that's not supported in Intune" -f $DeploymentTypeName)
                    }

                    # Add detection method details to a new PSCustomObject
                    $detectionObject = [PSCustomObject]@{
                        ApplicationName         = $ApplicationName
                        Application_LogicalName = $appXML.AppMgmtDigest.Application.LogicalName
                        DeploymentTypeName      = $DeploymentTypeName
                        DTLogicalName           = $deploymentTypeXML.LogicalName
                        LogicalName             = $method.Setting.LogicalName
                        DetectionType           = $method.SettingSourceType
                        Connector               = $method.Connector
                        PropertyPath            = $method.PropertyPath
                        DataType                = $method.DataType.Name
                        Operator                = $method.Operator
                        ConstValue              = $method.Constant.Value
                        SettingIs64Bit          = $method.Setting.Is64Bit
                        SettingPath             = $method.Setting.Path
                        SettingFileOrFolderName = $method.Setting.FileOrFolderName
                        SettingProductCode      = $method.Setting.ProductCode
                        SettingLocation         = $method.Setting.Location
                        SettingValueName        = $method.Setting.ValueName
                    }

                    Write-Log -Message ("ApplicationName = '{0}', Application_LogicalName = '{1}', DeploymentTypeName = '{2}', DTLogicalName = '{3}', LogicalName = '{4}', DetectionType = '{5}', Connector = '{6}', `
                        PropertyPath = '{7}', DataType = '{8}', Operator = '{9}', ConstValue = '{10}', SettingIs64Bit = '{11}', SettingPath = '{12}', SettingFileOrFolderName = '{13}', SettingProductCode = '{14}', `
                        SettingLocation = '{15}', SettingValueName = '{16}'" -f `
                            $ApplicationName, `
                            $appXML.AppMgmtDigest.Application.LogicalName, `
                            $DeploymentTypeName, `
                            $deploymentTypeXML.LogicalName, `
                            $method.Setting.LogicalName, `
                            $method.SettingSourceType, `
                            $method.Connector, `
                            $method.PropertyPath, `
                            $method.DataType.Name, `
                            $method.Operator, `
                            $method.Constant.Value, `
                            $method.Setting.Is64Bit, `
                            $method.Setting.Path, `
                            $method.Setting.FileOrFolderName, `
                            $method.Setting.ProductCode, `
                            $method.Setting.Location, `
                            $method.Setting.ValueName) -LogId $LogId

                    # Output the detection object
                    Write-Host "`n$detectionObject`n" -ForegroundColor Green

                    # Add the detection object to the array
                    $detectionMethods += $detectionObject
                }
            }
            else {
                Write-Log -Message ("Warning: Could not get detection method provider for deployment type '{0}'" -f $DeploymentTypeName) -LogId $LogId -Severity 2
                Write-Host ("Warning: Could not get detection method provider for deployment type '{0}'" -f $DeploymentTypeName) -ForegroundColor Yellow
            }

            return $detectionMethods

        }
        catch {
            Write-Log -Message ("Could not get detection method information for application '{0}' deployment type '{1}'" -f $ApplicationName, $DeploymentTypeName) -LogId $LogId -Severity 3
            Write-Warning -Message ("Could not get detection method information for application '{0}' deployment type '{1}'" -f $ApplicationName, $DeploymentTypeName)
            Write-Warning -Message ("Error message: '{0}'" -f $_.Exception.Message)
            Get-ScriptEnd -LogId $LogId -ErrorMessage $_.Exception.Message
        }
    }
}