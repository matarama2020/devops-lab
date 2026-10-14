terraform {
  required_version = ">= 1.6"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.6"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17" # la 3.x cambia la sintaxis del bloque kubernetes
    }
  }

  # Estado local (terraform.tfstate). Reto fase 3: moverlo a un backend remoto.
}
