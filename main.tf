# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.65"
    }
  }

  required_version = ">= 0.14.9"
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg-robin" {
  name     = "rg-robin"
  location = "westeurope"
}
# Create virtual network
resource "azurerm_virtual_network" "robin-network" {
    name                = "robin-network"
    address_space       = ["10.0.0.0/16"]
    location            = "westeurope"
    resource_group_name = azurerm_resource_group.rg-robin.name

    tags = {
        environment = "robin-network"
    }
}

# Create subnet
resource "azurerm_subnet" "robin-subnet" {
    name                 = "robin-subnet"
    resource_group_name  = azurerm_resource_group.rg-robin.name
    virtual_network_name = azurerm_virtual_network.robin-network.name
    address_prefixes       = ["10.0.1.0/24"]
}

# Create public IPs
resource "azurerm_public_ip" "robin-ip" {
    name                         = "robin-ip"
    location                     = "westeurope"
    resource_group_name          = azurerm_resource_group.rg-robin.name
    allocation_method            = "Dynamic"

    tags = {
        environment = "robin-ip"
    }
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "robin-nsg" {
    name                = "robin-nsg"
    location            = "westeurope"
    resource_group_name = azurerm_resource_group.rg-robin.name

    security_rule {
        name                       = "SSH"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    tags = {
        environment = "robin-nsg"
    }
}

# Create network interface
resource "azurerm_network_interface" "robin-ic" {
    name                      = "robin-ic"
    location                  = "westeurope"
    resource_group_name       = azurerm_resource_group.rg-robin.name

    ip_configuration {
        name                          = "robin-icconfig"
        subnet_id                     = azurerm_subnet.robin-subnet.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.robin-ip.id
    }

    tags = {
        environment = "robin-ic"
    }
}

# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "example" {
    network_interface_id      = azurerm_network_interface.robin-ic.id
    network_security_group_id = azurerm_network_security_group.robin-nsg.id
}

# Generate random text for a unique storage account name
resource "random_id" "randomId" {
    keepers = {
        # Generate a new ID only when a new resource group is defined
        resource_group = azurerm_resource_group.rg-robin.name
    }

    byte_length = 8
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "robin-storage" {
    name                        = "diag${random_id.randomId.hex}"
    resource_group_name         = azurerm_resource_group.rg-robin.name
    location                    = "westeurope"
    account_tier                = "Standard"
    account_replication_type    = "LRS"

    tags = {
        environment = "robin-storage"
    }
}

# Create (and display) an SSH key
resource "tls_private_key" "robin-ssh" {
  algorithm = "RSA"
  rsa_bits = 4096
}
output "tls_private_key" { 
    value = tls_private_key.example_ssh.private_key_pem 
    sensitive = true
}

# Create virtual machine
resource "azurerm_linux_virtual_machine" "robin-vm" {
    name                  = "robin-vm"
    location              = "westeurope"
    resource_group_name   = azurerm_resource_group.rg-robin.name
    network_interface_ids = [azurerm_network_interface.robin-ic.id]
    size                  = "Standard_DS1_v2"

    os_disk {
        name              = "myOsDisk"
        caching           = "ReadWrite"
        storage_account_type = "Premium_LRS"
    }

    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "18.04-LTS"
        version   = "latest"
    }

    computer_name  = "robin-vm"
    admin_username = "robin"
    disable_password_authentication = true

    admin_ssh_key {
        username       = "robin"
        public_key     = tls_private_key.example_ssh.public_key_openssh
    }

    boot_diagnostics {
        storage_account_uri = azurerm_storage_account.mystorageaccount.primary_blob_endpoint
    }

    tags = {
        environment = "robin-vm"
    }
}