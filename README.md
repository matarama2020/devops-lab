# DevOps Lab — Pruebas de concepto integradas

Laboratorio práctico y pequeño para dominar, **una herramienta a la vez y luego todas juntas**:

| Herramienta | Qué practicas aquí |
|---|---|
| **Docker Compose** | Levantar API + SQL Server 2022 + Oracle XE 11g en local |
| **Liquibase** | Migraciones versionadas, rollback, contexts y labels en **SQL Server** y **Oracle 11g** |
| **Terraform** | Crear un clúster Kubernetes local (kind) e instalar ArgoCD con Helm, usando módulos |
| **Kubernetes** | Deployment, StatefulSet, Service, Secret, Job, probes y Kustomize (base/overlays) |
| **ArgoCD** | GitOps: el clúster se sincroniza solo con lo que hay en Git (sync waves + hooks) |
| **GitHub Actions** | CI de la app, validación de migraciones contra BD reales, validación de Terraform y "image bump" GitOps |

## Arquitectura

```
                         ┌──────────────────── GitHub ─────────────────────┐
  git push ───────────►  │  repo devops-lab                                 │
                         │   ├─ app/        ──► Actions: test + build ──► GHCR (lab-api:sha)
                         │   ├─ liquibase/  ──► Actions: migrar contra SQL Server y Oracle 11g
                         │   ├─ terraform/  ──► Actions: fmt + validate
                         │   └─ k8s/        ◄── Actions: commit "image tag = sha" (GitOps)
                         └───────────────────────────┬─────────────────────┘
                                                     │ ArgoCD observa k8s/overlays/dev
  Tu PC                                              ▼
  ┌─ Terraform ─► kind cluster ─────────────────────────────────────────────┐
  │                ├─ namespace argocd: ArgoCD (Helm)                        │
  │                └─ namespace lab:                                         │
  │                     wave 0: SQL Server (StatefulSet + PVC)               │
  │                     wave 1: Job Liquibase (hook) → crea BD y migra       │
  │                     wave 2: lab-api (Deployment) → NodePort 30080        │
  └──────────────────────────────────────────────────────────────────────────┘
  ┌─ Docker Compose (desarrollo local) ─────────────────────────────────────┐
  │   sqlserver:1433   oracle(11g XE):1521   api:8080   liquibase-* (perfil) │
  └──────────────────────────────────────────────────────────────────────────┘
```

> Oracle 11g se usa como **sistema legado**: solo se gestiona con Liquibase (Compose y CI).
> La API usa SQL Server. Así practicas migraciones en ambos motores sin cargar el clúster
> con un Oracle de 2 GB.

## Fases (hazlas en orden)

| Fase | Documento | Resultado verificable |
|---|---|---|
| 0 | [docs/fase-0-prerequisitos.md](docs/fase-0-prerequisitos.md) | Herramientas instaladas |
| 1 | [docs/fase-1-docker-compose.md](docs/fase-1-docker-compose.md) | `curl localhost:8080/health` responde |
| 2 | [docs/fase-2-liquibase.md](docs/fase-2-liquibase.md) | Tablas creadas y rollback probado en ambos motores |
| 3 | [docs/fase-3-terraform.md](docs/fase-3-terraform.md) | Clúster kind + ArgoCD creados con `terraform apply` |
| 4 | [docs/fase-4-kubernetes.md](docs/fase-4-kubernetes.md) | App corriendo en el clúster (despliegue manual) |
| 5 | [docs/fase-5-argocd.md](docs/fase-5-argocd.md) | El clúster se sincroniza desde Git |
| 6 | [docs/fase-6-github-actions.md](docs/fase-6-github-actions.md) | Un `git push` termina desplegado en el clúster |

Cada fase termina con **Retos** para practicar más allá del ejemplo.

## Estructura

```
devops-lab/
├─ app/                     API Flask (productos) + Dockerfile + tests
├─ liquibase/
│  ├─ Dockerfile            Imagen Liquibase con driver Oracle compatible con 11g + changelogs
│  └─ changelog/
│     ├─ sqlserver/         changelog master (YAML) + changesets en SQL formateado
│     └─ oracle/            changelog master (YAML) + changesets YAML y SQL (secuencia+trigger)
├─ docker-compose.yml
├─ terraform/
│  ├─ main.tf …             raíz: providers y llamada a módulos
│  └─ modules/{kind-cluster,argocd}
├─ k8s/
│  ├─ base/                 manifiestos genéricos
│  └─ overlays/dev/         parches y tag de imagen (lo edita el CI)
├─ argocd/application.yaml
└─ .github/workflows/       ci-app, db-migrations, terraform
```

## Credenciales de laboratorio

Todas las contraseñas están en `.env.example` y en `k8s/base/sqlserver-secret.yaml`.
**Son solo para práctica local**; en la fase 5 hay un reto para reemplazarlas por Sealed Secrets.
