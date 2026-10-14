module "cluster" {
  source = "./modules/kind-cluster"

  name          = var.cluster_name
  node_image    = var.kubernetes_version
  app_node_port = var.app_node_port
}

# Los providers de Helm se configuran con las salidas del módulo del clúster:
# Terraform crea primero el clúster y luego instala ArgoCD dentro de él.
provider "helm" {
  kubernetes {
    host                   = module.cluster.endpoint
    client_certificate     = module.cluster.client_certificate
    client_key             = module.cluster.client_key
    cluster_ca_certificate = module.cluster.cluster_ca_certificate
  }
}

module "argocd" {
  source = "./modules/argocd"

  chart_version = var.argocd_chart_version
}
