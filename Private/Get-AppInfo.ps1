<#
.Synopsis
Created on:   28/10/2023
Created by:   Ben Whitmore
Filename:     Get-AppInfo.ps1

.Description
Function to get application information from ConfigMgr

.PARAMETER LogId
The component (script name) passed as LogID to the 'Write-Log' function. 
This parameter is built from the line number of the call from the function up the

.PARAMETER ApplicationName
The name of the application to get information for
#>
function Get-AppInfo {
    param (
        [Parameter(Mandatory = $false, ValuefromPipeline = $false, HelpMessage = "The component (script name) passed as LogID to the 'Write-Log' function")]
        [string]$LogId = $($MyInvocation.MyCommand).Name,
        [Parameter(Mandatory = $true, ValueFromPipeline = $false, Position = 0, HelpMessage = 'The name of the application(s) to get information for')]
        [object[]]$ApplicationName
    )
    begin {

        # Create an array for the display application information
        $applicationTypes = @()

        # Count the number of applications to process
        $applicationCount = $ApplicationName | Measure-Object | Select-Object -ExpandProperty Count

        # Create a counter
        $i = 0
    }
    process {
    
        # Iterate through each application and get the details
        foreach ($application in $applicationName) {

            # Increment counter
            $i++

            Write-Log -Message ("Processing application '{0}' of '{1}': '{2}'" -f $i, $applicationCount, $application.LocalizedDisplayName) -LogId $LogId
            Write-Host ("Processing application '{0}' of '{1}': '{2}'" -f $i, $applicationCount, $application.LocalizedDisplayName) -ForegroundColor Cyan
        
            try {
                # Grab the SDMPackgeXML which contains the application details
                Write-Log -Message ("Invoking Get-CMApplication where Id equals '{0}' for application '{1}'" -f $application.Id, $application.LocalizedDisplayName) -LogId $LogId
                Write-Host ("Invoking Get-CMApplication where Id equals '{0}' for application '{1}'" -f $application.Id, $application.LocalizedDisplayName) -ForegroundColor Cyan
                $xmlPackage = Get-CMApplication -Id $application.Id | Where-Object { $null -ne $_.SDMPackageXML } | Select-Object -ExpandProperty SDMPackageXML
        
                # Prepare xml from SDMPackageXML
                $xmlContent = [xml]($xmlPackage)

                # Get the total number of deployment types for the application
                $totalDeploymentTypes = ($xmlContent.AppMgmtDigest.Application.DeploymentTypes.DeploymentType | Measure-Object | Select-Object -ExpandProperty Count)
                Write-Log -Message ("The total number of deployment types for '{0}' with CI_ID '{1}' is '{2}')" -f $application.LocalizedDisplayName, $application.Id, $totalDeploymentTypes) -LogId $LogId

                # Create a new custom hashtable to store application details
                $applicationObject = [PSCustomObject]@{}

                # Add application details to PSCustomObject
                $applicationObject | Add-Member NoteProperty -Name Id -Value $application.Id
                $applicationObject | Add-Member NoteProperty -Name LogicalName -Value $xmlContent.AppMgmtDigest.Application.LogicalName
                $applicationObject | Add-Member NoteProperty -Name Name -Value $xmlContent.AppMgmtDigest.Application.title.'#text'
                $applicationObject | Add-Member NoteProperty -Name DisplayName -Value $xmlContent.AppMgmtDigest.Application.DisplayInfo.Info.Title
                $applicationObject | Add-Member NoteProperty -Name Description -Value $xmlContent.AppMgmtDigest.Application.DisplayInfo.Info.Description
                $applicationObject | Add-Member NoteProperty -Name Publisher -Value $xmlContent.AppMgmtDigest.Application.DisplayInfo.Info.Publisher
                $applicationObject | Add-Member NoteProperty -Name Version -Value $xmlContent.AppMgmtDigest.Application.DisplayInfo.Info.Version
                $applicationObject | Add-Member NoteProperty -Name ReleaseDate -Value $xmlContent.AppMgmtDigest.Application.DisplayInfo.Info.ReleaseDate
                $applicationObject | Add-Member NoteProperty -Name InfoUrl -Value $xmlContent.AppMgmtDigest.Application.DisplayInfo.Info.InfoUrl
                $applicationObject | Add-Member NoteProperty -Name Tags -Value $xmlContent.AppMgmtDigest.Application.DisplayInfo.Tags.Tag
                $applicationObject | Add-Member NoteProperty -Name TotalDeploymentTypes -Value $totalDeploymentTypes
                $applicationObject | Add-Member NoteProperty -Name IconId -Value $xmlContent.AppMgmtDigest.Resources.Icon.Id

                # If we have the logo, add the path
                if (-not ($null -eq $xmlContent.AppMgmtDigest.Resources.Icon.Id) ) {
                    $iconFileName = $xmlContent.AppMgmtDigest.Resources.Icon.Id + '.png'
                    $iconPath = (Join-Path -Path "$workingFolder_Root\Icons" -ChildPath $iconFileName)
                    Write-Log -Message ("Application icon path is '{0}'" -f $iconPath) -LogId $LogId
                    $applicationObject | Add-Member NoteProperty -Name IconPath -Value $iconPath
                }

                # Add IconData to last column for easy reading
                $applicationObject | Add-Member NoteProperty -Name IconData -Value $xmlContent.AppMgmtDigest.Resources.Icon.Data
                
                Write-Log -Message ("Id = '{0}', LogicalName = '{1}', Name = '{2}', DisplayName = '{3}', Description = '{4}', Publisher = '{5}', Version = '{6}', ReleaseDate = '{7}', InfoUrl = '{8}', Tags = '{9}', TotalDeploymentTypes = '{10}', IconId = '{11}', IconPath = '{12}', IconData '{13}'" -f `
                        $application.Id, `
                        $xmlContent.AppMgmtDigest.Application.LogicalName, `
                        $xmlContent.AppMgmtDigest.Application.title.'#text', `
                        $xmlContent.AppMgmtDigest.Application.DisplayInfo.Info.Title, `
                        $xmlContent.AppMgmtDigest.Application.DisplayInfo.Info.Description, `
                        $xmlContent.AppMgmtDigest.Application.DisplayInfo.Info.Publisher, `
                        $xmlContent.AppMgmtDigest.Application.DisplayInfo.Info.Version, `
                        $xmlContent.AppMgmtDigest.Application.DisplayInfo.Info.ReleaseDate, `
                        $xmlContent.AppMgmtDigest.Application.DisplayInfo.Info.InfoUrl, `
                        $xmlContent.AppMgmtDigest.Application.DisplayInfo.Tags.Tag, `
                        $totalDeploymentTypes, `
                        $xmlContent.AppMgmtDigest.Resources.Icon.Id, `
                        $iconPath, `
                        $xmlContent.AppMgmtDigest.Resources.Icon.Data) -LogId $LogId

                # Output the application object but substitue the base64 icon data for readability
                $applicationObjectOutput = $applicationObject | Select-Object -Property Id, LogicalName, Name, Description, Publisher, Version, ReleaseDate, InfoUrl, Tags, TotalDeploymentTypes, IconId, IconPath
                Write-Host "`n$applicationObjectOutput`n" -ForegroundColor Green

                # Add the application object to the array
                $applicationTypes += $applicationObject
            }
            catch {
                Write-Log -Message ("Could not get application information for '{0}'" -f $application.LocalizedDisplayName) -LogId $LogId -Severity 3
                Write-Warning -Message ("Could not get application information for '{0}'" -f $application.LocalizedDisplayName)
                Get-ScriptEnd -LogId $LogId -Message $_.Exception.Message
            }
            return $applicationTypes
        }
    }
}