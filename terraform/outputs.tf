output "kubeconfig_path" {
  description = "Úsalo con: $env:KUBECONFIG = (terraform output -raw kubeconfig_path)"
  value       = module.cluster.kubeconfig_path
}

output "app_url" {
  value = "http://localhost:${var.app_node_port}"
}

output "argocd_password_cmd" {
  description = "Comando para obtener la contraseña inicial de admin de ArgoCD"
  value       = "kubectl -n ${module.argocd.namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}'"
}
