# Fase 6 — Automatización con GitHub Actions (cerrando el ciclo)

**Objetivo:** que un `git push` pruebe, construya, valide migraciones contra Oracle 11g y SQL
Server reales, publique imágenes y deje el despliegue listo para que ArgoCD lo aplique.

---

## 6.1 Conceptos

### Vocabulario
| Término | Significado | Ejemplo en el lab |
|---|---|---|
| **Workflow** | Archivo YAML en `.github/workflows/` | `ci-app.yml` |
| **Evento (trigger)** | Qué lo dispara | `push` a `main`, `pull_request`, `workflow_dispatch` (botón manual), `workflow_call` |
| **Filtro de rutas** | Solo dispara si cambian ciertos archivos | `paths: ["app/**"]` |
| **Job** | Conjunto de pasos en **una máquina nueva** (runner). Los jobs corren en paralelo salvo que uses `needs` | `test`, `build-push` |
| **Step** | Comando (`run`) o acción reutilizable (`uses`) | `uses: actions/checkout@v4` |
| **Runner** | VM efímera que ejecuta el job (`ubuntu-latest`) con Docker preinstalado | — |
| **Action** | Paquete reutilizable publicado por terceros | `docker/build-push-action@v6` |
| **Contexto / expresión** | Datos del evento y del entorno con `${{ }}` | `${{ github.sha }}`, `${{ needs.build-push.outputs.tag }}` |
| **Outputs** | Pasar datos entre steps (`$GITHUB_OUTPUT`) y entre jobs (`outputs:`) | el tag `sha-xxxxxxx` |
| **Service containers** | Contenedores auxiliares (BD) vivos durante el job | SQL Server y Oracle 11g en `db-migrations` |
| **Artifacts** | Archivos que el job guarda para descargar luego | `preview-sqlserver` (SQL de `update-sql`) |
| **Cache** | Reutilizar dependencias entre ejecuciones | caché de pip y de capas Docker (`type=gha`) |
| **Reusable workflow** | Workflow invocable desde otros (`workflow_call`) | `gitops-bump.yml` |
| **Concurrency** | Serializa ejecuciones de un mismo grupo | evita dos pushes de bump simultáneos |
| **`GITHUB_TOKEN`** | Token temporal creado por ejecución | login a GHCR y push del bump |
| **`permissions`** | Qué puede hacer ese token (mínimo privilegio) | `packages: write` solo en `build-push` |

### Detalles finos que conviene entender
- Cada job empieza en una **máquina limpia**: por eso cada job hace `checkout` de nuevo.
- Un push hecho con `GITHUB_TOKEN` **no dispara otros workflows**: evita el bucle
  "CI hace commit → CI se dispara → hace commit…".
- `${GITHUB_REPOSITORY_OWNER,,}` es sintaxis de bash para minúsculas: GHCR no acepta mayúsculas.
- En `pull_request` no se publican imágenes (`if: github.event_name != 'pull_request'`): un PR
  debe poder probarse sin efectos secundarios.

---

## 6.2 Los cuatro workflows

### `ci-app.yml`
```
test (pytest) ──► build-push (imagen ghcr.io/<owner>/lab-api:sha-xxxxxxx) ──► deploy-dev (llama a gitops-bump)
```

### `db-migrations.yml`
```
sqlserver  ┐  validate → update-sql (artefacto) → update → rollback → update → history
oracle11g  ┘  (en paralelo, cada uno con su BD real como service container)
      └──► publish (imagen lab-liquibase) ──► deploy-dev (gitops-bump)
```
El valor didáctico: **cada PR prueba que los rollbacks funcionan** contra motores reales,
incluido Oracle 11g. El rollback que nadie probó es el que falla en producción.

### `gitops-bump.yml` (reutilizable)
Ejecuta `kustomize edit set image lab-api=ghcr.io/<owner>/lab-api:sha-xxxxxxx` en
`k8s/overlays/dev` y hace commit + push. **Ese commit es el despliegue.** ArgoCD lo detecta.

### `terraform.yml`
- En PR/push: `fmt -check`, `init -backend=false`, `validate`.
- Manual con `e2e = true`: crea el clúster kind + ArgoCD **en el runner**, verifica y destruye.
  Demuestra que tu IaC funciona en una máquina que no es la tuya.

---

## 6.3 El flujo completo de extremo a extremo

```
1. git checkout -b feature/version-endpoint
2. cambias app/app.py  → git push → abres PR
3. PR: ci-app ejecuta solo "test"                         (sin publicar nada)
4. merge a main
5. ci-app: test → build-push (lab-api:sha-abc1234) → gitops-bump
6. gitops-bump: commit "deploy(dev): lab-api sha-abc1234" en k8s/overlays/dev
7. ArgoCD (≤60 s): detecta el commit → wave 0 → Job Liquibase (wave 1) → API nueva (wave 2)
8. curl localhost:30080/health  →  "version": "sha-abc1234"
```

---

## 6.4 Práctica

