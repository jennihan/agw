variable "create_resource_group" {
  description = "Whether to create resource group and use it for all networking resources"
  default     = false
}

variable "resource_group_name" {
  description = "A container that holds related resources for an Azure solution"
  default     = ""
}

variable "location" {
  description = "The location/region to keep all your network resources. To get the list of all locations with table format from azure cli, run 'az account list-locations -o table'"
  default     = ""
}

variable "virtual_network_name" {
  description = "The name of the virtual network"
  default     = ""
}

variable "vnet_resource_group_name" {
  description = "The resource group name where the virtual network is created"
  default     = null
}

variable "subnet_name" {
  description = "The name of the subnet to use in VM scale set"
  default     = ""
}

variable "key_vault_resource_group_name" {
  description = "The resource group name where the key vault is created"
  default     = ""
}

variable "key_vault_name" {
  description = "The name of the key vault for certificate"
  default     = ""
}

variable "app_gateway_name" {
  description = "The name of the application gateway"
  default     = ""
}

variable "app_gateway_public_ip_name" {
  description = "The name of the application gateway public ip"
  default     = ""
}

variable "zones" {
  description = "A collection of availability zones to spread the Application Gateway over."
  type        = list(string)
  default     = [] #["1", "2", "3"]
}

variable "sku" {
  description = "The sku pricing model of v1 and v2"
  type = object({
    name     = string
    tier     = string
    capacity = optional(number)
  })
  default = {
    capacity = 2
    name = "WAF_v2"
    tier = "WAF_v2"
  }
}

variable "autoscale_configuration" {
  description = "Minimum or Maximum capacity for autoscaling. Accepted values are for Minimum in the range 0 to 100 and for Maximum in the range 2 to 125"
  type = object({
    min_capacity = number  
    max_capacity = number
  })
  default = null
}

variable "private_ip_address" {
  description = "Private IP Address to assign to the Load Balancer."
}

variable "application_endpoints" {
    description = "List of application endpoints"
    type = list(object({
    
    # application name
    application  = string # mcadev.cs.ciena.com

    # backend_address_pools  either fqdns or ip_addresses
    backend_pool_fqdns        = optional(list(string)) # List of web app's default fqdn, e.g. ["cienamcsmcadev.azurewebshites.net"]
    ip_addresses = optional(list(string))

    # backend_http_settings
    http_settings_port                   = number # The port which should be used for this Backend HTTP Settings Collection. 443 or 80
    cookie_based_affinity               = string # "Enabled" or "Disabled".
    affinity_cookie_name                = optional(string)
    override_backend_path               = optional(string)
    request_timeout                     = optional(number) # Default is 600
    http_settings_override_host_name    = optional(string) # Host header to be sent to the backend servers, e.g. "mcadev.cs.ciena.com"
    pick_host_name_from_backend_address = optional(bool) # Whether host header should be picked from the host name of the backend server. Defaults to false.

  # http_listeners
    listener_host_name                  = string # The Hostname which should be used for this HTTP Listener, e.g "mcadev.cs.ciena.com"
    ssl_certificate_name                = string

  # health_probes
    probe_host_name                           = string
    interval                                  = number
    probe_path                                = string
    probe_timeout                             = number
    unhealthy_threshold                       = number
    pick_host_name_from_backend_http_settings = optional(bool)
    minimum_servers                           = optional(number)

  }))
}

variable "log_analytics_workspace_name" {
  description = "The name of log analytics workspace name"
  default     = null
}

variable "storage_account_name" {
  description = "The name of the hub storage account to store logs"
  default     = null
}

variable "storage_account_resource_group" {
  description = "The name of the logging storage account resource group to store logs"
  default     = null
}

variable "ssl_certificates" {
  description = "List of SSL certificates data for Application gateway"
  type = map(any)
  
  default = {

  }
}

variable "identity_ids" {
  description = "Specifies a list with a single user managed identity id to be assigned to the Application Gateway"
  default     = []
}

variable "rewrite_rule_set" {
  description = "List of rewrite rule set including rewrite rules"
  type        = any
  default     = []
}

variable "waf_configuration" {
  description = "Web Application Firewall support for your Azure Application Gateway"
  type = object({
    firewall_mode            = string
    rule_set_version         = string
    file_upload_limit_mb     = optional(number)
    request_body_check       = optional(bool)
    max_request_body_size_kb = optional(number)
    disabled_rule_group = optional(list(object({
      rule_group_name = string
      rules           = optional(list(string))
    })))
    exclusion = optional(list(object({
      match_variable          = string
      selector_match_operator = optional(string)
      selector                = optional(string)
    })))
  })
  default = null
}

variable "agw_diag_logs" {
  description = "Application Gateway Monitoring Category details for Azure Diagnostic setting"
  default     = ["ApplicationGatewayAccessLog", "ApplicationGatewayPerformanceLog", "ApplicationGatewayFirewallLog"]
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}



