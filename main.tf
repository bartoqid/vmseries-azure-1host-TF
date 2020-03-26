provider "azurerm" {}

locals {
  virtual_machine_name = "${var.prefix}vm-series"
}

#Create a Resource Group for the new Virtual Machine
resource "azurerm_resource_group" "main" {
  name     = "${var.prefix}-Test1"
  location = "${var.location}"
}

#Create a Virtual Network within the Resource Group
resource "azurerm_virtual_network" "main" {
  name                = "${var.prefix}-network"
  address_space       = ["10.5.0.0/16"]
  resource_group_name = "${azurerm_resource_group.main.name}"
  location            = "${azurerm_resource_group.main.location}"
}

#Create the first Subnet within the Virtual Network
resource "azurerm_subnet" "Untrust" {
  name                 = "Untrust"
  virtual_network_name = "${azurerm_virtual_network.main.name}"
  resource_group_name  = "${azurerm_resource_group.main.name}"
  address_prefix       = "10.5.1.0/24"
}


#Create the second Subnet within the Virtual Network
resource "azurerm_subnet" "Trust" {
  name                 = "Trust"
  virtual_network_name = "${azurerm_virtual_network.main.name}"
  resource_group_name  = "${azurerm_resource_group.main.name}"
  address_prefix       = "10.5.2.0/24"
}

#Create the third Subnet within the Virtual Network
resource "azurerm_subnet" "management" {
  name                 = "management"
  virtual_network_name = "${azurerm_virtual_network.main.name}"
  resource_group_name  = "${azurerm_resource_group.main.name}"
  address_prefix       = "10.5.0.0/24"
}

#create UDR from Trust to outside
resource "azurerm_route_table" "PAN_FW_RT_Trust" {
  name                = "Trust"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"
            
  route {
    name           = "Trust-to-outside"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "10.5.2.4"
  }
}

#subnet association Trust
resource "azurerm_subnet_route_table_association" "Trustassc" {
  subnet_id      = "${azurerm_subnet.Trust.id}"
  route_table_id = "${azurerm_route_table.PAN_FW_RT_Trust.id}"
}

#create UDR from  Untrust back to trust
resource "azurerm_route_table" "PAN_FW_RT_Untrust" {
  name                = "Untrust"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"

  route {
    name           = "Untrust-to-Trust"
    address_prefix = "10.5.2.0/24"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "10.5.1.4"
  }
}

#subnet association Untrust
resource "azurerm_subnet_route_table_association" "Untrustassc" {
  subnet_id      = "${azurerm_subnet.Untrust.id}"
  route_table_id = "${azurerm_route_table.PAN_FW_RT_Untrust.id}"
}

