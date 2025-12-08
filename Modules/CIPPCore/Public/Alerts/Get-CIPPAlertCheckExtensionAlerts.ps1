function Get-CIPPAlertCheckExtensionAlerts {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    try {
        # Default to 24 hours if no input value is provided
        if ([int]$InputValue -gt 0) {
            $IntervalHours = [int]$InputValue
        } else {
            $IntervalHours = 24
        }

        # Calculate the timestamp threshold
        $ThresholdTime = (Get-Date).AddHours(-$IntervalHours).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

        # Get the CheckExtensionAlerts table
        $Table = Get-CIPPTable -tablename CheckExtensionAlerts

        # Query alerts for this tenant with timestamp filter for better performance
        $Filter = "PartitionKey eq 'CheckAlert' and tenantFilter eq '$TenantFilter' and Timestamp ge datetime'$ThresholdTime'"
        $RecentAlerts = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        if (!$RecentAlerts -or $RecentAlerts.Count -eq 0) {
            return
        }

        # Combine all recent alerts into a list
        $AlertData = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($Alert in $RecentAlerts) {
            $AlertDetails = [PSCustomObject]@{
                Message                  = $Alert.message
                Type                     = $Alert.type
                Url                      = $Alert.url
                Reason                   = $Alert.reason
                Score                    = $Alert.score
                Threshold                = $Alert.threshold
                PotentialUserName        = $Alert.potentialUserName
                PotentialUserDisplayName = $Alert.potentialUserDisplayName
                ReportedByIP             = $Alert.reportedByIP
                Timestamp                = $Alert.Timestamp
                Tenant                   = $TenantFilter
            }
            $AlertData.Add($AlertDetails)
        }

        # Write the combined alert trace
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -message "Failed to process check extension alerts: $ErrorMessage" -API 'Check Extension Alerts' -tenant $TenantFilter -sev Error
        return
    }
}
