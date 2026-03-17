# DoD PKI Automation Scripts

Comprehensive PowerShell automation for deploying and configuring a Department of Defense (DoD) PKI environment with Enterprise Root CA, certificate templates, NTAuth store configuration, and Group Policy-based auto-enrollment.

## Overview

This automation suite consists of modular PowerShell scripts that can be executed individually or orchestrated together for complete PKI deployment. The scripts are designed for Windows Server environments integrated with Active Directory.

## Architecture

The PKI deployment follows these sequential steps:

1. **Domain Join** - Join Windows Server to Active Directory domain
2. **Certificate Download** - Download and prepare DoD PKI certificates
3. **CA Installation** - Install and configure Enterprise Root CA
4. **Template Configuration** - Configure Domain Controller certificate templates
5. **NTAuth Installation** - Install DoD certificates to AD NTAuth store
6. **GPO Configuration** - Configure auto-enrollment via Group Policy

## Prerequisites

- Windows Server 2016 or later
- PowerShell 5.1 or higher
- Administrator privileges
- Active Directory domain environment
- Enterprise Admin or Domain Admin credentials
- Internet connectivity (for DoD certificate download)

## Scripts

### Individual Scripts

#### 1-Join-Domain.ps1
Joins a Windows Server to an Active Directory domain.

**Parameters:**
- `DomainName` (Required) - FQDN of the domain to join
- `Credential` (Optional) - Domain credentials
- `NewComputerName` (Optional) - Rename computer during join
- `OUPath` (Optional) - Target OU for computer account
- `Restart` (Optional) - Auto-restart after join (default: true)

**Example:**
```powershell
.\1-Join-Domain.ps1 -DomainName "contoso.com"
```

#### 2-Download-PrepDoDCerts.ps1
Downloads DoD certificate bundle and extracts certificates.

**Parameters:**
- `DownloadUrl` (Optional) - URL for DoD certificate bundle
- `OutputPath` (Optional) - Download destination (default: C:\PKI-Certificates)
- `Force` (Optional) - Overwrite existing files

**Example:**
```powershell
.\2-Download-PrepDoDCerts.ps1 -OutputPath "D:\Certificates"
```

#### 3-Install-EnterpriseRootCA.ps1
Installs and configures Enterprise Root CA.

**Parameters:**
- `CACommonName` (Optional) - CA name (default: "Enterprise Root CA")
- `CADistinguishedNameSuffix` (Optional) - DN suffix (auto-detected)
- `ValidityPeriod` (Optional) - Period type (default: Years)
- `ValidityPeriodUnits` (Optional) - Period length (default: 20)
- `KeyLength` (Optional) - Key size in bits (default: 4096)
- `HashAlgorithm` (Optional) - Hash algorithm (default: SHA256)

**Example:**
```powershell
.\3-Install-EnterpriseRootCA.ps1 -CACommonName "DoD Root CA" -ValidityPeriodUnits 25
```

#### 4-Configure-DCCertTemplate.ps1
Configures Domain Controller certificate template for auto-enrollment.

**Parameters:**
- `TemplateName` (Optional) - Template display name
- `UseExistingTemplate` (Optional) - Use existing DC template
- `ValidityPeriod` (Optional) - Certificate validity in years (default: 2)
- `RenewalPeriod` (Optional) - Renewal period in weeks (default: 6)

**Example:**
```powershell
.\4-Configure-DCCertTemplate.ps1 -UseExistingTemplate
```

#### 5-Install-DoDNTAuthCerts.ps1
Installs DoD certificates to NTAuth store for smart card authentication.

**Parameters:**
- `CertificatePath` (Optional) - Certificate directory (default: C:\PKI-Certificates)
- `InstallRootCerts` (Optional) - Install root CAs (default: true)
- `InstallIntermediateCerts` (Optional) - Install intermediate CAs (default: true)
- `AlsoInstallToTrustedRoot` (Optional) - Install to local stores (default: true)

