# Fase 5 — GitOps con ArgoCD

**Objetivo:** que el clúster se despliegue **solo** a partir de lo que hay en Git, en el orden
correcto (BD → migraciones → API), y que se corrija solo si alguien lo modifica a mano.

---

## 5.1 Conceptos

### Qué es GitOps
Un modelo operativo con cuatro principios (OpenGitOps):
1. **Declarativo**: el sistema se describe con manifiestos (los de `k8s/`).
2. **Versionado e inmutable**: ese estado vive en Git → historial, revisión por PR, auditoría.
3. **Pull automático**: un agente *dentro* del clúster descarga el estado deseado.
4. **Reconciliación continua**: el agente corrige cualquier diferencia, siempre.

### Push vs Pull
- **Push (CI clásico)**: el pipeline ejecuta `kubectl apply` contra el clúster → el CI necesita
  credenciales de administrador del clúster y, si alguien cambia algo a mano, nadie lo nota.
- **Pull (GitOps)**: el CI solo **escribe en Git**; ArgoCD, dentro del clúster, lee Git y aplica.
  Las credenciales del clúster nunca salen de él. **Git es la única fuente de verdad** y un
  rollback es un `git revert`.

### Componentes de ArgoCD
| Componente | Función |
|---|---|
| `argocd-repo-server` | Clona el repo y **renderiza** manifiestos (Kustomize, Helm, YAML plano) |
| `argocd-application-controller` | Compara lo renderizado con el clúster (diff) y sincroniza |
| `argocd-server` | API + interfaz web + CLI |
| `argocd-redis` | Caché |

### El objeto `Application` (`argocd/application.yaml`)
Responde tres preguntas: **de dónde** (`source`: repo, rama, carpeta), **a dónde**
(`destination`: clúster y namespace) y **cómo** (`syncPolicy`).
- `automated`: sincroniza sin intervención cuando Git cambia.
- `prune: true`: si borras un manifiesto de Git, borra el objeto del clúster.
- `selfHeal: true`: si alguien hace `kubectl edit`, lo revierte al estado de Git.
- `CreateNamespace=true`: crea `lab` si no existe.
- `finalizers`: borrar la Application borra también sus recursos.

### Dos estados distintos: Sync y Health
- **Sync status**: ¿el clúster coincide con Git? → `Synced` / `OutOfSync`.
- **Health status**: ¿lo desplegado funciona? → `Healthy` / `Progressing` / `Degraded` / `Missing`.
Puedes estar `Synced` y `Degraded` (lo que pediste está aplicado, pero los pods fallan).

### Orden de despliegue: sync waves y hooks
Una sincronización tiene fases: **PreSync → Sync → PostSync** (y `SyncFail` si algo falla).
Dentro de cada fase, los recursos se aplican por **olas** (`sync-wave`, de menor a mayor) y
ArgoCD **espera a que una ola esté Healthy** antes de la siguiente:

```
wave 0: Secret, ConfigMap, Service y StatefulSet sqlserver  → espera readiness de SQL Server
wave 1: Job liquibase-migrate (hook Sync)                    → espera a que termine OK
wave 2: Deployment lab-api                                   → solo si las migraciones pasaron
```

¿Por qué el Job es un **hook** y no un recurso normal? Porque un Job es inmutable y "se completa
una vez"; como hook, ArgoCD lo **recrea en cada sincronización** (`BeforeHookCreation` borra el
anterior). Así cada despliegue ejecuta `liquibase update`, que es idempotente.
¿Por qué `Sync` y no `PreSync`? En el primer despliegue, PreSync correría antes de que exista
SQL Server (que está en la fase Sync) y fallaría.

---

## 5.2 Práctica

### Requisitos previos
1. El repo está en GitHub (fase 0) y reemplazaste `TU_USUARIO` en `argocd/application.yaml`.
2. Tu primer `push` ya ejecutó los workflows `ci-app` y `db-migrations` (pestaña **Actions**):
   publicaron `lab-api` y `lab-liquibase` en GHCR e hicieron commits `deploy(dev): ...` que
   actualizan `k8s/overlays/dev/kustomization.yaml`. Haz `git pull` para verlos.
   Si fallaron, revisa la fase 6 y vuelve.
3. En GitHub → tu perfil → **Packages** → cada paquete → *Package settings* → **Change visibility
   → Public** (para que el clúster pueda descargarlas sin credenciales).
4. Limpiaste el despliegue manual de la fase 4.

### Entrar a ArgoCD
```powershell
$env:KUBECONFIG = (terraform -chdir=terraform output -raw kubeconfig_path)
$b64 = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))     # contraseña de admin
kubectl port-forward -n argocd svc/argocd-server 8081:80
```
Abre http://localhost:8081 (usuario `admin`). Deja esa terminal abierta.

