# CIPP Standardized Alert Schema

## Overview

CIPP now supports a standardized JSON schema for webhook alerts, making it easier to consume alerts in Power Automate, Logic Apps, and other webhook processors. This schema provides a consistent structure across all alert types while preserving alert-specific data.

## Schema Version

**Current Version:** 1.0  
**Alert Version:** 1.0.0

## Schema Structure

```json
{
  "SchemaVersion": "1.0",
  "AlertVersion": "1.0.0",
  "Timestamp": "2026-02-10T06:30:00.000Z",
  "PartitionKey": "20260210",
  "AlertId": "12345678-1234-1234-1234-123456789012",
  "AlertType": "Security",
  "Source": "Get-CIPPAlertMFAAdmins",
  "Tenant": "contoso.onmicrosoft.com",
  "TenantId": "87654321-4321-4321-4321-210987654321",
  "Title": "Admin MFA Alert",
  "Severity": "Warning",
  "Count": 3,
  "Summary": "3 alert(s) for contoso.onmicrosoft.com",
  "CIPPURL": "https://cipp.example.com",
  "Data": [
    {
      "Message": "Admin user John Doe (john.doe@contoso.com) does not have MFA registered.",
      "UserPrincipalName": "john.doe@contoso.com",
      "DisplayName": "John Doe",
      "Id": "user-guid-here",
      "LastUpdated": "2026-02-10T06:00:00Z",
      "Tenant": "contoso.onmicrosoft.com"
    }
  ]
}
```

## Field Descriptions

### Top-Level Metadata Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `SchemaVersion` | string | Yes | Version of the alert schema structure (currently "1.0") |
| `AlertVersion` | string | Yes | Version of the CIPP alert system (currently "1.0.0") |
| `Timestamp` | string | Yes | ISO 8601 UTC timestamp when the alert was generated |
| `PartitionKey` | string | Yes | Date-based partition key (YYYYMMDD format) |
| `AlertId` | string | Yes | Unique GUID for this specific alert |
| `AlertType` | string | Yes | Category of alert (e.g., "Security", "License", "Compliance", "Health", "Standards", "Logbook") |
| `Source` | string | Yes | Source function or system that generated the alert |
| `Tenant` | string | Yes | Tenant domain name (e.g., "contoso.onmicrosoft.com") |
| `TenantId` | string | No | Tenant GUID (optional, included when available) |
| `Title` | string | Yes | Human-readable title/subject of the alert |
| `Severity` | string | Yes | Alert severity level: "Info", "Warning", "Error", "Critical", or "Alert" |
| `Count` | integer | Yes | Number of items in the Data array |
| `Summary` | string | Yes | Brief summary of the alert content |
| `CIPPURL` | string | No | URL to the CIPP instance for deep links (optional) |
| `Data` | array | Yes | Array of alert-specific data objects |

### Data Array

The `Data` array contains one or more objects with alert-specific information. The structure of these objects varies based on the alert type but always excludes Azure Table Storage metadata fields (`ETag`, `PartitionKey`, `RowKey`, `Timestamp`).

## Alert Types

### Common Alert Types

- **Security** - User security alerts (MFA, passwords, risky users, admin changes)
- **License** - License expiration, assignment errors, usage alerts
- **Compliance** - Conditional access, security defaults, policy compliance
- **Health** - Service health, sync status, defender status
- **Standards** - Standards drift and out-of-sync configurations
- **Logbook** - General log-based alerts from the CIPP logbook

## Example Alert Scenarios

### Example 1: MFA Admin Alert (Security)