**Example:**
```powershell
.\5-Install-DoDNTAuthCerts.ps1 -CertificatePath "C:\PKI-Certificates"
```

#### 6-Configure-AutoEnrollment-GPO.ps1
Configures certificate auto-enrollment and trusted CA distribution via GPO.

**Parameters:**
- `GPONameAutoEnroll` (Optional) - Auto-enrollment GPO name
- `GPONameTrustedCAs` (Optional) - Trusted CA GPO name
- `LinkToRoot` (Optional) - Link to domain root (default: true)
- `LinkToDomainControllers` (Optional) - Link to DC OU (default: true)
- `EnableForComputers` (Optional) - Enable for computers (default: true)
- `EnableForUsers` (Optional) - Enable for users (default: false)

**Example:**
```powershell
.\6-Configure-AutoEnrollment-GPO.ps1 -EnableForUsers $true
```

### Master Orchestration Script

#### Deploy-PKI-Complete.ps1
Orchestrates complete PKI deployment by executing all scripts in sequence.

**Parameters:**
- `DomainName` (Optional) - Domain FQDN
- `DomainCredential` (Optional) - Domain credentials
- `NewComputerName` (Optional) - Rename CA server
- `CACommonName` (Optional) - CA name (default: "Enterprise Root CA")
- `CertificatePath` (Optional) - Certificate storage path
- `SkipDomainJoin` (Optional) - Skip domain join step
- `SkipCertDownload` (Optional) - Skip certificate download
- `SkipCAInstall` (Optional) - Skip CA installation

**Example:**
```powershell
# Full deployment
.\Deploy-PKI-Complete.ps1 -DomainName "contoso.com"

# With credential and custom CA name
$cred = Get-Credential
.\Deploy-PKI-Complete.ps1 -DomainName "contoso.com" -DomainCredential $cred -CACommonName "DoD Enterprise CA"

# Skip already completed steps
.\Deploy-PKI-Complete.ps1 -DomainName "contoso.com" -SkipDomainJoin -SkipCertDownload
```

## Deployment Workflow

### Option 1: Complete Automated Deployment

```powershell
# Navigate to script directory
cd C:\Git\powershell\PKI-Automation

# Run complete deployment
.\Deploy-PKI-Complete.ps1 -DomainName "yourdomain.com"
```

The orchestration script will:
1. Prompt for credentials if not provided
2. Execute each step in sequence
3. Handle errors and dependencies
4. Provide detailed progress output
5. Generate deployment summary

### Option 2: Step-by-Step Manual Execution

For testing or troubleshooting, run scripts individually:

```powershell
# Step 1: Join domain
.\1-Join-Domain.ps1 -DomainName "contoso.com"
# (Computer will restart)

# Step 2: Download certificates
.\2-Download-PrepDoDCerts.ps1

# Step 3: Install CA
.\3-Install-EnterpriseRootCA.ps1

# Step 4: Configure template
.\4-Configure-DCCertTemplate.ps1 -UseExistingTemplate

# Step 5: Install to NTAuth
.\5-Install-DoDNTAuthCerts.ps1

# Step 6: Configure GPO
.\6-Configure-AutoEnrollment-GPO.ps1
```

## Verification and Testing

### Verify CA Installation
```powershell
# Check CA service
Get-Service CertSvc

# View CA configuration
certutil -cainfo

# List published templates
certutil -CATemplates
```

### Verify Certificate Templates
```powershell
# View template permissions
certutil -v -template DomainController

# Check template publication
Get-CATemplate | Where-Object { $_.Name -like "*Domain*" }
```

### Verify NTAuth Store
```powershell
# View NTAuth certificates
certutil -viewstore -enterprise NTAuth

# List certificates
certutil -enterprise -store NTAuth
```

### Verify Group Policy
```powershell
# Force GP update
gpupdate /force

# View applied policies
gpresult /h gpresult.html

# Check auto-enrollment settings
Get-GPRegistryValue -Name "PKI - Certificate Auto-Enrollment" -Key "HKLM\SOFTWARE\Policies\Microsoft\Cryptography\AutoEnrollment"
```

