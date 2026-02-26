# 1. Configure the Azure Provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
# 2. Create a Resource Group
resource "azurerm_resource_group" "devops_rg" {
  name     = "rg-devops-portfolio-v2"
  location = "North Europe"
}

# 3. Create a Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-devops"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.devops_rg.location
  resource_group_name = azurerm_resource_group.devops_rg.name
}

# 4. Create a Subnet
resource "azurerm_subnet" "subnet" {
  name                 = "snet-web"
  resource_group_name  = azurerm_resource_group.devops_rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# 5. Create a Public IP (Standard SKU)
resource "azurerm_public_ip" "public_ip" {
  name                = "pip-webserver"
  location            = azurerm_resource_group.devops_rg.location
  resource_group_name = azurerm_resource_group.devops_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}


# 6. Create a Network Security Group (Firewall Rules)
resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-web"
  location            = azurerm_resource_group.devops_rg.location
  resource_group_name = azurerm_resource_group.devops_rg.name

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# 7. Create the Network Interface (NIC)
resource "azurerm_network_interface" "nic" {
  name                = "nic-webserver"
  location            = azurerm_resource_group.devops_rg.location
  resource_group_name = azurerm_resource_group.devops_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }
}
# 7.5 Associate the NSG to the NIC
resource "azurerm_network_interface_security_group_association" "nsg_link" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}
# 8. Create the Linux Virtual Machine
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "vm-webserver"
  resource_group_name = azurerm_resource_group.devops_rg.name
  location            = azurerm_resource_group.devops_rg.location
  size                = "Standard_D2s_v3"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  custom_data = base64encode(<<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y nginx
              echo "<h1>Deployed via Terraform by Shawn Nicol</h1>" > /var/www/html/index.html
              systemctl enable nginx
              systemctl start nginx
              EOF
  )
}

# 9. Output the Public IP
output "web_server_ip" {
  value = azurerm_public_ip.public_ip.ip_address
}