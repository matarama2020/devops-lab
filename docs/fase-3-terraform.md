# Fase 3 — Infraestructura como código con Terraform

**Objetivo:** crear con código un clúster Kubernetes local (kind) y desplegar ArgoCD dentro con
Helm, organizándolo en módulos.

---

## 3.1 Conceptos

### Qué es y qué no es
Terraform crea, modifica y destruye **infraestructura** (clústeres, redes, VMs, buckets, DNS…)
describiéndola en HCL. No sirve para configurar *dentro* de un servidor (eso es Ansible) ni para
desplegar cada versión de tu app (eso es ArgoCD en este lab). Su punto fuerte: **un mismo flujo
para cualquier proveedor** (AWS, Azure, Docker, kind, GitHub…).

### Piezas
| Pieza | Ejemplo en el lab | Qué es |
|---|---|---|
| **Provider** | `tehcyx/kind`, `hashicorp/helm` | Plugin que traduce HCL a llamadas a una API |
| **Resource** | `kind_cluster.this`, `helm_release.argocd` | Algo que Terraform crea y gestiona |
| **Variable** | `var.cluster_name` | Entrada parametrizable (con tipo, default y `validation`) |
| **Output** | `kubeconfig_path` | Valor que se expone tras el apply (o hacia el módulo padre) |
| **Module** | `modules/kind-cluster`, `modules/argocd` | Carpeta reutilizable con sus propias variables/outputs |
| **State** | `terraform.tfstate` | Mapa entre tu código y los objetos reales (IDs, atributos) |
| **Lock file** | `.terraform.lock.hcl` | Fija las versiones exactas de los providers (súbelo a Git) |

### El ciclo de vida
```
terraform init     → descarga providers y módulos (.terraform/)
terraform plan     → refresca el estado real, lo compara con el código y muestra el DIFF
terraform apply    → ejecuta el plan (crea + / modifica ~ / destruye -)
terraform destroy  → elimina todo lo que está en el state
```

### El state: el concepto más importante
Terraform **no "busca" tu infraestructura**: recuerda lo que creó en el state. Si borras el state,
Terraform cree que nada existe e intentará crearlo todo de nuevo. Por eso en equipos el state va
en un **backend remoto** (S3, Azure Storage, Terraform Cloud) con **bloqueo** para que dos
personas no hagan apply a la vez. El state puede contener secretos (aquí, la clave del clúster):
nunca se sube a Git (ver `.gitignore`).

### Grafo de dependencias
No hay que decir el orden. En `main.tf` el provider `helm` usa `module.cluster.endpoint`; Terraform
deduce que primero debe existir el clúster y después instalar ArgoCD. Las referencias entre
recursos **son** el orden. (`depends_on` solo se usa para dependencias que no se ven en el código.)

### Drift
Si alguien cambia la infraestructura a mano, el siguiente `plan` lo detecta (compara state +
realidad vs código) y propone devolverla a lo declarado.

### Las dos piezas que crea este lab
- **kind** (*Kubernetes IN Docker*): cada "nodo" de Kubernetes es un contenedor Docker. Ideal para
  practicar. `extra_port_mappings` publica el puerto 30080 del nodo en `localhost:30080`.
- **Helm**: gestor de paquetes de Kubernetes. Un *chart* es una plantilla de manifiestos; un
  *release* es una instalación de ese chart con unos *values*. El provider `helm` permite que
  Terraform instale charts.

---

## 3.2 Lectura guiada

```
terraform/
├─ versions.tf        versión de Terraform y providers (~> fija la versión mayor/menor)
├─ variables.tf       entradas con validación (NodePort entre 30000 y 32767)
├─ main.tf            llama a los módulos y configura el provider helm con salidas del clúster
├─ outputs.tf         kubeconfig, URL de la app, comando de la contraseña de ArgoCD
└─ modules/
   ├─ kind-cluster/   recurso kind_cluster + outputs de credenciales (client_key = sensitive)
   └─ argocd/         helm_release + values.yaml
```

Detalles para fijarte:
- `version = "~> 2.17"` en helm: acepta 2.17, 2.18… pero no 3.0, que cambió la sintaxis del bloque
  `kubernetes`. Fijar versiones evita que un `init` futuro rompa tu código.
- `sensitive = true` en `client_key`: Terraform la oculta en la salida de `plan`/`apply` (pero sigue
  en el state en texto plano).
- `abspath("${path.root}/${var.name}-config")`: el kubeconfig queda en `terraform/lab-config`.

---

