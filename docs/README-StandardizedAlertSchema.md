# Standardized Alert Schema

## Overview

CIPP includes a standardized JSON schema for webhook alerts, making it easier to process alerts in Power Automate, Logic Apps, and other automation platforms. This feature addresses the common challenge of inconsistent alert structures by providing a unified format across all alert types.

## Quick Start

### Enable in CIPP

1. Navigate to **Settings > Notifications**  
2. Enable **"Use Standardized Alert Schema"** checkbox (disabled by default for backward compatibility)
3. Configure your webhook URL
4. Save configuration

### Use in Power Automate

1. Add trigger: **"When a HTTP request is received"**
2. Add action: **"Parse JSON"** with the schema from `docs/PowerAutomate-Sample-Flow.json`
3. Add conditions to filter by `Severity` or `AlertType`
4. Add actions to send notifications

See [Quick Start Guide](docs/StandardizedAlertSchema-QuickStart.md) for detailed setup instructions.

## Schema Structure

All alerts follow this standardized format:

```json
{
  "SchemaVersion": "1.0",
  "AlertVersion": "1.0.0",
  "Timestamp": "2026-02-10T06:30:00.000Z",
  "AlertId": "unique-guid",
  "AlertType": "Security|License|Compliance|Health|Standards|Logbook",
  "Source": "Get-CIPPAlertMFAAdmins",
  "Tenant": "customer.onmicrosoft.com",
  "Title": "Alert Title",
  "Severity": "Info|Warning|Error|Critical|Alert",
  "Count": 2,
  "Summary": "Brief summary of the alert",
  "Data": [
    { /* alert-specific details */ }
  ]
}
```

## Key Benefits

- ✅ **Consistent Structure**: All alerts use the same top-level format
- ✅ **Easy Filtering**: Route by `AlertType`, `Severity`, or `Tenant`
- ✅ **Unique Identification**: Each alert has a unique `AlertId`
- ✅ **Better Integration**: Simplified Power Automate and Logic Apps flows
- ✅ **Backward Compatible**: Existing Teams/Slack/Discord webhooks unchanged
- ✅ **Configurable**: Enable/disable per installation

## Common Use Cases

### Route by Severity
```
Critical → Page on-call engineer
Warning  → Email team
Info     → Log only
```

### Route by Type
```
Security    → Security team
License     → Procurement team
Standards   → Compliance team
```

### Create Tickets
```
For each alert:
  Create ticket
  Set priority based on Severity
  Assign based on AlertType
```

## Documentation

- **[Quick Start Guide](docs/StandardizedAlertSchema-QuickStart.md)** - Get started in 5 minutes
- **[Full Schema Documentation](docs/StandardizedAlertSchema.md)** - Complete schema reference with examples
- **[Sample Power Automate Flow](docs/PowerAutomate-Sample-Flow.json)** - Import ready-to-use flow

## Testing

Test the schema implementation:

```powershell
cd /home/runner/work/CIPP-API/CIPP-API
pwsh -File Tests/Test-StandardizedAlertSchema.ps1
```

## Compatibility

- ✅ Generic webhooks: Use standardized schema  
- ✅ Power Automate: Fully supported
- ✅ Logic Apps: Fully supported
- ✅ Custom integrations: Consistent parsing
- ⚠️ Teams/Slack/Discord: Platform-specific formats (unchanged)

Platform-specific webhooks automatically use their optimized formats.

## Migration

For existing webhook consumers:

1. Review your current parsing logic
2. Update Parse JSON action with new schema
3. Update field references to access `Data` array
4. Test with sample alerts

See [Full Documentation](docs/StandardizedAlertSchema.md#migration-guide) for detailed migration steps.

## Feature Request

This feature was implemented in response to [GitHub Issue #3884](https://github.com/KelvinTegelaar/CIPP/issues/3884).

## Version

**Schema Version**: 1.0  
**Alert Version**: 1.0.0  
**Released**: 2026-02-10