### Registrar la aplicación (el único `kubectl apply` "manual" de GitOps)
```powershell
kubectl apply -f argocd/application.yaml
kubectl get applications -n argocd -w
```
En la interfaz, abre `lab-api` y observa el árbol: primero aparece `sqlserver`, luego el Job, al
final el Deployment. Cuando todo esté `Synced` + `Healthy`:
```powershell
curl.exe http://localhost:30080/products
```

Con el CLI (opcional):
```powershell
argocd login localhost:8081 --username admin --insecure
argocd app get lab-api
argocd app history lab-api
argocd app diff lab-api
```

---

## 5.3 Experimentos

1. **Self-heal:** `kubectl scale deploy/lab-api -n lab --replicas=5`. En segundos ArgoCD lo vuelve
   a 1 (lo que dice el overlay dev). Mira el evento en la UI.
2. **Cambio vía Git:** en `k8s/overlays/dev/kustomization.yaml` cambia `value: 1` por `value: 2`,
   haz commit y push. Espera ≤60 s (o pulsa *Refresh*). Despliegue sin tocar el clúster.
3. **Rollback GitOps:** `git revert HEAD` y push. Vuelve a 1 réplica. El historial de Git es tu
   historial de despliegues.
4. **Prune:** agrega un ConfigMap nuevo a `k8s/base`, push, verifícalo en el clúster; luego bórralo
   de Git y push. ArgoCD lo elimina.
5. **Migración que falla:** añade un changeset SQL inválido en `liquibase/changelog/sqlserver`,
   push. `db-migrations` debería fallar en el PR... pero si lo saltas y llega al clúster, el Job
   falla, la sincronización queda en `Failed` y **la API no se actualiza** (wave 2 nunca llega).
   Revierte el commit.
6. **Synced pero Degraded:** cambia en Git la imagen de la API a un tag inexistente. Estado:
   `Synced` + `Degraded` (`ImagePullBackOff`). Revierte.

---

## Autoevaluación

<details><summary>1. ¿Por qué se dice que en GitOps "el CI no despliega"?</summary>

Porque el CI solo construye la imagen y modifica Git (el tag en el overlay). Quien aplica en el
clúster es ArgoCD, que tira de Git. El CI ni siquiera necesita credenciales del clúster.
</details>

<details><summary>2. Alguien ejecuta <code>kubectl edit</code> en producción para "arreglar algo rápido". ¿Qué pasa con selfHeal activo y con él desactivado?</summary>

Activo: ArgoCD revierte el cambio al estado de Git (el arreglo se pierde; debe hacerse por Git).
Desactivado: el cambio queda, pero la app aparece `OutOfSync`, haciendo visible la desviación.
</details>

<details><summary>3. ¿Cómo garantiza este lab que la API nueva no arranque antes de que el esquema esté migrado?</summary>

Con sync waves: el Job de Liquibase (wave 1) debe completar con éxito antes de que ArgoCD aplique
el Deployment (wave 2). Si el Job falla, la sincronización se detiene. Además, la readinessProbe
`/ready` impide recibir tráfico si la BD no está lista.
</details>

<details><summary>4. ¿Qué diferencia hay entre "Synced" y "Healthy"?</summary>

Synced compara clúster vs Git (¿se aplicó lo pedido?). Healthy evalúa el estado de los recursos
(¿los pods están listos, el Job terminó, etc.?). Son independientes.
</details>

<details><summary>5. ¿Cómo haces rollback de un despliegue en GitOps?</summary>

`git revert` del commit que cambió el tag (o los manifiestos) y push. ArgoCD sincroniza a la
versión anterior. Existe `argocd app rollback`, pero con `automated` activo se desaconseja porque
Git volvería a imponer la versión nueva.
</details>

<details><summary>6. ¿Por qué el Job de migraciones es un hook con <code>BeforeHookCreation</code>?</summary>

Los Jobs son inmutables y se ejecutan una sola vez. Como hook, ArgoCD lo vuelve a crear en cada
sync (borrando el anterior antes), de modo que cada despliegue ejecuta `liquibase update`.
</details>

## Retos
1. Reemplaza `k8s/base/sqlserver-secret.yaml` por un **SealedSecret** (instala el controlador
   sealed-secrets con Helm desde Terraform y cifra el secreto con `kubeseal`).
2. Crea un `AppProject` que solo permita desplegar en el namespace `lab` desde tu repo.
3. Crea un overlay `qa` y un **ApplicationSet** que genere una Application por cada carpeta de
   `k8s/overlays/*`.
4. Patrón **App of Apps**: una Application raíz que despliega `argocd/` (incluida la propia `lab-api`).
5. Añade un hook `PostSync` que ejecute un smoke test (`curl` a `/ready`).
