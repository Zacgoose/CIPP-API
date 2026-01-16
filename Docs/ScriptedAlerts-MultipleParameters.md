# Scripted Alerts: Multiple Input Parameters

## Overview

Scripted alerts (scheduled alert tasks) now support passing multiple input parameters directly to alert functions, instead of having to nest all configuration values within a single `input` object.

## Background

Previously, alert functions only accepted two parameters:
- `$InputValue` (with alias `input`) - A single object containing all configuration
- `$TenantFilter` - The tenant to run the alert against

This meant all configuration had to be passed as properties of one object.

## New Capability

Alert functions now accept **multiple direct parameters**, allowing you to pass configuration values individually.

## Benefits

1. **Clearer structure** - Each configuration option is a top-level parameter
2. **Easier to understand** - No need to nest everything in an `input` object
3. **More flexible** - Can pass parameters individually or combined
4. **Better type safety** - Parameters have explicit types
5. **Full backward compatibility** - Existing alerts continue to work

## Supported Alert Functions

### Get-CIPPAlertExpiringLicenses
- `ExpiringLicensesDays` (int) - Days before expiration to alert (default: 30)
- `ExpiringLicensesUnassignedOnly` (bool) - Only alert for unassigned licenses (default: false)

### Get-CIPPAlertSharepointQuota
- `PercentageThreshold` (int) - Percentage of quota used to trigger alert (default: 90)

### Get-CIPPAlertQuotaUsed
- `PercentageThreshold` (int) - Percentage of mailbox quota used to trigger alert (default: 90)

### Get-CIPPAlertEntraConnectSyncStatus
- `Hours` (int) - Hours without sync to trigger alert (default: 72)

### Get-CIPPAlertHuntressRogueApps
- `IgnoreDisabledApps` (bool) - Whether to ignore disabled rogue apps (default: false)

### Get-CIPPAlertIntunePolicyConflicts
- `AlertEachIssue` (bool) - Alert for each issue individually vs aggregated (default: false)
- `IncludePolicies` (bool) - Include policy conflicts (default: true)
- `IncludeApplications` (bool) - Include application conflicts (default: true)
- `AlertConflicts` (bool) - Alert on conflicts (default: true)
- `AlertErrors` (bool) - Alert on errors (default: true)

## Parameter Priority

When both direct parameters and `InputValue` properties are present, **direct parameters take priority**.

## For Alert Function Authors

To add direct parameter support:

1. Add explicit parameters for each configuration option
2. Check for direct parameters first using `$PSBoundParameters.ContainsKey()`
3. Fall back to `InputValue` properties
4. Keep `[Alias('input')]` on `$InputValue` for backward compatibility
