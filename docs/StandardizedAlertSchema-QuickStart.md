# CIPP Standardized Alert Schema - Quick Start Guide

## What is it?

The standardized alert schema provides a consistent JSON structure for all CIPP webhook alerts, making it much easier to process alerts in Power Automate, Logic Apps, and other automation platforms.

## Before and After

### Before (Inconsistent)
Different alerts had different structures:
```json
// MFA Alert
[
  {
    "Message": "User has no MFA",
    "UserPrincipalName": "user@domain.com",
    "Tenant": "domain.com"
  }
]

// License Alert  
[
  {
    "License": "M365 E3",
    "DaysUntilRenew": 15,
    "Tenant": "domain.com"
  }
]
```

### After (Standardized)
All alerts follow the same top-level structure:
```json
{
  "SchemaVersion": "1.0",
  "AlertType": "Security",
  "Severity": "Critical",
  "Tenant": "domain.com",
  "Title": "MFA Alert",
  "Summary": "2 users without MFA",
  "Count": 2,
  "Data": [ /* alert details here */ ]
}
```

## Power Automate - 5 Minute Setup

### Step 1: Create Webhook Trigger

1. Create a new Flow
2. Add trigger: **"When a HTTP request is received"**
3. Generate URL after saving

### Step 2: Parse JSON

Add "Parse JSON" action with this schema:

```json
{
  "type": "object",
  "properties": {
    "SchemaVersion": { "type": "string" },
    "AlertType": { "type": "string" },
    "Severity": { "type": "string" },
    "Tenant": { "type": "string" },
    "Title": { "type": "string" },
    "Summary": { "type": "string" },
    "Count": { "type": "integer" },
    "Data": { "type": "array" }
  }
}
```

### Step 3: Add Conditions

Filter by severity:
```
Severity equals "Critical"
```

Or by alert type:
```
AlertType equals "Security"
```

### Step 4: Send Notification

Send to Teams, email, or ticketing system using:
- **Title**: `Title` field
- **Message**: `Summary` field  
- **Details**: Loop through `Data` array

## Common Use Cases

### Route by Severity
```
If Severity = "Critical" → Page on-call engineer
If Severity = "Warning" → Email team  
If Severity = "Info" → Log only
```

### Route by Type
```
If AlertType = "Security" → Security team
If AlertType = "License" → Procurement team
If AlertType = "Standards" → Compliance team
```

### Create Tickets
```
For each alert in Data array:
  Create ticket with alert details
  Set priority based on Severity
  Assign to team based on AlertType
```

## Configuration in CIPP

1. Go to **Settings > Notifications**
2. Enable **"Use Standardized Alert Schema"** checkbox
3. Save configuration

The setting is **disabled by default** to maintain backward compatibility with existing webhook consumers.

## Need Help?

- Full documentation: See `StandardizedAlertSchema.md`
- Test your setup: Use `Tests/Test-StandardizedAlertSchema.ps1`
- Examples: Check documentation for alert type examples

## Migration from Legacy Format

The standardized schema is **disabled by default**, so your existing flows continue to work without changes.

When you're ready to migrate:

1. **Update your Power Automate flows** to use the new schema (see Step 2 above)
2. **Test** with sample alerts in a test flow
3. **Enable** "Use Standardized Alert Schema" in CIPP Settings > Notifications
4. **Monitor** your flows to ensure they work correctly

## Key Fields

| Field | Use For |
|-------|---------|
| `AlertType` | Routing alerts to different teams |
| `Severity` | Priority and escalation |
| `Tenant` | Filtering by customer |
| `Title` | Notification subject |
| `Summary` | Quick overview |
| `Count` | Number of issues |
| `Data` | Detailed alert information |

## Schema Compatibility

- ✅ Generic webhooks: Use standardized schema
- ✅ Power Automate: Fully supported
- ✅ Logic Apps: Fully supported  
- ✅ Custom integrations: Consistent parsing
- ⚠️ Teams webhooks: Use Teams format (unchanged)
- ⚠️ Slack webhooks: Use Slack format (unchanged)
- ⚠️ Discord webhooks: Use Discord format (unchanged)

Platform-specific webhooks (Teams/Slack/Discord) continue to use their optimized formats automatically.
