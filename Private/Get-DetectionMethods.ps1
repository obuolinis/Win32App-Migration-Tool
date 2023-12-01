<#
.Synopsis
Created on:   2023.11.26
Created by:   Martynas Atkocius
Filename:     Get-DetectionMethods.ps1

.Description
Function to get deployment type detection methods from ConfigMgr

.PARAMETER LogId
The component (script name) passed as LogID to the 'Write-Log' function. 
This parameter is built from the line number of the call from the function up the

.PARAMETER DeploymentTypeXML
The XML object of the deployment type

.PARAMETER ApplicationName
The name of the application

.PARAMETER DeploymentTypeName
The name of the deployment type
#>
function Get-DetectionMethods {
    param (
        [Parameter(Mandatory = $false, ValuefromPipeline = $false, HelpMessage = "The component (script name) passed as LogID to the 'Write-Log' function")]
        [string]$LogId = $($MyInvocation.MyCommand).Name,
        [Parameter(Mandatory = $false, ValueFromPipeline = $false, HelpMessage = 'The name of the application')]
        [string]$ApplicationName,
        [Parameter(Mandatory = $false, ValueFromPipeline = $false, HelpMessage = 'The name of the deployment type')]
        [string]$DeploymentTypeName,
        [Parameter(Mandatory = $false, ValueFromPipeline = $false, HelpMessage = 'The XML object of the deployment type')]
        [System.Xml.XmlElement]$DeploymentTypeXML
    )
    begin {

        # Create an empty array to store the detection methods
        $detectionMethods = @()
    }
    process {

        try {

            # Get the detection provider from DeploymentTypeXML
            if (-not $DeploymentTypeXML) {
                $CMApp = Get-CMApplication -ApplicationName $ApplicationName
                [xml]$AppXML = $CMApp.SDMPackageXML
                $DeploymentTypeXML = $AppXML.AppMgmtDigest.DeploymentType | where { $_.Title.InnerText -eq $DeploymentTypeName }
            }
            $detectionProvider = $DeploymentTypeXML.Installer.DetectAction.Provider
            
            if ($detectionProvider -eq 'Script') {
                $detectionScriptBody = $DeploymentTypeXML.Installer.DetectAction.Args.Arg.Where({ $_.Name -eq 'ScriptBody' }).InnerText
                $detectionScriptRunAs32Bit = $DeploymentTypeXML.Installer.DetectAction.Args.Arg.Where({ $_.Name -eq 'RunAs32Bit' }).InnerText

            }
            elseif ($detectionProvider -eq 'Local') {
                $CMAppDT = Get-CMDeploymentType -ApplicationName $ApplicationName -DeploymentTypeName $DeploymentTypeName
                $AppDetectionArray = @(Get-CMDeploymentTypeDetectionClause -InputObject $CMAppDT)

                # Need to check all connectors - if any connector = OR, then we have a problem as Intune doesn't support OR

                foreach ($method in $AppDetectionArray) {
                    $detectionObject = [PSCustomObject]@{
                        DTLogicalName           = $DeploymentTypeXML.LogicalName
                        LogicalName             = $method.Setting.LogicalName
                        SettingSourceType       = $method.SettingSourceType
                        Connector               = $method.Connector
                        PropertyPath            = $method.PropertyPath
                        DataType                = $method.DataType.Name
                        Operator                = $method.Operator
                        ConstValue              = $method.Constant.Value
                        SettingLocation         = $method.Setting.Location
                        SettingIs64Bit          = $method.Setting.Is64Bit
                        SettingPath             = $method.Setting.Path
                        SettingFileOrFolderName = $method.Setting.FileOrFolderName
                        SettingDataType         = $method.Setting.SettingDataType.Name
                        SettingProductCode      = $method.Setting.ProductCode
                        SettingRootKey          = $method.Setting.RootKey
                        SettingKey              = $method.Setting.Key
                        SettingValueName        = $method.Setting.ValueName
                    }
                    $detectionMethods += $detectionObject
                }

<# 
                $AppDetectionArray | foreach {
                    [PSCustomObject]@{
                        LogicalName             = $_.Setting.LogicalName
                        SettingSourceType       = $_.SettingSourceType
                        Connector               = $_.Connector
                        PropertyPath            = $_.PropertyPath
                        DataType                = $_.DataType.Name
                        Operator                = $_.Operator
                        ConstValue              = $_.Constant.Value
                        SettingLocation         = $_.Setting.Location
                        SettingIs64Bit          = $_.Setting.Is64Bit
                        SettingPath             = $_.Setting.Path
                        SettingFileOrFolderName = $_.Setting.FileOrFolderName
                        SettingDataType         = $_.Setting.SettingDataType.Name
                        SettingProductCode      = $_.Setting.ProductCode
                        SettingRootKey          = $_.Setting.RootKey
                        SettingKey              = $_.Setting.Key
                        SettingValueName        = $_.Setting.ValueName
                    }
                } | select * | Out-GridView
 #>
            }

            return $detectionMethods

        }
        catch {
            Write-Log -Message ("Could not get detection method information for application '{0}'" -f $ApplicationName) -LogId $LogId -Severity 3
            Write-Warning -Message ("Could not get detection method information for application '{0}'" -f $ApplicationName)
            Write-Warning -Message ("Error: '{0}'" -f $_.Exception.Message)
            Write-Warning -Message ("Error: '{0}'" -f $_.InvocationInfo.PositionMessage)
            Get-ScriptEnd -LogId $LogId -Message $_.Exception.Message
        }
    }
}