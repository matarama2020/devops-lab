variable "cluster_name" {
  description = "Nombre del clúster kind"
  type        = string
  default     = "lab"
}

variable "kubernetes_version" {
  description = "Imagen de nodo de kind (define la versión de Kubernetes)"
  type        = string
  default     = "kindest/node:v1.31.0"
}

variable "app_node_port" {
  description = "NodePort de la API que se publica en localhost"
  type        = number
  default     = 30080

  validation {
    condition     = var.app_node_port >= 30000 && var.app_node_port <= 32767
    error_message = "Un NodePort debe estar entre 30000 y 32767."
  }
}

variable "argocd_chart_version" {
  description = "Versión del chart argo-cd (https://artifacthub.io/packages/helm/argo/argo-cd)"
  type        = string
  default     = "7.7.0"
}
