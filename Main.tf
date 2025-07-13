data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "example" {
  name     = "Cogservices-openai-1"
  location = "East US"
}

resource "azurerm_key_vault" "openai_kv" {
  name                      = "kv-cogacct-0"
  location                  = azurerm_resource_group.example.location
  resource_group_name       = azurerm_resource_group.example.name
  tenant_id                 = data.azurerm_client_config.current.tenant_id
  sku_name                  = "standard"
  
  # FIX: Enable Soft Delete and Purge Protection as required for CMK
  soft_delete_retention_days = 7
  purge_protection_enabled   = true

  enable_rbac_authorization = true
}

resource "azurerm_key_vault_key" "openai_key" {
  name         = "openai-key0"
  key_vault_id = azurerm_key_vault.openai_kv.id
  key_type     = "RSA"
  key_size     = 2048
  key_opts     = ["encrypt", "decrypt", "sign", "verify", "wrapKey", "unwrapKey"]
}

resource "azurerm_virtual_network" "openai_vnet" {
  name                = "vnet-cogservices-openai"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
}

resource "azurerm_subnet" "openai_subnet" {
  name                 = "subnet-cogservices-openai"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.openai_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
  # NOTE: service_endpoints are not required when using private endpoints for the subnet.
  # They can be removed, but leaving them does not cause harm.
  service_endpoints    = ["Microsoft.CognitiveServices"]
}

resource "azurerm_cognitive_account" "openai" {
  name                  = "tevopenaiaccount"
  location              = azurerm_resource_group.example.location
  resource_group_name   = azurerm_resource_group.example.name
  kind                  = "OpenAI"
  sku_name              = "S0"
   # Ensure this name is globally unique.
  custom_subdomain_name = "tevopenaisubdomain"

  identity {
    type = "SystemAssigned"
  }

  tags = {
    environment = "dev"
  }
}

# PREREQUISITE: The principal running Terraform must have the "User Access Administrator" or "Owner" role on this Key Vault
# to be able to create the role assignments below.
resource "azurerm_role_assignment" "cog_account_crypto_officer" {
  scope                = azurerm_key_vault.openai_kv.id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = azurerm_cognitive_account.openai.identity[0].principal_id
}

resource "azurerm_role_assignment" "current_user_crypto_officer" {
  scope                = azurerm_key_vault.openai_kv.id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_cognitive_account_customer_managed_key" "openai_cmk" {
  cognitive_account_id = azurerm_cognitive_account.openai.id
  key_vault_key_id     = azurerm_key_vault_key.openai_key.id

  # FIX: Added an explicit dependency to ensure the role assignment is complete
  # before attempting to associate the key.
  depends_on = [
    azurerm_role_assignment.cog_account_crypto_officer
  ]
}

resource "azurerm_private_endpoint" "openai_pe" {
  name                = "pe-cogopenai"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  subnet_id           = azurerm_subnet.openai_subnet.id

  private_service_connection {
    name                           = "psc-cogopenai"
    private_connection_resource_id = azurerm_cognitive_account.openai.id
    is_manual_connection           = false
    subresource_names              = ["account"]
  }
}

resource "azurerm_private_dns_zone" "cog_dns" {
  name                = "privatelink.cognitiveservices.azure.com"
  resource_group_name = azurerm_resource_group.example.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "cog_dns_link" {
  name                  = "cog-dns-vnet-link"
  resource_group_name   = azurerm_resource_group.example.name
  private_dns_zone_name = azurerm_private_dns_zone.cog_dns.name
  virtual_network_id    = azurerm_virtual_network.openai_vnet.id
}

resource "azurerm_private_dns_a_record" "cog_dns_record" {
  name                = azurerm_cognitive_account.openai.custom_subdomain_name # FIX: Use the custom subdomain for the DNS record
  zone_name           = azurerm_private_dns_zone.cog_dns.name
  resource_group_name = azurerm_resource_group.example.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.openai_pe.private_service_connection[0].private_ip_address]
}