1. **Configura el repo** (una vez): Settings → Actions → General → *Workflow permissions*: deja
   "Read repository contents" (los workflows piden los permisos extra explícitamente con
   `permissions:`). Opcional: Settings → Branches → regla para `main` que exija que pasen `test`,
   `sqlserver` y `oracle11g` antes de mergear. **Ojo:** si la regla bloquea pushes directos a
   `main`, el bot de `gitops-bump` tampoco podrá pushear; en ese caso deja la regla sin
   "Restrict pushes" o haz el reto de que el bump abra un PR.

2. **Cambio de app** (sigue el flujo 6.3):
   ```powershell
   git checkout -b feature/saludo
   # añade en app/app.py un endpoint GET /version que devuelva APP_VERSION
   # añade su test en app/tests/test_app.py
   git commit -am "feat: endpoint /version"; git push -u origin feature/saludo
   gh pr create --fill          # o desde la web
   ```
   Observa la pestaña *Checks* del PR. Mergea. Observa Actions, luego `git pull` (verás el
   commit del bot) y ArgoCD.

3. **Cambio de esquema:** crea el changeset `005-create-orders.sql` (reto de la fase 2) en una
   rama, abre PR y descarga el artefacto `preview-sqlserver` para revisar el SQL. Mergea y mira
   cómo el Job de Liquibase lo aplica en el clúster.

4. **Terraform e2e:** Actions → terraform → *Run workflow* → marca `e2e`.

Comandos útiles con `gh`:
```powershell
gh run list
gh run watch
gh run view --log-failed
gh workflow run terraform.yml -f e2e=true
```

---

## 6.5 Experimentos
1. Rompe un test y abre PR: el job `build-push` ni siquiera aparece (`needs` + `if`).
2. Escribe un changeset en SQL Server sin `--rollback`: `rollback-count` falla en CI. Aprende por
   qué el pipeline exige rollbacks.
3. Quita `packages: write` de `build-push` y observa el error 403 al publicar en GHCR.
4. Lanza dos merges seguidos: `concurrency` hace que el segundo bump espere al primero.
5. Elimina la caché (`cache-from`/`cache-to`) y compara tiempos de build.

---

## Autoevaluación

<details><summary>1. ¿Por qué el tag de la imagen es el SHA del commit y no solo <code>latest</code>?</summary>

Porque es inmutable y trazable: sabes exactamente qué commit corre en el clúster, y Git registra
el cambio de tag (ArgoCD necesita que el manifiesto **cambie** para desplegar; con `latest` el
manifiesto nunca cambiaría).
</details>

<details><summary>2. ¿Por qué los pasos de Liquibase en CI usan <code>--network host</code>?</summary>

Los service containers publican sus puertos en el runner (`ports: 1433:1433`). El contenedor de
Liquibase, con red del host, llega a ellos por `localhost`.
</details>

<details><summary>3. El commit del bot modifica el repo. ¿Por qué no dispara de nuevo <code>ci-app</code>?</summary>

Por dos razones: los eventos generados con `GITHUB_TOKEN` no disparan workflows, y además el
cambio está en `k8s/`, fuera del filtro `paths: app/**`.
</details>

<details><summary>4. ¿Qué ventaja tiene <code>gitops-bump.yml</code> como workflow reutilizable?</summary>

La lógica del despliegue (editar tag, commit, push, concurrencia) está en un solo lugar y la usan
tanto `ci-app` como `db-migrations`. Un cambio ahí aplica a ambos.
</details>

<details><summary>5. ¿Dónde están las credenciales del clúster en GitHub?</summary>

En ninguna parte. GitHub solo escribe en el repo y en GHCR. ArgoCD, dentro del clúster, tira de
ellos. Esa es la ventaja de seguridad del modelo pull.
</details>

<details><summary>6. ¿Qué pasa si <code>oracle11g</code> falla pero <code>sqlserver</code> pasa en un push a main?</summary>

`publish` depende de ambos (`needs: [sqlserver, oracle11g]`), así que no se publica la imagen de
Liquibase ni se hace el bump: nada llega al clúster.
</details>

## Retos
1. Añade una **matriz** en `test` para probar la app con Python 3.11 y 3.12.
2. Añade un escaneo de vulnerabilidades de la imagen con `aquasecurity/trivy-action` y haz que
   falle con severidad `CRITICAL`.
3. Crea un entorno `prod` (GitHub **Environments**) con aprobación manual: un workflow que, tras
   aprobación, haga el bump en `k8s/overlays/prod`.
4. Haz que `db-migrations` comente en el PR el contenido de `update-sql` (con `gh pr comment`).
5. Usa `lb status --verbose` con `continue-on-error` para mostrar en el resumen del job
   (`$GITHUB_STEP_SUMMARY`) qué changesets están pendientes.

## Problemas comunes
- **403 al publicar en GHCR:** falta `packages: write` o el paquete ya existe ligado a otro repo.
- **El bump falla con "rejected":** otro push llegó antes; el `git pull --rebase` lo resuelve, si
  persiste revisa la protección de rama (el bot debe poder pushear a `main`, o cambia el bump
  para abrir un PR).
- **Oracle service unhealthy en CI:** falta `--shm-size 1g` o aumenta `--health-retries`.
- **ArgoCD no ve el cambio:** pulsa *Refresh* o revisa que `targetRevision`/`path` sean correctos.
