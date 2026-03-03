function New-CIPPWebhookRootSchema {
    [CmdletBinding()]
    param(
        [string]$Title,
        [string]$Tenant,
        [string]$AlertType = 'WebhookAlert',
        [string]$Source,
        $Data
    )

    [pscustomobject]@{
        SchemaVersion = '1.0'
        Timestamp     = (Get-Date).ToUniversalTime().ToString('o')
        AlertType     = $AlertType
        Source        = $Source
        Title         = $Title
        Tenant        = $Tenant
        Data          = $Data
    }
}
