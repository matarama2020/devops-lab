terraform {
  required_providers {
    kind = {
      source = "tehcyx/kind"
    }
  }
}

resource "kind_cluster" "this" {
  name            = var.name
  node_image      = var.node_image
  wait_for_ready  = true
  kubeconfig_path = abspath("${path.root}/${var.name}-config")

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      # Publica el NodePort de la app en localhost del host (Docker Desktop)
      extra_port_mappings {
        container_port = var.app_node_port
        host_port      = var.app_node_port
      }
    }
  }
}