## 3.3 Práctica

```powershell
cd terraform
terraform init
terraform fmt -recursive          # formatea el código
terraform validate
terraform plan                    # lee el plan: 2 recursos a crear
terraform apply                   # escribe "yes". Tarda 2-5 min
```

Conéctate al clúster:

```powershell
$env:KUBECONFIG = (terraform output -raw kubeconfig_path)
kubectl get nodes
kubectl get pods -n argocd
docker ps                          # ¡el nodo de Kubernetes es un contenedor!
```

Explora el state:

```powershell
terraform state list
terraform state show module.cluster.kind_cluster.this
terraform output
terraform graph                    # grafo en formato DOT (pégalo en https://dreampuf.github.io/GraphvizOnline)
```

---

## 3.4 Experimentos

1. **Idempotencia:** ejecuta `terraform plan` otra vez. Debe decir *No changes*.
2. **Cambio que fuerza reemplazo:** cambia `kubernetes_version` a `kindest/node:v1.30.0` y haz
   `plan`. Verás `-/+ (forces replacement)`: hay atributos que no se pueden modificar en sitio.
   No lo apliques (o sí, y observa que ArgoCD se reinstala).
3. **Cambio en sitio:** en `modules/argocd/values.yaml` cambia `timeout.reconciliation` a `120s`.
   `plan` mostrará `~ update in-place` del helm_release.
4. **Drift:** `helm uninstall argocd -n argocd` (con `helm` instalado) o
   `kubectl delete ns argocd`, y luego `terraform plan`. Terraform detecta que falta y lo recrea.
5. **Validación:** `terraform plan -var app_node_port=8080`. Lee el mensaje de tu `validation`.
6. **Pérdida de state:** copia `terraform.tfstate` a otro lugar, bórralo y ejecuta `plan`.
   Terraform quiere crear todo otra vez (y fallaría porque el clúster ya existe). Restaura el
   archivo. Ahora entiendes por qué el state se protege.

---

## Autoevaluación

<details><summary>1. ¿Qué hace exactamente <code>terraform plan</code>?</summary>

Refresca los atributos reales de los recursos que están en el state, los compara con lo que
declara el código y calcula las acciones (crear, modificar en sitio, reemplazar, destruir) sin
ejecutarlas.
</details>

<details><summary>2. ¿Cómo sabe Terraform que debe crear el clúster antes de instalar ArgoCD si no hay ningún <code>depends_on</code>?</summary>

Porque la configuración del provider helm referencia salidas de `module.cluster`. Esas
referencias forman un grafo de dependencias que Terraform recorre en orden.
</details>

<details><summary>3. ¿Por qué no se sube <code>terraform.tfstate</code> a Git pero sí <code>.terraform.lock.hcl</code>?</summary>

El state contiene datos sensibles y cambia en cada apply (conflictos si varios lo editan); va en
un backend remoto con bloqueo. El lock file solo fija versiones de providers para que todos usen
las mismas: es código y se versiona.
</details>

<details><summary>4. ¿Qué diferencia hay entre un módulo y un provider?</summary>

El provider es un plugin que sabe hablar con una API (kind, helm, AWS). El módulo es una
agrupación reutilizable de **tu** código HCL (recursos + variables + outputs).
</details>

<details><summary>5. ¿Por qué en este lab Terraform instala ArgoCD pero NO despliega la API?</summary>

Separación de responsabilidades: Terraform gestiona la plataforma, que cambia poco. La app cambia
en cada commit y la gestiona GitOps (ArgoCD), que reconcilia continuamente, no solo cuando
alguien ejecuta `apply`.
</details>

## Retos
1. Añade un nodo `worker` al clúster en el módulo (otro bloque `node { role = "worker" }`).
2. Instala `ingress-nginx` con otro `helm_release` en un módulo nuevo y publica la API por Ingress.
3. Crea la `Application` de ArgoCD desde Terraform con un segundo `helm_release` del chart
   `argocd-apps` (mismo repositorio de argo-helm).
4. Mueve el state a un backend remoto (p. ej. un bucket gratuito de Terraform Cloud).
5. Añade `tflint` al workflow `terraform.yml`.

## Problemas comunes
- **`kind` falla al crear:** Docker Desktop no está corriendo o tiene poca memoria.
- **Puerto 30080 ocupado:** cambia `app_node_port` (y el `nodePort` del Service en `k8s/base/api.yaml`).
- **Timeout del helm_release:** primera descarga lenta de imágenes; vuelve a ejecutar `apply`.
