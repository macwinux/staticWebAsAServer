[CmdletBinding()]
param (
    [string] $clientName,
    [string] $apiName,
    [string] $resourceGroup,
    [string] $staticWebURL
)

az config set extension.use_dynamic_install=yes_without_prompt
az extension add --name authV2

# Create Client App
az login --service-principal -u $env:servicePrincipalId -p $env:servicePrincipalKey --tenant $env:tenantId

$clientApp=$(az ad app list --display-name "${clientName}-staticwebapp")
if ($clientApp -eq "[]") {
    $clientApp=$(az ad app create --display-name "${clientName}-staticwebapp" --web-redirect-uris $staticWebURL --enable-access-token-issuance true --enable-id-token-issuance true | ConvertFrom-Json)
} else {
    $clientApp=$($clientApp | ConvertFrom-Json)
}
$clientAppId=$clientApp.appId

# Create API App
$apiApp=$(az ad app list --display-name "${apiName}-app")
if ($apiApp -eq "[]") {
    $apiApp=$(az ad app create --display-name "${apiName}-app" --web-redirect-uris "https://${apiName}.azurewebsites.net/.auth/login/aad/callback" --identifier-uris "api://${apiName}" | ConvertFrom-Json)
} else {
    $apiApp = $($apiApp | ConvertFrom-Json)
}
$apiPermissionId=$([guid]::NewGuid())
$apiAppId=$apiApp.appId
$apiAppObjId=$apiApp.id
az rest -m PATCH --uri "https://graph.microsoft.com/v1.0/applications/$apiAppObjId" --headers 'Content-Type=application/json' --body "{ api: { oauth2PermissionScopes: [ { value: 'user_impersonation', adminConsentDescription: 'Allow the application to access ${apiName}-app on behalf of the signed-in user.', adminConsentDisplayName: 'Access fn-waastest2-dev-app', id: '$apiPermissionId', isEnabled: true, type: 'User' } ] } }"

Start-Sleep 40
Write-Host "PermissionID $apiPermissionId"
if (!$(az ad sp show --id $apiAppId)) {
    Write-Host "Creating Service principal"
    az ad sp create --id $apiAppId --only-show-errors
}



az ad app permission add --id $clientAppId --api $apiAppId --api-permissions "${apiPermissionId}=Scope"
az ad app permission add --id $apiAppId --api 00000003-0000-0000-c000-000000000000 --api-permissions "e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope"


# Allow client app above to access API as a trusted service
$secret=$(az ad app credential reset --id $apiApp.id --append --only-show-errors | ConvertFrom-Json)

$tenantDomainName=$clientApp.publisherDomain

$account=$(az account show | ConvertFrom-Json)
$tenantId=$account.tenantId

az webapp auth microsoft update -g $resourceGroup -n $apiName -y `
--allowed-audiences "api://${apiName}" `
--client-id $apiAppId `
--client-secret $secret.password  `
--issuer "https://sts.windows.net/${tenantId}/v2.0" -o none

az webapp auth update -g $resourceGroup -n $apiName --enabled true --action AllowAnonymous

Write-Host "##vso[task.setvariable variable=clientId;isoutput=true]$($clientAppId)"
Write-Host "##vso[task.setvariable variable=scope;isoutput=true]api://$($apiName)/user_impersonation"
Write-Host "##vso[task.setvariable variable=tenantDomainName;isoutput=true]https://login.microsoftonline.com/$($tenantDomainName)"

#echo "::set-output name=clientId::${clientAppId}"
#echo "::set-output name=scope::api://${apiName}/user_impersonation"
#echo "::set-output name=tenantDomainName::https://login.microsoftonline.com/${tenantDomainName}"