function Add-CIPPAdminRoles {
    [CmdletBinding()]
    param(
        $AdminRoles,
        $TemplateId,
        $ApplicationId,
        $Tenantfilter
    )

    if (!$AdminRoles -and $TemplateId) {
        Write-Information "Adding admin roles for template $TemplateId"
        $TemplateTable = Get-CIPPTable -TableName 'templates'
        $Filter = "RowKey eq '$TemplateId' and PartitionKey eq 'AppApprovalTemplate'"
        $Template = (Get-CIPPAzDataTableEntity @TemplateTable -Filter $Filter).JSON | ConvertFrom-Json -ErrorAction SilentlyContinue
        $ApplicationId = $Template.AppId
        $AdminRoles = $Template.AdminRoles
    }

    # Return early if no admin roles to assign
    if (!$AdminRoles -or $AdminRoles.Count -eq 0) {
        Write-Information "No admin roles specified for application $ApplicationId"
        return @("No admin roles to assign")
    }

    Write-Information "Assigning admin roles to application $ApplicationId in tenant $Tenantfilter"

    $Results = [System.Collections.Generic.List[string]]::new()

    try {
        # Get the service principal for the application
        $ServicePrincipalList = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$filter=appId eq '$ApplicationId'&`$select=id,appId,displayName" -tenantid $Tenantfilter -NoAuthCheck $true
        $ServicePrincipal = $ServicePrincipalList | Where-Object -Property AppId -EQ $ApplicationId

        if (!$ServicePrincipal) {
            $Results.add("Service principal for application $ApplicationId not found in tenant $Tenantfilter")
            return $Results
        }

        Write-Information "Found service principal: $($ServicePrincipal.displayName) ($($ServicePrincipal.id))"

        # Get available directory roles in the tenant
        $DirectoryRoles = New-GraphGETRequest -uri "https://graph.microsoft.com/v1.0/directoryRoles" -tenantid $Tenantfilter -NoAuthCheck $true
        $DirectoryRoleTemplates = New-GraphGETRequest -uri "https://graph.microsoft.com/v1.0/directoryRoleTemplates" -tenantid $Tenantfilter -NoAuthCheck $true

        # Get current role assignments for the service principal
        $CurrentRoleAssignments = New-GraphGETRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($ServicePrincipal.id)/memberOf" -tenantid $Tenantfilter -NoAuthCheck $true

        $RoleAssignmentCount = 0

        foreach ($AdminRole in $AdminRoles) {
            try {
                $RoleId = $AdminRole.id
                $RoleName = $AdminRole.displayName

                Write-Information "Processing role: $RoleName ($RoleId)"

                # Check if service principal already has this role
                if ($CurrentRoleAssignments.id -contains $RoleId) {
                    $Results.Add("Service principal already has role: $RoleName")
                    continue
                }

                # Check if the directory role is activated in the tenant
                $DirectoryRole = $DirectoryRoles | Where-Object { $_.roleTemplateId -eq $RoleId -or $_.id -eq $RoleId }

                if (!$DirectoryRole) {
                    # Role is not activated, try to activate it using the role template
                    $RoleTemplate = $DirectoryRoleTemplates | Where-Object { $_.id -eq $RoleId }

                    if (!$RoleTemplate) {
                        $Results.Add("Role template not found for role: $RoleName ($RoleId)")
                        continue
                    }

                    Write-Information "Activating directory role: $RoleName"
                    $ActivationBody = @{
                        roleTemplateId = $RoleTemplate.id
                    } | ConvertTo-Json -Compress

                    try {
                        $DirectoryRole = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/directoryRoles" -tenantid $Tenantfilter -body $ActivationBody -NoAuthCheck $true
                        Write-Information "Successfully activated directory role: $RoleName"
                    } catch {
                        $ErrorMsg = Get-NormalizedError -message $_.Exception.Message
                        $Results.Add("Failed to activate directory role $RoleName`: $ErrorMsg")
                        continue
                    }
                }

                # Assign the role to the service principal
                Write-Information "Assigning role $RoleName to service principal"
                $AssignmentBody = @{
                    "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($ServicePrincipal.id)"
                } | ConvertTo-Json -Compress

                try {
                    $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/directoryRoles/$($DirectoryRole.id)/members/`$ref" -tenantid $Tenantfilter -body $AssignmentBody -NoAuthCheck $true
                    $Results.Add("Successfully assigned role: $RoleName")
                    $RoleAssignmentCount++
                    Write-Information "Successfully assigned role $RoleName to service principal"
                } catch {
                    $ErrorMsg = Get-NormalizedError -message $_.Exception.Message
                    if ($ErrorMsg -match "already exists" -or $ErrorMsg -match "already a member") {
                        $Results.Add("Service principal already has role: $RoleName")
                    } else {
                        $Results.Add("Failed to assign role $RoleName`: $ErrorMsg")
                    }
                }
            } catch {
                $ErrorMsg = Get-NormalizedError -message $_.Exception.Message
                $Results.Add("Error processing role $($AdminRole.displayName)`: $ErrorMsg")
            }
        }

        if ($RoleAssignmentCount -gt 0) {
            Write-LogMessage -message "Assigned $RoleAssignmentCount admin role(s) to $($ServicePrincipal.displayName)" -tenant $Tenantfilter -API 'Add Admin Roles' -sev Info
        }

    } catch {
        $ErrorMsg = Get-NormalizedError -message $_.Exception.Message
        $Results.Add("Failed to assign admin roles: $ErrorMsg")
        Write-LogMessage -message "Failed to assign admin roles to $ApplicationId`: $ErrorMsg" -tenant $Tenantfilter -API 'Add Admin Roles' -sev Error
    }

    "Added $RoleAssignmentCount admin role(s) to $($ServicePrincipal.displayName)"
    return $Results
}
