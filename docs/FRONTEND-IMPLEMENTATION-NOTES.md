# Frontend Implementation Notes: Standardized Alert Schema Configuration

## Overview
A new configuration option has been added to the notification settings to enable/disable the standardized alert schema for webhooks.

## API Changes

### 1. GET Endpoint - List Notification Config
**Endpoint**: `GET /api/ListNotificationConfig`

**New Response Field**:
```json
{
  "email": "string",
  "webhook": "string",
  "onePerTenant": boolean,
  "sendtoIntegration": boolean,
  "Severity": ["Alert", "Error", "Info"],
  "logsToInclude": ["array", "of", "strings"],
  "UseStandardizedSchema": boolean,  // NEW FIELD - defaults to false if not set
  ...other fields
}
```

**Key Points**:
- The `UseStandardizedSchema` field is a **boolean** value
- It will be `false` (or `undefined`) by default for existing configurations
- It's **excluded** from the `logsToInclude` array (filtered out)

### 2. POST Endpoint - Execute Notification Config
**Endpoint**: `POST /api/ExecNotificationConfig`

**New Request Body Field**:
```json
{
  "email": "string",
  "webhook": "string",
  "onePerTenant": boolean,
  "sendtoIntegration": boolean,
  "Severity": [{"value": "Alert"}, {"value": "Error"}],
  "logsToInclude": [{"value": "string"}],
  "UseStandardizedSchema": boolean  // NEW FIELD - add this
}
```

**Key Points**:
- Add `UseStandardizedSchema` as a boolean field in the request body
- The backend will cast it to boolean: `[boolean]$Request.body.UseStandardizedSchema`
- If omitted, it will be treated as `false`

## UI Implementation Requirements

### 1. Add a Checkbox/Toggle Control

**Location**: Settings > Notifications page

**Control Details**:
- **Type**: Checkbox or Toggle Switch
- **Label**: "Use Standardized Alert Schema"
- **Default Value**: `false` (unchecked)
- **Description/Help Text**: 
  ```
  Enable standardized JSON schema for webhook alerts. This provides a consistent 
  structure across all alert types, making Power Automate and Logic Apps 
  integrations easier. Disabled by default for backward compatibility.
  ```

**Additional Help/Info Icon Text**:
```
When enabled, webhook alerts will use a standardized JSON schema with consistent 
metadata fields (AlertType, Severity, Source, AlertId) and a predictable structure.

Note: This only affects generic webhooks. Teams, Slack, and Discord webhooks 
continue to use their platform-specific formats.

Learn more: [Link to documentation]
```

### 2. Form Field Implementation Example

**React/TypeScript Example**:
```tsx
<FormControlLabel
  control={
    <Checkbox
      checked={formData.UseStandardizedSchema || false}
      onChange={(e) => setFormData({
        ...formData,
        UseStandardizedSchema: e.target.checked
      })}
    />
  }
  label="Use Standardized Alert Schema"
/>
<FormHelperText>
  Enable consistent JSON structure for webhook alerts (recommended for Power Automate)
</FormHelperText>
```

### 3. Form State Management

**Initial Load**:
```javascript
// When loading existing configuration
const loadConfig = async () => {
  const response = await fetch('/api/ListNotificationConfig');
  const config = await response.json();
  
  setFormData({
    email: config.email || '',
    webhook: config.webhook || '',
    onePerTenant: config.onePerTenant || false,
    sendtoIntegration: config.sendtoIntegration || false,
    Severity: config.Severity || [],
    logsToInclude: config.logsToInclude || [],
    UseStandardizedSchema: config.UseStandardizedSchema || false  // NEW: default to false
  });
};
```

**On Save**:
```javascript
// When saving configuration
const saveConfig = async () => {
  const payload = {
    email: formData.email,
    webhook: formData.webhook,
    onePerTenant: formData.onePerTenant,
    sendtoIntegration: formData.sendtoIntegration,
    Severity: formData.Severity.map(s => ({ value: s })),
    logsToInclude: formData.logsToInclude.map(l => ({ value: l })),
    UseStandardizedSchema: formData.UseStandardizedSchema || false  // NEW: ensure boolean
  };
  
  await fetch('/api/ExecNotificationConfig', {
    method: 'POST',
    body: JSON.stringify(payload)
  });
};
```

## Placement Recommendations

**Suggested UI Layout**:
```
┌─────────────────────────────────────────────────────┐
│ Notification Settings                                │
├─────────────────────────────────────────────────────┤
│                                                       │
│ Email: [________________________]                    │
│                                                       │
│ Webhook URL: [________________________]              │
│                                                       │
│ ☐ One alert per tenant                              │
│ ☐ Send to PSA Integration                           │
│ ☐ Use Standardized Alert Schema (NEW)       ⓘ      │
│                                                       │
│ Severity Levels: [Multi-select dropdown]            │
│                                                       │
│ Logs to Include: [Multi-select dropdown]            │
│                                                       │
│ [Save Configuration]                                 │
└─────────────────────────────────────────────────────┘
```

## Testing Checklist

- [ ] Checkbox appears on notification settings page
- [ ] Checkbox loads with correct default value (`false`)
- [ ] Checkbox state can be toggled
- [ ] Configuration saves successfully with `UseStandardizedSchema: true`
- [ ] Configuration saves successfully with `UseStandardizedSchema: false`
- [ ] Saved configuration loads correctly on page refresh
- [ ] Help text/tooltip displays correctly
- [ ] Form validation works (no errors from new field)
- [ ] Existing configurations without the field work correctly (backward compatible)

## Backward Compatibility Notes

- **Existing configurations**: If a configuration doesn't have the `UseStandardizedSchema` field, it will default to `false`
- **No breaking changes**: Existing webhook consumers continue to work without modifications
- **Opt-in feature**: Users must explicitly enable the standardized schema
- **No migration needed**: The feature is disabled by default

## Additional Resources

- **Schema Documentation**: `/docs/StandardizedAlertSchema.md`
- **Quick Start Guide**: `/docs/StandardizedAlertSchema-QuickStart.md`
- **Sample Power Automate Flow**: `/docs/PowerAutomate-Sample-Flow.json`

## Questions or Issues?

Contact the backend team if:
- The API response format doesn't match this documentation
- You need additional fields or validation
- You encounter unexpected behavior with the boolean field
- You need help with integration testing

## Example Payload (Complete)

**Full POST Request Example**:
```json
{
  "email": "alerts@company.com",
  "webhook": "https://webhook.site/unique-id",
  "onePerTenant": true,
  "sendtoIntegration": false,
  "UseStandardizedSchema": true,
  "Severity": [
    {"value": "Alert"},
    {"value": "Error"},
    {"value": "Critical"}
  ],
  "logsToInclude": [
    {"value": "Alerts"},
    {"value": "Standards"}
  ]
}
```

**Full GET Response Example**:
```json
{
  "email": "alerts@company.com",
  "webhook": "https://webhook.site/unique-id",
  "onePerTenant": true,
  "sendtoIntegration": false,
  "UseStandardizedSchema": true,
  "Severity": ["Alert", "Error", "Critical"],
  "logsToInclude": ["Alerts", "Standards"],
  "type": "CIPPNotifications",
  "schedule": "Every 15 minutes",
  "tenant": "Any",
  "tenantid": "TenantId",
  "includeTenantId": true,
  "PartitionKey": "CippNotifications",
  "RowKey": "CippNotifications"
}
```
