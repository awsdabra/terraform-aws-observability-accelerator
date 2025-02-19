module "operator" {
  source = "./add-ons/adot-operator"
  count  = var.enable_amazon_eks_adot ? 1 : 0

  enable_cert_manager = var.enable_cert_manager
  kubernetes_version  = local.eks_cluster_version
  addon_context       = local.context
}

resource "helm_release" "kube_state_metrics" {
  count            = var.enable_kube_state_metrics ? 1 : 0
  chart            = var.ksm_config.helm_chart_name
  create_namespace = var.ksm_config.create_namespace
  namespace        = var.ksm_config.k8s_namespace
  name             = var.ksm_config.helm_release_name
  version          = var.ksm_config.helm_chart_version
  repository       = var.ksm_config.helm_repo_url

  dynamic "set" {
    for_each = var.ksm_config.helm_settings
    content {
      name  = set.key
      value = set.value
    }
  }
}

resource "helm_release" "prometheus_node_exporter" {
  count            = var.enable_node_exporter ? 1 : 0
  chart            = var.ne_config.helm_chart_name
  create_namespace = var.ne_config.create_namespace
  namespace        = var.ne_config.k8s_namespace
  name             = var.ne_config.helm_release_name
  version          = var.ne_config.helm_chart_version
  repository       = var.ne_config.helm_repo_url

  dynamic "set" {
    for_each = var.ne_config.helm_settings
    content {
      name  = set.key
      value = set.value
    }
  }
}

resource "helm_release" "fluxcd" {
  count            = var.enable_fluxcd ? 1 : 0
  chart            = var.flux_config.helm_chart_name
  create_namespace = var.flux_config.create_namespace
  namespace        = var.flux_config.k8s_namespace
  name             = var.flux_config.helm_release_name
  version          = var.flux_config.helm_chart_version
  repository       = var.flux_config.helm_repo_url

  dynamic "set" {
    for_each = var.flux_config.helm_settings
    content {
      name  = set.key
      value = set.value
    }
  }
}

resource "helm_release" "grafana_operator" {
  count            = var.enable_grafana_operator ? 1 : 0
  chart            = var.go_config.helm_chart
  name             = var.go_config.helm_name
  namespace        = var.go_config.k8s_namespace
  version          = var.go_config.helm_chart_version
  create_namespace = var.go_config.create_namespace
  max_history      = 3
}

module "helm_addon" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons/helm-addon?ref=v4.26.0"

  helm_config = merge(
    {
      name        = local.name
      chart       = "${path.module}/otel-config"
      version     = "0.4.0"
      namespace   = local.namespace
      description = "ADOT helm Chart deployment configuration"
    },
    var.helm_config
  )

  set_values = [
    {
      name  = "ampurl"
      value = "${var.managed_prometheus_workspace_endpoint}api/v1/remote_write"
    },
    {
      name  = "region"
      value = var.managed_prometheus_workspace_region
    },
    {
      name  = "ekscluster"
      value = local.context.eks_cluster_id
    },
    {
      name  = "globalScrapeInterval"
      value = var.prometheus_config.global_scrape_interval
    },
    {
      name  = "globalScrapeTimeout"
      value = var.prometheus_config.global_scrape_timeout
    },
    {
      name  = "accountId"
      value = local.context.aws_caller_identity_account_id
    },
    {
      name  = "enableTracing"
      value = var.enable_tracing
    },
    {
      name  = "otlpHttpEndpoint"
      value = var.tracing_config.otlp_http_endpoint
    },
    {
      name  = "otlpGrpcEndpoint"
      value = var.tracing_config.otlp_grpc_endpoint
    },
    {
      name  = "tracingTimeout"
      value = var.tracing_config.timeout
    },
    {
      name  = "tracingSendBatchSize"
      value = var.tracing_config.send_batch_size
    },
    {
      name  = "enableCustomMetrics"
      value = var.enable_custom_metrics
    },
    {
      name  = "customMetricsPorts"
      value = format(".*:(%s)$", join("|", var.custom_metrics_config.ports))
    },
    {
      name  = "customMetricsDroppedSeriesPrefixes"
      value = format("(%s.*)$", join(".*|", var.custom_metrics_config.dropped_series_prefixes))
    },
    {
      name  = "enable_java"
      value = var.enable_java
    },
    {
      name  = "javaScrapeSampleLimit"
      value = var.java_config.scrape_sample_limit
    },
    {
      name  = "enable_nginx"
      value = var.enable_nginx
    },
    {
      name  = "nginxScrapeSampleLimit"
      value = var.nginx_config.scrape_sample_limit
    },
    {
      name  = "enable_istio"
      value = var.enable_istio
    },
    {
      name  = "istioScrapeSampleLimit"
      value = var.istio_config.scrape_sample_limit
    },
    {
      name  = "nginxPrometheusMetricsEndpoint"
      value = var.nginx_config.prometheus_metrics_endpoint
    }
  ]

  irsa_config = {
    create_kubernetes_namespace       = true
    kubernetes_namespace              = local.namespace
    create_kubernetes_service_account = true
    kubernetes_service_account        = try(var.helm_config.service_account, local.name)
    irsa_iam_policies = [
      "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonPrometheusRemoteWriteAccess",
      "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXrayWriteOnlyAccess"
    ]
  }

  addon_context = local.context

  depends_on = [module.operator]
}

module "java_monitoring" {
  source            = "./patterns/java"
  count             = var.enable_java ? 1 : 0
  enable_dashboards = var.enable_dashboards

  managed_prometheus_workspace_id = var.managed_prometheus_workspace_id
  enable_alerting_rules           = var.java_config.enable_alerting_rules
  enable_recording_rules          = var.java_config.enable_recording_rules
  dashboards_folder_id            = var.dashboards_folder_id
}

module "nginx_monitoring" {
  source = "./patterns/nginx"
  count  = var.enable_nginx ? 1 : 0

  managed_prometheus_workspace_id = var.managed_prometheus_workspace_id
  enable_alerting_rules           = var.nginx_config.enable_alerting_rules
  dashboards_folder_id            = var.dashboards_folder_id
}

module "istio_monitoring" {
  source = "./patterns/istio"
  count  = var.enable_istio ? 1 : 0

  managed_prometheus_workspace_id = var.managed_prometheus_workspace_id
  enable_alerting_rules           = var.istio_config.enable_alerting_rules
  dashboards_folder_id            = var.dashboards_folder_id
}



module "fluentbit_logs" {
  source = "./add-ons/aws-for-fluentbit"
  count  = var.enable_logs ? 1 : 0

  cw_log_retention_days = var.logs_config.cw_log_retention_days
  addon_context         = local.context
}

module "external_secrets" {
  source = "./add-ons/external-secrets"
  count  = var.enable_external_secrets ? 1 : 0

  enable_external_secrets = var.enable_external_secrets
  grafana_api_key         = var.grafana_api_key
  addon_context           = local.context
  target_secret_namespace = var.target_secret_namespace
  target_secret_name      = var.target_secret_name

  depends_on = [resource.helm_release.grafana_operator]
}
