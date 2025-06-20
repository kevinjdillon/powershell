# Set user Principal  (Email address)
$userPrincipalName = "username@tenant.onmicrosoft.com"

# Get object ID of the user/service principal
$objectId = (Get-AzADUser -UserPrincipalName $userPrincipalName).Id

# Assign User Access Administrator role
New-AzRoleAssignment `
    -ObjectId $objectId `
    -RoleDefinitionName "User Access Administrator" `
    -Scope "/subscriptions/$((Get-AzContext).Subscription.Id)"
