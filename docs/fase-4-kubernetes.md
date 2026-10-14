# Fase 4 — Orquestación con Kubernetes

**Objetivo:** desplegar SQL Server, las migraciones y la API en el clúster **a mano** con
`kubectl` + Kustomize, para entender cada objeto antes de automatizarlo con ArgoCD.

---

## 4.1 Conceptos

### Para qué sirve un orquestador
Docker Compose ejecuta contenedores en **una** máquina y si uno muere, nadie lo vigila de verdad.
Kubernetes gestiona contenedores en **muchas** máquinas: decide dónde ponerlos, los reinicia si
fallan, los escala, los actualiza sin cortes y les da red y almacenamiento.

### Arquitectura (lo mínimo que debes visualizar)
```
          kubectl ──HTTP──► API Server ◄── todo pasa por aquí
                              │   └─ etcd: base de datos con el estado deseado y actual
             ┌────────────────┼─────────────────┐
         Scheduler     Controller Manager     (Control plane)
       "¿en qué nodo?"  "bucles de reconciliación"
                              │
                 ┌────────────┴────────────┐
               Nodo: kubelet + runtime  ...  Nodo           (Workers)
               arranca los contenedores de los Pods asignados
```
**El bucle de reconciliación** es la idea central: cada *controller* observa un tipo de objeto y
compara *deseado* (`spec`) vs *actual* (`status`); si difieren, actúa. `kubectl apply` solo
escribe el deseado en etcd; el resto lo hacen los controllers.

### Objetos usados en el lab
| Objeto | En el lab | Explicación |
|---|---|---|
| **Pod** | (creados por otros) | Unidad mínima: 1+ contenedores que comparten red (misma IP) y volúmenes. Efímero |
| **Deployment** | `lab-api` | Mantiene N réplicas idénticas y sin estado. Crea un **ReplicaSet** por versión; el rolling update pasa pods de uno a otro |
| **StatefulSet** | `sqlserver` | Como Deployment pero con identidad estable (`sqlserver-0`) y **un disco propio por réplica** (`volumeClaimTemplates`) |
| **Service** | `sqlserver`, `lab-api` | IP y nombre DNS estables delante de pods cambiantes. Elige pods por **labels** (`selector`) |
| **ConfigMap / Secret** | `app-config`, `mssql-secret` | Configuración inyectada como variables. Un Secret solo está en **base64**, no cifrado |
| **PVC / PV / StorageClass** | `data-sqlserver-0` | El PVC *pide* disco; la StorageClass (`standard` en kind) crea el PV automáticamente |
| **Job** | `liquibase-migrate` | Ejecuta pods **hasta completar** (código 0), con reintentos (`backoffLimit`) |
| **initContainer** | `create-db` | Corre antes que los contenedores principales; si falla, el principal no arranca |
| **Namespace** | `lab`, `argocd` | Partición lógica del clúster (nombres, permisos, cuotas) |

### Labels y selectors: el "pegamento"
Nada en Kubernetes se referencia por nombre de pod. El Service `lab-api` envía tráfico a
**cualquier pod con `app: lab-api` que esté Ready**. El Deployment gestiona los pods que cumplen
su `selector`. Si entiendes esto, entiendes cómo se conecta todo.

### Probes
- **liveness** (`/health`): si falla, kubelet **reinicia** el contenedor.
- **readiness** (`/ready`): si falla, el pod se **saca del Service** (no recibe tráfico) pero no se reinicia.
- Por eso `/health` no toca la BD: si la BD cae, no quieres reiniciar todos los pods en bucle,
  solo dejar de enviarles tráfico.

### Requests y limits
- `requests`: lo que el scheduler **reserva** para elegir nodo.
- `limits`: el máximo. Si se supera la memoria → el contenedor muere con `OOMKilled`.

### Tipos de Service
`ClusterIP` (solo interno, por defecto — usado por `sqlserver`), `NodePort` (abre un puerto
30000–32767 en cada nodo — usado por `lab-api` y mapeado a tu `localhost` por kind),
`LoadBalancer` (IP externa en la nube).

### Kustomize: base + overlays
Kustomize (integrado en `kubectl -k`) personaliza YAML **sin plantillas**:
- `base/`: manifiestos comunes a todos los entornos.
- `overlays/<entorno>/`: referencia la base y aplica cambios: namespace, tags de imagen
  (`images:`), parches (`patches:`).
`kubectl kustomize k8s/overlays/local` muestra el YAML final sin aplicarlo.

> Las anotaciones `argocd.argoproj.io/*` de los manifiestos se ignoran en esta fase: solo las
> interpreta ArgoCD (fase 5).

---

## 4.2 Práctica (despliegue manual con imágenes locales)

Requisito: clúster de la fase 3 y `$env:KUBECONFIG` apuntando a él.

```powershell
cd devops-lab
# 1. Construir imágenes en tu PC
docker build -t lab-api:local app
docker build -t lab-liquibase:local liquibase

# 2. Cargarlas dentro del nodo kind (no existen en ningún registro)
kind load docker-image lab-api:local lab-liquibase:local --name lab

# 3. Ver el YAML final que generará Kustomize
kubectl kustomize k8s/overlays/local

# 4. Aplicar
kubectl apply -k k8s/overlays/local

# 5. Observar cómo converge (Ctrl+C para salir)
kubectl get pods -n lab -w
```