#Create a Network Security Group to allow any traffic inbound and outbound
resource "azurerm_network_security_group" "main" {
  name                = "${var.prefix}-nsg"
  location            = "${azurerm_resource_group.main.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"

  security_rule {
    name                       = "allow_all_inbound"
    description                = "Allow all"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow_all_outboundP"
    description                = "Allow All access"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

#create vmseries Public IPAddresses management and untrust interface
resource "azurerm_public_ip" "PublicIP_0" {
  name = "fwpublicIP0"
  location = "${var.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"
  public_ip_address_allocation = "Dynamic"
}


resource "azurerm_public_ip" "PublicIP_1" {
  name = "fwpublicIP1"
  location = "${var.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"
  public_ip_address_allocation = "Dynamic"
}

#create vmseries Network Interfaces
resource "azurerm_network_interface" "VNIC0" {
  name                = "vmarivaieth0"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"
  network_security_group_id = "${azurerm_network_security_group.main.id}"
  depends_on          = ["azurerm_virtual_network.main", "azurerm_public_ip.PublicIP_0"]

  ip_configuration {
    name                          = "ipmgmt"
    subnet_id                     = "${azurerm_subnet.management.id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = "${azurerm_public_ip.PublicIP_0.id}"
  }
}

resource "azurerm_network_interface" "VNIC1" {
  name                = "vmarivaieth1"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"
  network_security_group_id = "${azurerm_network_security_group.main.id}"
    depends_on          = ["azurerm_virtual_network.main", "azurerm_public_ip.PublicIP_1"]

  enable_ip_forwarding = true
  ip_configuration {
    name                          = "ipeth1"
    subnet_id                     = "${azurerm_subnet.Untrust.id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = "${azurerm_public_ip.PublicIP_1.id}"
  }
}

resource "azurerm_network_interface" "VNIC2" {
  name                = "vmarivaieth2"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"
  network_security_group_id = "${azurerm_network_security_group.main.id}"
  depends_on          = ["azurerm_virtual_network.main"]

  enable_ip_forwarding = true
  ip_configuration {
    name                          = "ipeth2"
    subnet_id                     = "${azurerm_subnet.Trust.id}"
    private_ip_address_allocation = "Dynamic"
  }
}


#create storage for vm-series
resource "azurerm_storage_account" "storagepan4" {
  name = "${var.prefix}storageaccount4"
  resource_group_name = "${azurerm_resource_group.main.name}"
  location = "${var.location}"
  account_tier = "Standard_LRS"
  account_replication_type = "LRS"
  account_tier = "Standard" 
}

#create vm-series
resource "azurerm_virtual_machine" "main" {
  name                         = "${var.prefix}-vm"
  location                     = "${azurerm_resource_group.main.location}"
  resource_group_name          = "${azurerm_resource_group.main.name}"
  primary_network_interface_id = "${azurerm_network_interface.VNIC0.id}"
  network_interface_ids        = ["${azurerm_network_interface.VNIC0.id}", "${azurerm_network_interface.VNIC1.id}", "${azurerm_network_interface.VNIC2.id}"]
  vm_size                      = "Standard_D3"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  delete_os_disk_on_termination = true


  # Uncomment this line to delete the data disks automatically when deleting the VM
  delete_data_disks_on_termination = true
  
  plan {
    name = "bundle2"
    publisher = "paloaltonetworks"
    product = "vmseries1"
  }

  storage_image_reference {
    publisher = "paloaltonetworks"
    offer     = "vmseries1"
    sku       = "bundle2"
    version   = "latest"
  }

  storage_os_disk {
    name              = "${local.virtual_machine_name}-osdisk"
    vhd_uri           = "${azurerm_storage_account.storagepan4.primary_blob_endpoint}vhds/${var.prefix}-vmseries1-bundle2.vhd"
    caching           = "ReadWrite"
    create_option     = "FromImage"
  }

  os_profile {
    computer_name  = "${local.virtual_machine_name}"
    admin_username = "${var.admin_username}"
    admin_password = "${var.admin_password}"
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

}


#create network interface for host
resource "azurerm_network_interface" "host-nic" {
  name                = "${var.prefix}-host-nic"
  location            = "${azurerm_resource_group.main.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"

  ip_configuration {
    name                          = "primary"
    subnet_id                     = "${azurerm_subnet.Trust.id}"
    private_ip_address_allocation = "dynamic"
  }
}

#create ubuntu host
resource "azurerm_virtual_machine" "ubuntu" {
  name                         = "${var.prefix}-vmubuntu"
  location                     = "${azurerm_resource_group.main.location}"
  resource_group_name          = "${azurerm_resource_group.main.name}"
  primary_network_interface_id = "${azurerm_network_interface.host-nic.id}"
  network_interface_ids        = ["${azurerm_network_interface.host-nic.id}"]
  vm_size                      = "Standard_D1"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  delete_os_disk_on_termination = true


  # Uncomment this line to delete the data disks automatically when deleting the VM
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  storage_os_disk {
    name              = "${local.virtual_machine_name}-osdisk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "${local.virtual_machine_name}"
    admin_username = "${var.admin_username}"
    admin_password = "${var.admin_password}"
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
}
