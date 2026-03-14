function Invoke-GetCippAlerts {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Alerts = [System.Collections.Generic.List[object]]::new()
    $Table = Get-CippTable -tablename CippAlerts
    $PartitionKey = Get-Date -UFormat '%Y%m%d'
    $Filter = "PartitionKey eq '{0}'" -f $PartitionKey
    $Rows = Get-CIPPAzDataTableEntity @Table -Filter $Filter | Sort-Object TableTimestamp -Descending | Select-Object -First 10
    $Role = Get-CippAccessRole -Request $Request

    $CIPPVersion = $Request.Query.localversion
    $Version = Assert-CippVersion -CIPPVersion $CIPPVersion
    if ($Version.OutOfDateCIPP) {
        $Alerts.Add(@{
                title = 'CIPP Frontend Out of Date'
                Alert = 'Your CIPP Frontend is out of date. Please update to the latest version. Find more on the following '
                link  = 'https://docs.cipp.app/setup/self-hosting-guide/updating'
                type  = 'warning'
            })
        Write-LogMessage -message 'Your CIPP Frontend is out of date. Please update to the latest version' -API 'Updates' -tenant 'All Tenants' -sev Alert

    }
    if ($Version.OutOfDateCIPPAPI) {
        $Alerts.Add(@{
                title = 'CIPP API Out of Date'
                Alert = 'Your CIPP API is out of date. Please update to the latest version. Find more on the following'
                link  = 'https://docs.cipp.app/setup/self-hosting-guide/updating'
                type  = 'warning'
            })
        Write-LogMessage -message 'Your CIPP API is out of date. Please update to the latest version' -API 'Updates' -tenant 'All Tenants' -sev Alert
    }

    if ($env:ApplicationID -eq 'LongApplicationID' -or $null -eq $env:ApplicationID) {
        $Alerts.Add(@{
                title          = 'SAM Setup Incomplete'
                Alert          = 'You have not yet completed your setup. Please go to the Setup Wizard in Application Settings to connect CIPP to your tenants.'
                link           = '/cipp/setup'
                type           = 'warning'
                setupCompleted = $false
            })
    }
    if ($role -like '*superadmin*') {
        $Alerts.Add(@{
                title = 'Superadmin Account Warning'
                Alert = 'You are logged in under a superadmin account. This account should not be used for normal usage.'
                link  = 'https://docs.cipp.app/setup/installation/owntenant'
                type  = 'error'
            })
    }
    if ($role -like '*admin*') {
        $AccessCheckTable = Get-CippTable -TableName AccessChecks

        try {
            $AccessPermissionsCache = Get-CIPPAzDataTableEntity @AccessCheckTable -Filter "PartitionKey eq 'AccessCheck' and RowKey eq 'AccessPermissions'" | Sort-Object Timestamp -Descending | Select-Object -First 1
            $AccessPermissions = $AccessPermissionsCache.Data | ConvertFrom-Json -ErrorAction Stop
        } catch {
            $AccessPermissions = $null
        }

        if ($AccessPermissions -and ($AccessPermissions.Success -eq $false -or @($AccessPermissions.ErrorMessages).Count -gt 0 -or @($AccessPermissions.MissingPermissions).Count -gt 0)) {
            $Alerts.Add(@{
                    title = 'SAM Permission Issues Detected'
                    Alert = 'Your environment has service account or permission issues. Open Access Checks in Admin Settings and run the Permissions check.'
                    link  = '/cipp/settings/permissions'
                    type  = 'warning'
                })
        }

        try {
            $GDAPRelationshipsCache = Get-CIPPAzDataTableEntity @AccessCheckTable -Filter "PartitionKey eq 'AccessCheck' and RowKey eq 'GDAPRelationships'" | Sort-Object Timestamp -Descending | Select-Object -First 1
            $GDAPRelationships = $GDAPRelationshipsCache.Data | ConvertFrom-Json -ErrorAction Stop
        } catch {
            $GDAPRelationships = $null
        }

        if ($GDAPRelationships -and @($GDAPRelationships.GDAPIssues).Count -gt 0) {
            $Alerts.Add(@{
                    title = 'GDAP Relationship Issues Detected'
                    Alert = 'Your environment has GDAP role or relationship issues. Open Access Checks in Admin Settings and run the GDAP check.'
                    link  = '/cipp/settings/permissions'
                    type  = 'warning'
                })
        }
    }
    if (!(![string]::IsNullOrEmpty($env:WEBSITE_RUN_FROM_PACKAGE) -or ![string]::IsNullOrEmpty($env:DEPLOYMENT_STORAGE_CONNECTION_STRING)) -and $env:AzureWebJobsStorage -ne 'UseDevelopmentStorage=true' -and $env:NonLocalHostAzurite -ne 'true') {
        $Alerts.Add(
            @{
                title = 'Function App in Write Mode'
                Alert = 'Your Function App is running in write mode. This will cause performance issues and increase cost. Please check this '
                link  = 'https://docs.cipp.app/setup/installation/runfrompackage'
                type  = 'warning'
            })
    }
    if ($Rows) { $Rows | ForEach-Object { $Alerts.Add($_) } }
    $Alerts = @($Alerts)

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Alerts
        })

}