### Test Certificate Enrollment
```powershell
# Force certificate enrollment
certutil -pulse

# View computer certificates
Get-ChildItem Cert:\LocalMachine\My

# Check certificate validity
Get-ChildItem Cert:\LocalMachine\My | Format-List Subject, Thumbprint, NotAfter
```

## Troubleshooting

### Common Issues

**Issue: Domain join fails**
- Verify DNS configuration points to domain controller
- Ensure credentials have permissions to join computers
- Check network connectivity to domain

**Issue: Certificate download fails**
- Verify internet connectivity
- Check proxy settings if behind firewall
- Ensure TLS 1.2 is enabled

**Issue: CA installation fails**
- Verify computer is domain-joined
- Ensure running as Enterprise Admin or Domain Admin
- Check Windows Server role installation permissions

**Issue: Auto-enrollment not working**
- Force GP update: `gpupdate /force`
- Check Event Viewer > Application log for errors
- Verify certificate template permissions
- Ensure CA service is running

### Logging and Diagnostics

View detailed help for any script:
```powershell
Get-Help .\<script-name>.ps1 -Full
Get-Help .\<script-name>.ps1 -Examples
```

Check Windows Event Logs:
```powershell
# Certificate Services events
Get-EventLog -LogName Application -Source "Microsoft-Windows-CertificationAuthority" -Newest 50

# Auto-enrollment events
Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Microsoft-Windows-CertificateServicesClient-AutoEnrollment'}
```

## Security Considerations

- All scripts require Administrator privileges
- Domain credentials should be handled securely
- Scripts support `PSCredential` objects for secure credential passing
- Consider running in isolated test environment first
- Review and customize scripts for your specific security requirements

## DoD-Specific Notes

- Scripts download DoD PKI certificates from official cyber.mil source
- Certificates are separated into Root and Intermediate categories
- NTAuth store installation enables DoD CAC/PIV card authentication
- Certificate validity and key lengths align with DoD standards
- Templates can be customized for additional DoD requirements

## Advanced Configuration

### Custom Certificate Templates

To create custom templates beyond Domain Controller:

1. Use Certificate Templates MMC snap-in (`certtmpl.msc`)
2. Duplicate existing template
3. Configure permissions and settings
4. Publish to CA using: `certutil -SetCATemplates +TemplateName`

### Multi-CA Environments

For subordinate CA deployment:
- Modify script 3 to use `EnterpriseSubordinateCA` type
- Provide parent CA certificate
- Configure appropriate CRL/AIA locations

### Custom CRL/OCSP Configuration

Scripts configure default HTTP-based CRL distribution. For custom OCSP:
- Configure OCSP responder role
- Update AIA extensions in CA properties
- Modify script 3's AIA/CDP configuration sections

## Support and Contributions

These scripts are provided as-is for DoD PKI automation. 

For issues or enhancements:
- Review script help documentation
- Check Windows Event Logs
- Verify prerequisites and permissions
- Test in isolated environment first

## License

These scripts follow standard open-source licensing practices. Modify and use according to your organization's requirements.

## Version History

- v1.0 - Initial release with complete PKI automation suite
  - Domain join automation
  - DoD certificate download and preparation
  - Enterprise Root CA installation
  - Certificate template configuration
  - NTAuth store setup
  - Group Policy auto-enrollment
  - Master orchestration script

## Related Documentation

- [Microsoft PKI Documentation](https://docs.microsoft.com/en-us/windows-server/networking/core-network-guide/cncg/server-certs/server-certificate-deployment)
- [DoD PKI/PKE Document Library](https://public.cyber.mil/pki-pke/tools-configuration-files/)
- [Certificate Template Management](https://docs.microsoft.com/en-us/windows-server/networking/core-network-guide/cncg/server-certs/configure-certificate-templates)
- [Group Policy Auto-Enrollment](https://docs.microsoft.com/en-us/windows-server/networking/core-network-guide/cncg/server-certs/configure-server-certificate-autoenrollment)
