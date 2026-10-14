# Fase 0 — Prerrequisitos y mapa mental

## 0.1 El problema que resuelve todo este ecosistema

Imagina el flujo "a mano" de un equipo: alguien instala SQL Server en un servidor, otro ejecuta
scripts `.sql` sueltos en orden "de memoria", un tercero copia la app por FTP y la reinicia.
Problemas: nadie sabe qué versión del esquema tiene cada ambiente, los servidores son distintos
entre sí ("en mi máquina funciona"), y desplegar da miedo.

Cada herramienta del laboratorio ataca una parte de ese problema con la **misma idea de fondo:
describir el estado deseado en archivos de texto versionados en Git** y dejar que una herramienta
lo haga realidad.

| Capa | Pregunta que responde | Herramienta | "Estado deseado" escrito en |
|---|---|---|---|
| Infraestructura | ¿Qué servidores/clústeres existen? | Terraform | `*.tf` |
| Empaquetado | ¿Cómo se ejecuta mi app igual en todas partes? | Docker | `Dockerfile` |
| Entorno local | ¿Cómo levanto app + BDs juntas en mi PC? | Docker Compose | `docker-compose.yml` |
| Esquema de BD | ¿Qué versión del esquema tiene cada BD? | Liquibase | changelogs |
| Ejecución | ¿Cuántas copias corren, cómo se recuperan de fallos? | Kubernetes | manifiestos YAML |
| Entrega | ¿Cómo llega lo que está en Git al clúster? | ArgoCD | `Application` + carpeta `k8s/` |
| Automatización | ¿Quién prueba, construye y publica en cada cambio? | GitHub Actions | `.github/workflows/*.yml` |

### Dos conceptos transversales que verás en TODAS las fases

1. **Declarativo vs imperativo.**
   - Imperativo: "ejecuta `CREATE TABLE`, luego `docker run`, luego…" (tú decides los pasos).
   - Declarativo: "quiero que exista esto" (la herramienta calcula los pasos comparando lo que hay
     con lo que pides). Terraform, Kubernetes, Compose y ArgoCD son declarativos.
     Liquibase es un híbrido: tú escribes los pasos (changesets), pero él decide **cuáles faltan**.
2. **Reconciliación / idempotencia.** Ejecutar la herramienta dos veces con el mismo archivo deja
   el sistema igual. `terraform apply`, `kubectl apply`, `liquibase update`, `docker compose up`
   son idempotentes. Si entiendes esto, entiendes por qué estas herramientas son seguras de
   automatizar.

## 0.2 Instalación (Windows 11)

Tu equipo hoy no tiene Docker, Terraform, kubectl ni kind. Instálalos con `winget` desde PowerShell:

```powershell
winget install -e --id Docker.DockerDesktop      # incluye docker compose. Requiere WSL2 y reinicio
winget install -e --id Hashicorp.Terraform
winget install -e --id Kubernetes.kubectl
winget install -e --id Kubernetes.kind
winget install -e --id Kubernetes.kustomize      # opcional (kubectl ya trae `kubectl kustomize`)
winget install -e --id argoproj.argocd           # CLI de ArgoCD, opcional
winget install -e --id GitHub.cli                # opcional, para gestionar el repo/Actions
```

Cierra y vuelve a abrir la terminal, luego verifica:

```powershell
docker version; docker compose version
terraform version
kubectl version --client
kind version
```

**Memoria para Docker (WSL2):** el laboratorio necesita al menos **6 GB** (SQL Server ~2 GB,
Oracle XE ~1 GB, clúster kind ~2 GB). Con el backend WSL2, Docker Desktop **no** muestra el control
de memoria en *Settings → Resources*: el límite se define en WSL. Por defecto WSL2 puede usar el
50 % de la RAM del equipo; para fijar un límite explícito crea `%USERPROFILE%\.wslconfig`:

```ini
[wsl2]
memory=10GB
processors=8
swap=4GB
```

Luego cierra Docker Desktop, ejecuta `wsl --shutdown`, vuelve a abrirlo y verifica con
`docker info --format "{{.MemTotal}}"`.

## 0.3 Preparar el repositorio

```powershell
cd "E:\GESTION DE ARCHIVOS\DOCUMENTACION\MISPROYECTOS\Laboratorio\devops-lab"
Copy-Item .env.example .env
git init -b main
git add .; git commit -m "chore: laboratorio inicial"
```

Crea un repositorio **público** en GitHub llamado `devops-lab` (público simplifica que ArgoCD lea
el repo y que el clúster descargue imágenes de GHCR sin credenciales) y súbelo:

```powershell
git remote add origin https://github.com/TU_USUARIO/devops-lab.git
git push -u origin main
```

Reemplaza `TU_USUARIO` en `argocd/application.yaml` y `k8s/overlays/dev/kustomization.yaml`
(en minúsculas).

## Autoevaluación

<details><summary>1. ¿Por qué decimos que Kubernetes es "declarativo"? Da un ejemplo del laboratorio.</summary>

Porque no le dices "arranca un contenedor", le dices "quiero 2 réplicas de `lab-api`"
(`replicas: 2`). Kubernetes compara continuamente lo que existe con lo pedido; si un pod muere,
crea otro sin que nadie ejecute un comando.
</details>

<details><summary>2. ¿Qué significa que `liquibase update` sea idempotente y por qué importa en CI/CD?</summary>

Que si lo ejecutas 10 veces, solo aplica los changesets que faltan (los demás ya están en la
tabla `DATABASECHANGELOG`). Importa porque el pipeline puede ejecutarlo en cada despliegue sin
miedo a duplicar tablas o datos.
</details>

<details><summary>3. ¿Qué capa del ecosistema resolvería "el servidor de QA tiene una columna que producción no tiene"?</summary>

Liquibase: cada BD registra qué changesets tiene aplicados, y `liquibase status` / `diff` muestran
la diferencia. Además, si todos los cambios pasan por changelogs, la desviación (drift) no ocurre.
</details>
