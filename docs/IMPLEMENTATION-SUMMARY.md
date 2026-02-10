# Implementation Summary: Standardized Alert Schema for CIPP

## Problem Statement

From [GitHub Issue #3884](https://github.com/KelvinTegelaar/CIPP/issues/3884):

> Currently most of the alerts that are sent to a webhook use different schemas. A unified json schema format would simplify PowerAutomate usage for webhook alerting.

## Solution Implemented

Created a standardized JSON schema for all CIPP alerts, inspired by the `Write-LogMessage` function pattern. The solution provides a consistent structure while preserving alert-specific data.

## Technical Implementation

### 1. Core Function: `ConvertTo-CIPPAlertSchema`

**Location**: `Modules/CIPPCore/Public/GraphHelper/ConvertTo-CIPPAlertSchema.ps1`

**Purpose**: Converts any alert data to the standardized schema format

**Features**:
- Consistent metadata structure
- Removes Azure Table Storage fields (ETag, PartitionKey, RowKey, Timestamp)
- Supports optional fields (TenantId, CIPPURL)
- Handles arrays and single objects
- Converts strings to proper message objects

**Example Usage**:
```powershell
$standardized = ConvertTo-CIPPAlertSchema `
    -AlertData $alertData `
    -AlertType "Security" `
    -Severity "Critical" `
    -Tenant "contoso.onmicrosoft.com" `
    -Source "Get-CIPPAlertMFAAdmins" `
    -Title "Admin users without MFA"
```

### 2. Updated Function: `Send-CIPPAlert`

**Location**: `Modules/CIPPCore/Public/Send-CIPPAlert.ps1`

**Changes**:
- Added `-UseStandardizedSchema` switch parameter
- Added metadata parameters (AlertType, Severity, Source, TenantId, CIPPURL)
- Applies standardized schema before sending to generic webhooks
- Maintains backward compatibility with Teams/Slack/Discord

**Behavior**:
- When `UseStandardizedSchema` is enabled:
  - Generic webhooks receive standardized JSON
  - Teams/Slack/Discord still get platform-specific formats
- When disabled:
  - Original behavior preserved

### 3. Updated Function: `Push-SchedulerCIPPNotifications`

**Location**: `Modules/CIPPCore/Public/Entrypoints/Activity Triggers/Push-SchedulerCIPPNotifications.ps1`

**Changes**:
- Uses standardized schema by default (configurable)
- Groups alerts by tenant when standardizing
- Determines severity from alert data
- Falls back to legacy format if disabled

**Configuration**:
- Enabled by default for new installations
- Existing installations can opt-in via `UseStandardizedSchema` setting

## Schema Structure

### Top-Level Fields

| Field | Type | Description |
|-------|------|-------------|
| SchemaVersion | string | Schema structure version ("1.0") |
| AlertVersion | string | CIPP alert system version ("1.0.0") |
| Timestamp | string | ISO 8601 UTC timestamp |
| PartitionKey | string | Date-based key (YYYYMMDD) |
| AlertId | string | Unique GUID for this alert |
| AlertType | string | Category (Security, License, etc.) |
| Source | string | Originating function/system |
| Tenant | string | Tenant domain name |
| TenantId | string | Tenant GUID (optional) |
| Title | string | Human-readable title |
| Severity | string | Info, Warning, Error, Critical, Alert |
| Count | integer | Number of items in Data array |
| Summary | string | Brief description |
| CIPPURL | string | Deep link to CIPP (optional) |
| Data | array | Alert-specific data objects |

### Example Output

```json
{
  "SchemaVersion": "1.0",
  "AlertVersion": "1.0.0",
  "Timestamp": "2026-02-10T06:23:47.901Z",
  "PartitionKey": "20260210",
  "AlertId": "7d34480f-dccb-4115-9afb-c367df90b20c",
  "AlertType": "Security",
  "Source": "Get-CIPPAlertMFAAdmins",
  "Tenant": "contoso.onmicrosoft.com",
  "Title": "Admin users without MFA",
  "Severity": "Critical",
  "Count": 1,
  "Summary": "Admin user john.doe@contoso.com does not have MFA registered.",
  "Data": [
    {
      "Message": "Admin user john.doe@contoso.com does not have MFA registered.",
      "UserPrincipalName": "john.doe@contoso.com",
      "DisplayName": "John Doe",
      "Tenant": "contoso.onmicrosoft.com"
    }
  ]
}
```

## Benefits

1. **Consistency**: All alerts follow the same top-level structure
2. **Filterability**: Easy to route by AlertType, Severity, or Tenant
3. **Identification**: Unique AlertId for tracking and deduplication
4. **Integration**: Simplified Power Automate and Logic Apps flows
5. **Compatibility**: Backward compatible with existing webhooks
6. **Configurability**: Can be enabled/disabled per installation

## Documentation Provided

1. **StandardizedAlertSchema.md** (11 KB)
   - Complete schema specification
   - Field descriptions
   - Multiple alert type examples
   - Power Automate integration guide
   - Migration guide
   - Troubleshooting

2. **StandardizedAlertSchema-QuickStart.md** (4 KB)
   - 5-minute setup guide
   - Before/after comparisons
   - Common use cases
   - Configuration steps

3. **README-StandardizedAlertSchema.md** (4 KB)
   - Overview section for main README
   - Benefits and compatibility
   - Links to detailed documentation

4. **PowerAutomate-Sample-Flow.json** (7 KB)
   - Ready-to-import flow
   - Demonstrates parsing
   - Routes by severity
   - Sends to email/Teams

## Testing

### Test Suite: `Tests/Test-StandardizedAlertSchema.ps1`

**Coverage**:
- ✅ Simple string alerts
- ✅ Complex object arrays (MFA alerts)
- ✅ License expiration alerts
- ✅ Standards drift alerts
- ✅ Required field validation
- ✅ Azure Table metadata removal

**Results**: All tests passing

### Manual Testing

Verified with PowerShell:
```powershell
Import-Module ./Modules/CIPPCore/CIPPCore.psd1 -Force
$alert = ConvertTo-CIPPAlertSchema -AlertData "Test" -AlertType "Test" -Severity "Info" -Tenant "test.com" -Source "Test"
$alert | ConvertTo-Json
```

## Integration Examples

### Power Automate Flow

1. Trigger: When HTTP request received
2. Parse JSON with standardized schema
3. Condition on Severity:
   - Critical → Email on-call
   - Error → Email team
   - Warning → Post to Teams
   - Info → Log only

### Logic Apps

Similar to Power Automate, using HTTP trigger and Parse JSON action

### Custom Webhook Consumer

```javascript
// Parse webhook payload
const alert = JSON.parse(webhookBody);

// Route based on metadata
if (alert.Severity === 'Critical') {
    pageOnCall(alert.Title, alert.Summary);
} else if (alert.AlertType === 'Security') {
    notifySecurityTeam(alert);
}

// Process alert details
alert.Data.forEach(item => {
    createTicket(item);
});
```

## Configuration

### Enable Standardized Schema

**In CIPP UI**:
1. Navigate to Settings > Notifications
2. Enable "Use Standardized Alert Schema" checkbox
3. Save configuration

**In Configuration Table**:
- Table: `SchedulerConfig`
- PartitionKey: `CippNotifications`
- RowKey: `CippNotifications`
- Property: `UseStandardizedSchema` = `true`

**Default**: Disabled (false) for backward compatibility with existing webhook consumers

### Disable (Legacy Mode)

Set `UseStandardizedSchema` to `false` in configuration

## Backward Compatibility

### Preserved Behaviors

- ✅ Teams webhook format unchanged
- ✅ Slack webhook format unchanged
- ✅ Discord webhook format unchanged
- ✅ Email alerts unchanged
- ✅ PSA integration unchanged

### Changed Behaviors

- ⚠️ Generic webhooks now receive standardized JSON (when enabled)
- ⚠️ Alerts grouped by tenant (when enabled)

### Migration Path

**Option 1: Gradual**
1. Keep `UseStandardizedSchema = false`
2. Update webhook consumers
3. Test with sample alerts
4. Enable standardized schema

**Option 2: Immediate**
1. Enable standardized schema
2. Update webhook consumers simultaneously
3. Test and iterate

## Files Added/Modified

### New Files (5)
1. `Modules/CIPPCore/Public/GraphHelper/ConvertTo-CIPPAlertSchema.ps1`
2. `Tests/Test-StandardizedAlertSchema.ps1`
3. `docs/StandardizedAlertSchema.md`
4. `docs/StandardizedAlertSchema-QuickStart.md`
5. `docs/README-StandardizedAlertSchema.md`
6. `docs/PowerAutomate-Sample-Flow.json`

### Modified Files (2)
1. `Modules/CIPPCore/Public/Send-CIPPAlert.ps1`
2. `Modules/CIPPCore/Public/Entrypoints/Activity Triggers/Push-SchedulerCIPPNotifications.ps1`

## Future Enhancements

Potential future additions:
1. Alert categories/tags for more granular routing
2. Custom field mapping configuration
3. Schema versioning support for evolution
4. Alert aggregation by type/tenant
5. Rate limiting and batching options

## References

- **Issue**: [#3884](https://github.com/KelvinTegelaar/CIPP/issues/3884)
- **Inspiration**: `Write-LogMessage` function pattern
- **Schema Version**: 1.0
- **Implementation Date**: 2026-02-10

## Credits

Implemented based on community feedback and MSP requirements for simplified webhook integration with Power Automate and other automation platforms.
