terraform {
  required_providers {
    helm = {
      source = "hashicorp/helm"
    }
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = var.namespace
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version

  # Valores del chart en un archivo aparte: más legible que muchos bloques `set`
  values = [file("${path.module}/values.yaml")]

  wait    = true
  timeout = 600
}
