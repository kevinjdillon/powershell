..\..\FederalAVD\tools\New-TemplateSpecs.ps1 `
  -Location 'usgovarizona' `
  -createSharedServices $false `
  -createNetwork $false `
  -createImageManagement $false `
  -createCustomImage $false `
  -createHostPool $true `
  -createAutomatedHostPool $false `
  -CreateAddOns $false