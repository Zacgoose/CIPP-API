# Quick Notes for Frontend Team - Standardized Alert Schema

## Summary
Add a checkbox to the notification settings page for enabling/disabling the standardized alert schema feature.

## Required Changes

### 1. UI Control
**Add to**: Settings > Notifications page

**Control**: Checkbox (or toggle switch)
- Label: "Use Standardized Alert Schema"
- Default: `false` (unchecked)
- Help text: "Enable consistent JSON structure for webhook alerts (recommended for Power Automate)"

### 2. API Integration

**GET `/api/ListNotificationConfig`** - New field in response:
```json
{
  "UseStandardizedSchema": boolean  // defaults to false
}
```

**POST `/api/ExecNotificationConfig`** - New field in request:
```json
{
  "UseStandardizedSchema": boolean  // add this to the request body
}
```

### 3. Code Changes

**Load configuration**:
```javascript
UseStandardizedSchema: config.UseStandardizedSchema || false
```

**Save configuration**:
```javascript
{
  ...otherFields,
  UseStandardizedSchema: formData.UseStandardizedSchema || false
}
```

## Important Notes
- ✅ **Disabled by default** - backward compatible
- ✅ **Optional field** - if missing, defaults to `false`
- ✅ **Boolean type** - ensure proper boolean conversion
- ✅ **No breaking changes** - existing configs work without this field

## Visual Placement
Place checkbox below "Send to PSA Integration" and above "Severity Levels":

```
☐ One alert per tenant
☐ Send to PSA Integration  
☐ Use Standardized Alert Schema (NEW)
```

## Full Documentation
See `/docs/FRONTEND-IMPLEMENTATION-NOTES.md` for detailed implementation guide with code examples.
