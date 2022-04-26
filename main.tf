#----------------------------------------------------------
# Resource Group, VNet, Subnet selection, Storage account & Random Resources
#----------------------------------------------------------
data "azurerm_resource_group" "rgrp" {
  count = var.create_resource_group == false ? 1 : 0
  name  = var.resource_group_name
}

resource "azurerm_resource_group" "rg" {
  count    = var.create_resource_group ? 1 : 0
  name     = lower(var.resource_group_name)
  location = var.location
  tags     = merge({ "ResourceName" = format("%s", var.resource_group_name) }, var.tags, )
}

data "azurerm_virtual_network" "vnet" {
  name                = var.virtual_network_name
  resource_group_name = var.vnet_resource_group_name == null ? var.resource_group_name : var.vnet_resource_group_name
}

data "azurerm_subnet" "snet" {
  name                 = var.subnet_name
  virtual_network_name = data.azurerm_virtual_network.vnet.name
  resource_group_name  = data.azurerm_virtual_network.vnet.resource_group_name
}

data "azurerm_log_analytics_workspace" "logws" {
  count               = var.log_analytics_workspace_name != null ? 1 : 0
  name                = var.log_analytics_workspace_name
  resource_group_name = var.resource_group_name
}

data "azurerm_storage_account" "storeacc" {
  count               = var.storage_account_name != null ? 1 : 0
  name                = var.storage_account_name
  resource_group_name = var.storage_account_resource_group
}


data "azurerm_key_vault" "ssl_key_vault" {
  name                = var.key_vault_name
  resource_group_name = var.key_vault_resource_group_name
}

# data "azurerm_key_vault_certificate" "ssl_secret" {
#   for_each     = var.ssl_certificates
#   name         = each.value.secret_name
#   key_vault_id = data.azurerm_key_vault.ssl_key_vault.id
# }
  