```json
{
  "SchemaVersion": "1.0",
  "AlertVersion": "1.0.0",
  "Timestamp": "2026-02-10T06:30:15.123Z",
  "PartitionKey": "20260210",
  "AlertId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "AlertType": "Security",
  "Source": "Get-CIPPAlertMFAAdmins",
  "Tenant": "contoso.onmicrosoft.com",
  "Title": "Admin users without MFA",
  "Severity": "Critical",
  "Count": 2,
  "Summary": "2 admin users do not have MFA registered",
  "CIPPURL": "https://cipp.example.com",
  "Data": [
    {
      "Message": "Admin user John Doe (john.doe@contoso.com) does not have MFA registered.",
      "UserPrincipalName": "john.doe@contoso.com",
      "DisplayName": "John Doe",
      "Id": "12345678-1234-1234-1234-123456789012",
      "LastUpdated": "2026-02-10T06:00:00Z",
      "Tenant": "contoso.onmicrosoft.com"
    },
    {
      "Message": "Admin user Jane Smith (jane.smith@contoso.com) does not have MFA registered.",
      "UserPrincipalName": "jane.smith@contoso.com",
      "DisplayName": "Jane Smith",
      "Id": "87654321-4321-4321-4321-210987654321",
      "LastUpdated": "2026-02-10T06:00:00Z",
      "Tenant": "contoso.onmicrosoft.com"
    }
  ]
}
```

### Example 2: License Expiration Alert

```json
{
  "SchemaVersion": "1.0",
  "AlertVersion": "1.0.0",
  "Timestamp": "2026-02-10T07:00:00.456Z",
  "PartitionKey": "20260210",
  "AlertId": "f1e2d3c4-b5a6-7890-fedc-ba0987654321",
  "AlertType": "License",
  "Source": "Get-CIPPAlertExpiringLicenses",
  "Tenant": "fabrikam.onmicrosoft.com",
  "Title": "Licenses expiring soon",
  "Severity": "Warning",
  "Count": 1,
  "Summary": "1 license expiring within 30 days",
  "CIPPURL": "https://cipp.example.com",
  "Data": [
    {
      "License": "Microsoft 365 Business Premium",
      "SkuId": "cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46",
      "DaysUntilRenew": 15,
      "Term": "Monthly",
      "TotalLicenses": 50,
      "CountUsed": 48,
      "CountAvailable": 2,
      "Tenant": "fabrikam.onmicrosoft.com"
    }
  ]
}
```

### Example 3: Standards Drift Alert

```json
{
  "SchemaVersion": "1.0",
  "AlertVersion": "1.0.0",
  "Timestamp": "2026-02-10T08:15:30.789Z",
  "PartitionKey": "20260210",
  "AlertId": "99887766-5544-3322-1100-ffeeddccbbaa",
  "AlertType": "Standards",
  "Source": "StandardsDrift",
  "Tenant": "northwind.onmicrosoft.com",
  "Title": "Standards are out of sync for northwind.onmicrosoft.com",
  "Severity": "Warning",
  "Count": 3,
  "Summary": "3 standards deviations detected",
  "CIPPURL": "https://cipp.example.com",
  "Data": [
    {
      "standardName": "DisableBasicAuth",
      "message": "Basic authentication is still enabled",
      "Tenant": "northwind.onmicrosoft.com"
    },
    {
      "standardName": "EnableMFA",
      "message": "Per-user MFA is not enforced for all users",
      "Tenant": "northwind.onmicrosoft.com"
    },
    {
      "standardName": "AuditLog",
      "message": "Audit logging is not enabled",
      "Tenant": "northwind.onmicrosoft.com"
    }
  ]
}
```

## Power Automate Integration

### Parsing the Alert

In Power Automate, use the "Parse JSON" action with this schema:

```json
{
  "type": "object",
  "properties": {
    "SchemaVersion": { "type": "string" },
    "AlertVersion": { "type": "string" },
    "Timestamp": { "type": "string" },
    "PartitionKey": { "type": "string" },
    "AlertId": { "type": "string" },
    "AlertType": { "type": "string" },
    "Source": { "type": "string" },
    "Tenant": { "type": "string" },
    "TenantId": { "type": "string" },
    "Title": { "type": "string" },
    "Severity": { "type": "string" },
    "Count": { "type": "integer" },
    "Summary": { "type": "string" },
    "CIPPURL": { "type": "string" },
    "Data": {
      "type": "array",
      "items": { "type": "object" }
    }
  },
  "required": [
    "SchemaVersion",
    "AlertVersion",
    "Timestamp",
    "PartitionKey",
    "AlertId",
    "AlertType",
    "Source",
    "Tenant",
    "Title",
    "Severity",
    "Count",
    "Summary",
    "Data"
  ]
}
```

