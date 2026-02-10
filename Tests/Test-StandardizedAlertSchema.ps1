# Test script for the standardized alert schema

# Import the module (adjust path as needed)
Import-Module "$PSScriptRoot/../Modules/CIPPCore/CIPPCore.psd1" -Force

# Test 1: Simple string alert
Write-Host "`n=== Test 1: Simple String Alert ===" -ForegroundColor Cyan
$simpleAlert = "This is a test alert message"
$result1 = ConvertTo-CIPPAlertSchema -AlertData $simpleAlert -AlertType "Test" -Severity "Info" -Tenant "test.onmicrosoft.com" -Source "TestScript" -Title "Test Alert"
Write-Host ($result1 | ConvertTo-Json -Depth 10)

# Test 2: Array of objects (MFA Admin alert simulation)
Write-Host "`n=== Test 2: MFA Admin Alert ===" -ForegroundColor Cyan
$mfaAlerts = @(
    [PSCustomObject]@{
        Message           = "Admin user John Doe (john.doe@contoso.com) does not have MFA registered."
        UserPrincipalName = "john.doe@contoso.com"
        DisplayName       = "John Doe"
        Id                = "12345678-1234-1234-1234-123456789012"
        LastUpdated       = "2026-02-10T06:00:00Z"
        Tenant            = "contoso.onmicrosoft.com"
    },
    [PSCustomObject]@{
        Message           = "Admin user Jane Smith (jane.smith@contoso.com) does not have MFA registered."
        UserPrincipalName = "jane.smith@contoso.com"
        DisplayName       = "Jane Smith"
        Id                = "87654321-4321-4321-4321-210987654321"
        LastUpdated       = "2026-02-10T06:00:00Z"
        Tenant            = "contoso.onmicrosoft.com"
    }
)
$result2 = ConvertTo-CIPPAlertSchema -AlertData $mfaAlerts -AlertType "Security" -Severity "Critical" -Tenant "contoso.onmicrosoft.com" -TenantId "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" -Source "Get-CIPPAlertMFAAdmins" -Title "Admin users without MFA" -CIPPURL "https://cipp.example.com"
Write-Host ($result2 | ConvertTo-Json -Depth 10)

# Test 3: License expiration alert
Write-Host "`n=== Test 3: License Expiration Alert ===" -ForegroundColor Cyan
$licenseAlert = @(
    [PSCustomObject]@{
        License              = "Microsoft 365 Business Premium"
        SkuId                = "cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46"
        DaysUntilRenew       = 15
        Term                 = "Monthly"
        TotalLicenses        = 50
        CountUsed            = 48
        CountAvailable       = 2
        Tenant               = "fabrikam.onmicrosoft.com"
    }
)
$result3 = ConvertTo-CIPPAlertSchema -AlertData $licenseAlert -AlertType "License" -Severity "Warning" -Tenant "fabrikam.onmicrosoft.com" -Source "Get-CIPPAlertExpiringLicenses" -Title "Licenses expiring soon" -CIPPURL "https://cipp.example.com"
Write-Host ($result3 | ConvertTo-Json -Depth 10)

# Test 4: Standards drift alert
Write-Host "`n=== Test 4: Standards Drift Alert ===" -ForegroundColor Cyan
$standardsAlerts = @(
    [PSCustomObject]@{
        standardName = "DisableBasicAuth"
        message      = "Basic authentication is still enabled"
        Tenant       = "northwind.onmicrosoft.com"
    },
    [PSCustomObject]@{
        standardName = "EnableMFA"
        message      = "Per-user MFA is not enforced for all users"
        Tenant       = "northwind.onmicrosoft.com"
    },
    [PSCustomObject]@{
        standardName = "AuditLog"
        message      = "Audit logging is not enabled"
        Tenant       = "northwind.onmicrosoft.com"
    }
)
$result4 = ConvertTo-CIPPAlertSchema -AlertData $standardsAlerts -AlertType "Standards" -Severity "Warning" -Tenant "northwind.onmicrosoft.com" -Source "StandardsDrift" -Title "Standards are out of sync for northwind.onmicrosoft.com" -CIPPURL "https://cipp.example.com"
Write-Host ($result4 | ConvertTo-Json -Depth 10)

# Test 5: Verify schema validation
Write-Host "`n=== Test 5: Schema Validation ===" -ForegroundColor Cyan
$result = ConvertTo-CIPPAlertSchema -AlertData "Test" -AlertType "General" -Severity "Info" -Tenant "test.com" -Source "Test"
$requiredFields = @('SchemaVersion', 'AlertVersion', 'Timestamp', 'PartitionKey', 'AlertId', 'AlertType', 'Source', 'Tenant', 'Title', 'Severity', 'Count', 'Summary', 'Data')
$allFieldsPresent = $true
foreach ($field in $requiredFields) {
    if (-not $result.PSObject.Properties[$field]) {
        Write-Host "Missing required field: $field" -ForegroundColor Red
        $allFieldsPresent = $false
    }
}
if ($allFieldsPresent) {
    Write-Host "✓ All required fields are present" -ForegroundColor Green
}

# Test 6: Verify data cleaning (Azure Table metadata removed)
Write-Host "`n=== Test 6: Data Cleaning ===" -ForegroundColor Cyan
$dirtyData = @(
    [PSCustomObject]@{
        Message      = "Test message"
        Tenant       = "test.com"
        ETag         = "W/datetime'2024-01-01T00%3A00%3A00.0000000Z'"
        PartitionKey = "20240101"
        RowKey       = "test-key"
        Timestamp    = "2024-01-01T00:00:00.000Z"
    }
)
$cleanResult = ConvertTo-CIPPAlertSchema -AlertData $dirtyData -AlertType "Test" -Severity "Info" -Tenant "test.com" -Source "Test"
$dataItem = $cleanResult.Data[0]
if ($dataItem.PSObject.Properties['ETag'] -or $dataItem.PSObject.Properties['PartitionKey'] -or $dataItem.PSObject.Properties['RowKey']) {
    Write-Host "✗ Azure Table metadata not properly removed" -ForegroundColor Red
} else {
    Write-Host "✓ Azure Table metadata properly removed from Data items" -ForegroundColor Green
}

Write-Host "`n=== All Tests Complete ===" -ForegroundColor Cyan