#-----------------------------------
# Public IP for application gateway
#-----------------------------------
resource "azurerm_public_ip" "pip" {
  name                = var.app_gateway_public_ip_name
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

#----------------------------------------------
# Application Gateway with optional blocks
#----------------------------------------------
resource "azurerm_application_gateway" "main" {
  name                = var.app_gateway_name
  resource_group_name = var.resource_group_name
  location            = var.location
  zones               = var.zones
  tags                = var.tags

  sku {
    name     = var.sku.name
    tier     = var.sku.tier
    capacity = var.autoscale_configuration == null ? var.sku.capacity : null
  }

  dynamic "autoscale_configuration" {
    for_each = var.autoscale_configuration != null ? [var.autoscale_configuration] : []
    content {
      min_capacity = lookup(autoscale_configuration.value, "min_capacity")
      max_capacity = lookup(autoscale_configuration.value, "max_capacity")
    }
  }

  gateway_ip_configuration {
    name      = local.gateway_ip_configuration_name
    subnet_id = data.azurerm_subnet.snet.id
  }

  frontend_ip_configuration {
    name                          = local.frontend_ip_configuration_name_public
    public_ip_address_id          = azurerm_public_ip.pip.id
  }

  frontend_ip_configuration {
    name                          = local.frontend_ip_configuration_name_private
    private_ip_address            = var.private_ip_address
    private_ip_address_allocation = "Static"
    subnet_id                     = data.azurerm_subnet.snet.id
  }

  frontend_port {
    name = local.frontend_port_name_http
    port = 80
  }

  frontend_port {
    name = local.frontend_port_name_https
    port = 443
  }

  #----------------------------------------------------------
  # Backend Address Pool Configuration (Required)
  #----------------------------------------------------------
  dynamic "backend_address_pool" {
    for_each = var.application_endpoints
    content {
      name         = backend_address_pool.value.application
      fqdns        = backend_address_pool.value.backend_pool_fqdns
      ip_addresses = backend_address_pool.value.ip_addresses
    }
  }

  #----------------------------------------------------------
  # Backend HTTP Settings (Required)
  #----------------------------------------------------------
  dynamic "backend_http_settings" {
    for_each = var.application_endpoints
    content {
      name                                = backend_http_settings.value.application
      cookie_based_affinity               = backend_http_settings.value.cookie_based_affinity
      affinity_cookie_name                = lookup(backend_http_settings.value, "affinity_cookie_name", null)
      path                                = lookup(backend_http_settings.value, "override_backend_path", "/")
      port                                = backend_http_settings.value.http_settings_port
      probe_name                          = "${backend_http_settings.value.application}-probe"
      protocol                            = backend_http_settings.value.http_settings_port == 443 ? "Https" : "Http"
      request_timeout                     = lookup(backend_http_settings.value, "request_timeout", local.default.request_timeout)
      host_name                           = lookup(backend_http_settings.value, "http_settings_override_host_name", null)
      pick_host_name_from_backend_address = lookup(backend_http_settings.value, "pick_host_name_from_backend_address", false)
    }
  }

  #----------------------------------------------------------
  # HTTP Listener Configuration (Required) - HTTPS & HTTP
  #----------------------------------------------------------
  dynamic "http_listener" {
    for_each = var.application_endpoints
    content {
      name                           = join("", tolist([http_listener.value.application,"-https"]))
      frontend_ip_configuration_name = local.frontend_ip_configuration_name_private
      frontend_port_name             = local.frontend_port_name_https
      host_name                      = lookup(http_listener.value, "listener_host_name", null)
      protocol                       = "Https"
      require_sni                    = true
      ssl_certificate_name           = lookup(http_listener.value, "ssl_certificate_name", local.default.ssl_certificate_name)
    }
  }

  #### HTTP Listener

  dynamic "http_listener" {
    for_each = var.application_endpoints
    content {
      name                           = join("", tolist([http_listener.value.application,"-http"]))
      frontend_ip_configuration_name = local.frontend_ip_configuration_name_private
      frontend_port_name             = local.frontend_port_name_http
      host_name                      = lookup(http_listener.value, "listener_host_name", null)
      protocol                       = "Http"
    }
  }

  #----------------------------------------------------------
  # Request routing rules Configuration (Required) - HTTPS & HTTP
  #----------------------------------------------------------
  dynamic "request_routing_rule" {
    for_each = var.application_endpoints
    content {
      name                        = request_routing_rule.value.application
      rule_type                   = "Basic"
      http_listener_name          = join("", tolist([request_routing_rule.value.application,"-https"]))
      backend_address_pool_name   = request_routing_rule.value.application
      backend_http_settings_name  = request_routing_rule.value.application
    }
  }

  #### Http routing rules - Redirect
  dynamic "request_routing_rule" {
    for_each = var.application_endpoints
    content {
      name                        = join("", tolist([request_routing_rule.value.application,"-http"]))
      rule_type                   = "Basic"
      http_listener_name          = join("", tolist([request_routing_rule.value.application,"-http"]))
      redirect_configuration_name = join("", tolist([request_routing_rule.value.application,"-redirect"]))
    }
  }

  #----------------------------------------------------------
  # Redirect Configuration
  #----------------------------------------------------------
  dynamic "redirect_configuration" {
    for_each = var.application_endpoints
    content {
      name                 = join("", tolist([redirect_configuration.value.application,"-redirect"]))
      redirect_type        = "Permanent"
      target_listener_name = join("", tolist([redirect_configuration.value.application,"-https"]))
      include_path         = true
      include_query_string = true
    }
  }

   #----------------------------------------------------------
  # Health Probe
  #----------------------------------------------------------
  dynamic "probe" {
    for_each = var.application_endpoints
    content {
      name                      = join("", tolist([probe.value.application,"-probe"]))
      host                      = lookup(probe.value, "probe_host_name", "127.0.0.1")
      interval                  = probe.value.interval
      protocol                  = probe.value.http_settings_port == 443 ? "Https" : "Http"
      path                      = probe.value.probe_path
      timeout                   = probe.value.probe_timeout
      unhealthy_threshold       = probe.value.unhealthy_threshold

      match {
        # define a local for this big list and put it here.
        status_code = local.default.return_codes
        body        = ""
    }
    }
  }


  #----------------------------------------------------------
  # SSL Certificate (.pfx) Configuration (Optional)
  #----------------------------------------------------------
   dynamic "ssl_certificate" {
    for_each = var.ssl_certificates
    content {
      name                = ssl_certificate.value.certificate_name
      key_vault_secret_id = ssl_certificate.value.key_vault_secret_id
    }
  }


  #---------------------------------------------------------------
  # Identity block Configuration (Optional)
  # A list with a single user managed identity id to be assigned
  #---------------------------------------------------------------
  dynamic "identity" {
    for_each = var.identity_ids != null ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = var.identity_ids
    }
  }


  #----------------------------------------------------------
  # Rewrite Rules Set configuration (Optional)
  #----------------------------------------------------------
  dynamic "rewrite_rule_set" {
    for_each = var.rewrite_rule_set
    content {
      name = var.rewrite_rule_set.name

      dynamic "rewrite_rule" {
        for_each = lookup(var.rewrite_rule_set, "rewrite_rules", [])
        content {
          name          = rewrite_rule.value.name
          rule_sequence = rewrite_rule.value.rule_sequence

          dynamic "condition" {
            for_each = lookup(rewrite_rule_set.value, "condition", [])
            content {
              variable    = condition.value.variable
              pattern     = condition.value.pattern
              ignore_case = condition.value.ignore_case
              negate      = condition.value.negate
            }
          }

          dynamic "request_header_configuration" {
            for_each = lookup(rewrite_rule.value, "request_header_configuration", [])
            content {
              header_name  = request_header_configuration.value.header_name
              header_value = request_header_configuration.value.header_value
            }
          }

          dynamic "response_header_configuration" {
            for_each = lookup(rewrite_rule.value, "response_header_configuration", [])
            content {
              header_name  = response_header_configuration.value.header_name
              header_value = response_header_configuration.value.header_value
            }
          }

          dynamic "url" {
            for_each = lookup(rewrite_rule.value, "url", [])
            content {
              path         = url.value.path
              query_string = url.value.query_string
              reroute      = url.value.reroute
            }
          }
        }
      }
    }
  }

  #----------------------------------------------------------
  # Web application Firewall (WAF) configuration (Optional)
  # Tier to be either “WAF” or “WAF V2”
  #----------------------------------------------------------
  dynamic "waf_configuration" {
    for_each = var.waf_configuration != null ? [var.waf_configuration] : []
    content {
      enabled                  = true
      firewall_mode            = lookup(waf_configuration.value, "firewall_mode", "Detection")
      rule_set_type            = "OWASP"
      rule_set_version         = lookup(waf_configuration.value, "rule_set_version", "3.1")
      file_upload_limit_mb     = lookup(waf_configuration.value, "file_upload_limit_mb", 100)
      request_body_check       = lookup(waf_configuration.value, "request_body_check", true)
      max_request_body_size_kb = lookup(waf_configuration.value, "max_request_body_size_kb", 128)

      dynamic "disabled_rule_group" {
        for_each = waf_configuration.value.disabled_rule_group
        content {
          rule_group_name = disabled_rule_group.value.rule_group_name
          rules           = disabled_rule_group.value.rules
        }
      }

      dynamic "exclusion" {
        for_each = waf_configuration.value.exclusion
        content {
          match_variable          = exclusion.value.match_variable
          selector_match_operator = exclusion.value.selector_match_operator
          selector                = exclusion.value.selector
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

#---------------------------------------------------------------
# azurerm monitoring diagnostics - Application Gateway
#---------------------------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "agw-diag" {
  count                      = var.log_analytics_workspace_name != null || var.storage_account_name != null ? 1 : 0
  name                       = lower("agw-${var.app_gateway_name}-diag")
  target_resource_id         = azurerm_application_gateway.main.id
  storage_account_id         = var.storage_account_name != null ? data.azurerm_storage_account.storeacc.0.id : null
  log_analytics_workspace_id = var.log_analytics_workspace_name != null ? data.azurerm_log_analytics_workspace.logws.0.id : null

  dynamic "log" {
    for_each = var.agw_diag_logs
    content {
      category = log.value
      enabled  = true

      retention_policy {
        enabled = false
        days    = 0
      }
    }
  }

  metric {
    category = "AllMetrics"

    retention_policy {
      enabled = false
      days    = 0
    }
  }

  lifecycle {
    ignore_changes = [log, metric]
  }
}