### Example Power Automate Flow

1. **Trigger**: When a HTTP request is received (webhook URL)
2. **Parse JSON**: Parse the incoming webhook body using the schema above
3. **Condition**: Check if `Severity` equals "Critical" or "Error"
4. **Action**: Send an email/Teams message with:
   - Subject: `Title`
   - Content: `Summary`
   - Alert Type: `AlertType`
   - Tenant: `Tenant`
   - Details: Iterate through `Data` array

### Filtering by Alert Type

```
Condition: AlertType equals "Security"
Condition: AlertType equals "License"
Condition: AlertType equals "Standards"
```

### Filtering by Severity

```
Condition: Severity equals "Critical"
Condition: Severity in ["Critical", "Error"]
```

## Configuration

### Enabling Standardized Schema

The standardized schema is **disabled by default**. You can enable it in the CIPP notification settings.

To enable standardized schema:

1. Navigate to CIPP Settings > Notifications
2. Enable "Use Standardized Alert Schema" checkbox
3. Save configuration

### Legacy Compatibility

If you have existing Power Automate flows that depend on the old alert format:

1. The standardized schema is disabled by default, so existing flows continue to work
2. When ready to migrate, enable "Use Standardized Alert Schema" in Settings > Notifications
3. Update your flows to use the new schema
4. Test with sample alerts before enabling in production

The standardized schema is designed to be opt-in - webhook URLs for Teams, Slack, and Discord continue to work with their specific formats, while generic webhooks can use either the legacy format (default) or the standardized JSON (when enabled).

## Migration Guide

### For Existing Webhook Consumers

If you're currently consuming CIPP alerts via webhooks:

1. **Review your current parsing logic** - The new schema wraps alert data in a consistent structure
2. **Update your webhook receiver** - Parse the top-level fields first, then iterate through the `Data` array
3. **Test with sample alerts** - Use the examples above to test your updated logic
4. **Update filtering rules** - Use the new `AlertType` and `Severity` fields for routing

### Key Changes

- Alert data is now in a `Data` array instead of at the root level
- New metadata fields provide context (`AlertType`, `Severity`, `Source`)
- Consistent timestamp format (ISO 8601 UTC)
- Unique `AlertId` for tracking and deduplication
- Optional deep links via `CIPPURL`

## Troubleshooting

### Alert Not Using Standardized Schema

1. Check that `UseStandardizedSchema` is enabled in the notification configuration
2. Verify that you're sending to a generic webhook (not Teams/Slack/Discord)
3. Check CIPP logs for any errors during schema conversion

### Missing Fields

Some optional fields (`TenantId`, `CIPPURL`) may not be present in all alerts. Always check for field existence before accessing.

### Data Array Structure Varies

The structure of objects within the `Data` array will vary based on the alert type. This is expected and by design - the standardized schema provides consistent metadata while preserving alert-specific details.

## Version History

### Version 1.0 (2026-02-10)
- Initial release of standardized alert schema
- Support for all existing CIPP alert types
- Power Automate integration examples
- Backward compatibility with legacy webhook formats

## Support and Feedback

For issues, questions, or feature requests related to the standardized alert schema:

1. Check the CIPP documentation: https://docs.cipp.app
2. Open an issue on GitHub: https://github.com/KelvinTegelaar/CIPP/issues
3. Join the CIPP community discussions

## Related Resources

- [CIPP Alert Configuration Guide](https://docs.cipp.app/alerts)
- [Power Automate Webhook Documentation](https://learn.microsoft.com/en-us/power-automate/triggers-introduction)
- [Azure Logic Apps HTTP Trigger](https://learn.microsoft.com/en-us/azure/connectors/connectors-native-http)
