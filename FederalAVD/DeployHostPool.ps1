New-AzSubscriptionDeployment `
  -Location "usgovarizona" `
  -TemplateFile "..\..\FederalAVD\deployments\hostpools\hostpool.json" `
  -TemplateParameterFile "..\..\FederalAVD\customer\parameters\hostpools\gpu-opt.parameters.json" `
  -Name "avd-hostpool-gpu-opt-$(Get-Date -Format 'yyyyMMddHHmm')"