Verás: `sqlserver-0` arrancando; el Job reintentando en el initContainer hasta que SQL Server
responde; la API en `0/1 Ready` hasta que las tablas existen; finalmente `1/1`.

```powershell
curl.exe http://localhost:30080/ready
curl.exe http://localhost:30080/products
```

Comandos que debes dominar:

```powershell
kubectl get all -n lab
kubectl describe pod -n lab -l app=lab-api        # eventos: muy útil para depurar
kubectl logs -n lab job/liquibase-migrate -c create-db
kubectl logs -n lab job/liquibase-migrate -c liquibase
kubectl get endpoints lab-api -n lab               # IPs de pods Ready detrás del Service
kubectl get pvc,pv -n lab
kubectl exec -it -n lab sqlserver-0 -- bash
kubectl port-forward -n lab svc/sqlserver 14333:1433   # SQL Server en localhost:14333 desde tu cliente
```

---

## 4.3 Experimentos

1. **Autorreparación:** `kubectl delete pod -n lab -l app=lab-api` y mira cómo aparece otro.
2. **Escalado:** `kubectl scale deploy/lab-api -n lab --replicas=3`, luego
   `kubectl get endpoints lab-api -n lab`.
3. **Readiness vs liveness:** `kubectl scale statefulset/sqlserver -n lab --replicas=0`. Los pods
   de la API pasan a `0/1` (readiness falla) pero **no se reinician** (`RESTARTS` no sube).
   Vuelve a `--replicas=1`: el disco persistió, los datos siguen.
4. **Rolling update:** `kubectl set env deploy/lab-api -n lab APP_VERSION=v2` y observa
   `kubectl rollout status deploy/lab-api -n lab`. Luego `kubectl rollout undo deploy/lab-api -n lab`.
5. **OOMKilled:** cambia el límite de memoria de la API a `20Mi` en un parche del overlay local,
   aplica y mira `kubectl describe pod`.
6. **Secret no es cifrado:**
   `kubectl get secret mssql-secret -n lab -o jsonpath='{.data.MSSQL_SA_PASSWORD}'` y decodifícalo
   con `[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('...'))`.
7. **Job inmutable:** cambia `args` del Job y aplica de nuevo → error, porque el `template` de un
   Job no se puede modificar. Bórralo (`kubectl delete job ...`) y aplica. (ArgoCD lo resuelve con
   `hook-delete-policy`.)

Limpieza antes de la fase 5 (para que ArgoCD empiece de cero):

```powershell
kubectl delete -k k8s/overlays/local
```

---

## Autoevaluación

<details><summary>1. ¿Qué diferencia hay entre Deployment y StatefulSet y por qué SQL Server usa el segundo?</summary>

El Deployment trata las réplicas como intercambiables (nombres aleatorios, disco compartido o
ninguno). El StatefulSet da nombre estable y un PVC propio por réplica que lo sigue aunque el pod
se recree. Una BD necesita conservar *su* disco.
</details>

<details><summary>2. Un pod de la API está Running pero el Service no le envía tráfico. ¿Qué revisas?</summary>

Que esté **Ready** (readinessProbe), que sus labels coincidan con el `selector` del Service y
`kubectl get endpoints lab-api`. En este lab, la causa típica es que `/ready` falla porque las
migraciones no corrieron.
</details>

<details><summary>3. ¿Por qué <code>/health</code> no consulta la base de datos?</summary>

Porque es la liveness probe: si dependiera de la BD, una caída de la BD haría que Kubernetes
reiniciara todos los pods de la API en bucle sin arreglar nada.
</details>

<details><summary>4. ¿Quién crea realmente los pods cuando haces <code>kubectl apply</code> de un Deployment?</summary>

`kubectl` solo guarda el Deployment en el API server/etcd. El controller de Deployments crea un
ReplicaSet; el controller de ReplicaSets crea los Pods; el scheduler les asigna nodo; el kubelet
del nodo arranca los contenedores.
</details>

<details><summary>5. ¿Qué aporta Kustomize frente a copiar los YAML por entorno?</summary>

Una sola fuente (base) y diferencias explícitas por entorno (overlays). Cambiar algo común se hace
una vez, y el overlay muestra claramente qué es distinto en cada ambiente.
</details>

<details><summary>6. ¿Cómo se entera la API de la dirección de SQL Server?</summary>

Por la variable `DB_HOST=sqlserver` del ConfigMap. `sqlserver` es el nombre del Service; el DNS
del clúster (CoreDNS) lo resuelve a su ClusterIP, que reenvía a `sqlserver-0`.
</details>

## Retos
1. Crea `overlays/qa` con 2 réplicas, otro namespace y un `ConfigMap` distinto.
2. Añade un `HorizontalPodAutoscaler` para la API (requiere instalar metrics-server).
3. Añade un `PodDisruptionBudget` y una `NetworkPolicy` que solo permita a `lab-api` y al Job
   hablar con `sqlserver`.
4. Haz que la API corra con `securityContext` `readOnlyRootFilesystem: true` y `runAsNonRoot: true`.
