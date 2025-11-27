$location = "northeurope"
$resourceGroupName = "mate-azure-task-13"
$networkSecurityGroupName = "defaultnsg"
$virtualNetworkName = "vnet"
$subnetName = "default"
$vnetAddressPrefix = "10.0.0.0/16"
$subnetAddressPrefix = "10.0.0.0/24"
$sshKeyName = "linuxboxsshkey"
$sshKeyPublicKey = Get-Content "~/.ssh/id_rsa.pub"
$publicIpAddressName = "linuxboxpip"
$vmName = "matebox"
$vmImage = "Ubuntu2204"
$vmSize = "Standard_B1s"
$dnsLabel = "matetask" + (Get-Random -Count 1)

Write-Host "Creating a resource group $resourceGroupName ..."
New-AzResourceGroup -Name $resourceGroupName -Location $location -Force

Write-Host "Creating a network security group $networkSecurityGroupName ..."
$nsgRuleSSH = New-AzNetworkSecurityRuleConfig `
    -Name SSH `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 1001 `
    -SourceAddressPrefix * `
    -SourcePortRange * `
    -DestinationAddressPrefix * `
    -DestinationPortRange 22 `
    -Access Allow

$nsgRuleHTTP = New-AzNetworkSecurityRuleConfig `
    -Name HTTP `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 1002 `
    -SourceAddressPrefix * `
    -SourcePortRange * `
    -DestinationAddressPrefix * `
    -DestinationPortRange 8080 `
    -Access Allow

New-AzNetworkSecurityGroup `
    -Name $networkSecurityGroupName `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -SecurityRules $nsgRuleSSH, $nsgRuleHTTP `
    -Force

Write-Host "Creating a virtual network ..."
$subnet = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetAddressPrefix

New-AzVirtualNetwork `
    -Name $virtualNetworkName `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -AddressPrefix $vnetAddressPrefix `
    -Subnet $subnet `
    -Force

Write-Host "Creating a SSH key ..."
$existingSshKey = Get-AzSshKey -ResourceGroupName $resourceGroupName -Name $sshKeyName -ErrorAction SilentlyContinue
if (-not $existingSshKey) {
    New-AzSshKey `
        -Name $sshKeyName `
        -ResourceGroupName $resourceGroupName `
        -PublicKey $sshKeyPublicKey
}
else {
    Write-Host "SSH key $sshKeyName already exists in $resourceGroupName, skipping creation."
}

Write-Host "Creating a Public IP Address ..."
New-AzPublicIpAddress `
    -Name $publicIpAddressName `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -Sku Standard `
    -AllocationMethod Static `
    -DomainNameLabel $dnsLabel `
    -Force

Write-Host "Creating a VM ..."
New-AzVm `
    -ResourceGroupName $resourceGroupName `
    -Name $vmName `
    -Location $location `
    -Image $vmImage `
    -Size $vmSize `
    -SubnetName $subnetName `
    -VirtualNetworkName $virtualNetworkName `
    -SecurityGroupName $networkSecurityGroupName `
    -SshKeyName $sshKeyName `
    -PublicIpAddressName $publicIpAddressName

Write-Host "Checking if VM was created..."
$vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -ErrorAction SilentlyContinue

if (-not $vm) {
    Write-Host "VM $vmName was not created. Exiting script." -ForegroundColor Red
    return
}

Write-Host "Enabling system-assigned managed identity on the VM..."
Update-AzVM `
    -VM $vm `
    -ResourceGroupName $resourceGroupName `
    -IdentityType SystemAssigned

Write-Host "System-assigned managed identity enabled."

Write-Host "Installing the TODO web app..."
$Params = @{
    ResourceGroupName  = $resourceGroupName
    VMName             = $vmName
    Name               = 'CustomScript'
    Publisher          = 'Microsoft.Azure.Extensions'
    ExtensionType      = 'CustomScript'
    TypeHandlerVersion = '2.1'
    Settings           = @{
        fileUris         = @(
            'https://raw.githubusercontent.com/mate-academy/azure_task_13_vm_monitoring/main/install-app.sh'
        )
        commandToExecute = './install-app.sh'
    }
}
Set-AzVMExtension @Params

Write-Host "Installing Azure Monitor Agent extension..." -ForegroundColor Cyan

$AmaParams = @{
    ResourceGroupName  = $resourceGroupName
    VMName             = $vmName
    Name               = 'AzureMonitorLinuxAgent'
    Publisher          = 'Microsoft.Azure.Monitor'
    ExtensionType      = 'AzureMonitorLinuxAgent'
    TypeHandlerVersion = '1.0'
    Location           = $location
    Settings           = @{}
}

Set-AzVMExtension @AmaParams

Write-Host "Azure Monitor Agent extension installed." -ForegroundColor Green
