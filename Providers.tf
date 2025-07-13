terraform { 
  cloud { 
    
    organization = "Patient-0" 

    workspaces { 
      name = "CogServices_OpenAI" 
    } 
  } 
}

provider "azurerm" {
  features {
    resource_group {
    }
    key_vault {
    }
  }
 # subscription_id =   "00000000-0000-0000-0000-000000000000" # Replace with your Azure subscription ID
}