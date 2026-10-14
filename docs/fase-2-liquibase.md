# Fase 2 — Migraciones con Liquibase (SQL Server y Oracle 11g)

**Objetivo:** versionar el esquema de dos motores distintos, aplicar, previsualizar, revertir y
entender cómo Liquibase sabe qué falta en cada base de datos.

---

## 2.1 Conceptos

### El problema
El código vive en Git con historial; la base de datos, no. Sin una herramienta, cada ambiente
(dev, QA, prod) acumula scripts aplicados a mano y nadie puede responder con certeza *"¿qué
versión del esquema tiene producción?"*.

### Vocabulario
| Término | Significado |
|---|---|
| **Changelog** | Archivo que lista los cambios en orden. Aquí: `db.changelog-master.yaml`, que *incluye* otros archivos |
| **Changeset** | Unidad atómica de cambio. Se identifica por **id + author + ruta del archivo** |
| **`DATABASECHANGELOG`** | Tabla que Liquibase crea en cada BD: una fila por changeset aplicado, con fecha, orden y **checksum (MD5)** |
| **`DATABASECHANGELOGLOCK`** | Candado: impide que dos `update` simultáneos (p. ej. dos pods) migren a la vez |
| **Change type** | Cambio abstracto en YAML/XML (`createTable`, `createSequence`…) que Liquibase traduce al SQL de cada motor |
| **Formatted SQL** | Archivo `.sql` con comentarios especiales (`--changeset`, `--rollback`). Tú escribes el SQL nativo |
| **Rollback** | Cómo deshacer un changeset. Automático para muchos change types; **obligatorio escribirlo** en SQL |
| **Context** | Filtro de *entorno*: `context:dev` solo corre con `--contexts=dev` (ej. datos de prueba) |
| **Label** | Filtro de *funcionalidad/versión*: `labels:v2` permite `--label-filter=v1` para desplegar solo v1 |
| **Precondition** | Condición previa; si falla puede `HALT`, `MARK_RAN`, `CONTINUE`, `WARN` |
| **Tag** | Marca en la historia (`tagDatabase`) para hacer `rollback --tag=v1.0` |

### Cómo decide Liquibase qué ejecutar (el algoritmo)
1. Toma el candado (`DATABASECHANGELOGLOCK`).
2. Lee el changelog completo **en orden**.
3. Por cada changeset calcula su identidad (id+author+archivo) y busca esa fila en `DATABASECHANGELOG`:
   - No existe → lo ejecuta y registra la fila con su checksum.
   - Existe y el checksum coincide → lo salta.
   - Existe y el checksum **no** coincide → **error de validación** (alguien editó un changeset ya
     aplicado), salvo que tenga `runOnChange:true` (se re-ejecuta) o se marque como `validCheckSum`.
4. Libera el candado.

> **Regla de oro:** nunca edites un changeset ya aplicado en algún ambiente. Si te equivocaste,
> crea uno nuevo que corrija.

### Particularidades de Oracle 11g (sistema legado)
- **Sin `IDENTITY`** (llegó en 12c): por eso `SEQ_CUSTOMERS` + trigger `TRG_CUSTOMERS_ID`.
- **Nombres de máximo 30 caracteres** (12.2+ permite 128).
- **PL/SQL** contiene `;` internos → `endDelimiter:/` y `splitStatements:false`.
- **Usuario = esquema**: al conectarte como `LAB`, las tablas se crean en el esquema `LAB`.
- **Driver JDBC**: Liquibase 4.29 trae ojdbc 23.x, que no certifica 11g. El `liquibase/Dockerfile`
  lo reemplaza por **ojdbc8 19.x**. Lección real: con bases legadas, la versión del driver importa.

### Particularidades de SQL Server
- Liquibase **no crea la base de datos**; por eso existe `sqlserver-init` (Compose) y el
  `initContainer` del Job (Kubernetes).
- Se conecta con `encrypt=true;trustServerCertificate=true` porque el certificado es autofirmado.

---

## 2.2 Lectura guiada de los changelogs

**SQL Server** (`liquibase/changelog/sqlserver/`): todo en *formatted SQL*.
- `001`/`002`: tablas con constraints **con nombre** (`pk_products`, `fk_products_category`).
  Nombrar constraints hace que los rollbacks y futuros `ALTER` sean predecibles.
- `003`: datos semilla con `context:dev`.
- `004`: añade `stock` (evolución "v2") con **precondición** `onFail:MARK_RAN`: si la columna ya
  existe (alguien la creó a mano), lo marca como ejecutado en vez de fallar. El rollback tiene
  dos líneas porque SQL Server exige borrar el DEFAULT antes que la columna.

**Oracle** (`liquibase/changelog/oracle/`): mezcla YAML y SQL.
- `001-customers.yaml`: `createSequence` y `createTable` abstractos → rollback automático.
- `002-customers-trigger.sql`: PL/SQL nativo con delimitador `/`.
- `003-seed-customers.yaml`: `insert` sin ID (lo pone el trigger), con rollback explícito.
- `tag-v1.0` en el master: punto de restauración.
- `004-customers-view.sql`: `runOnChange:true` → si editas la vista, se re-aplica.

**Configuración por variables de entorno** (`LIQUIBASE_COMMAND_URL`, `..._USERNAME`,
`..._PASSWORD`, `..._CHANGELOG_FILE`): la misma imagen funciona en Compose, en GitHub Actions y
en Kubernetes solo cambiando variables. Es el principio *12-factor: config en el entorno*.

---

## 2.3 Práctica

Define atajos en tu sesión de PowerShell:

```powershell
function lbs { docker compose --profile migrations run --rm liquibase-sqlserver @args }
function lbo { docker compose --profile migrations run --rm liquibase-oracle @args }
docker compose --profile migrations build      # construye lab-liquibase:local
```

### SQL Server
```powershell
lbs validate                       # ¿el changelog es correcto?
lbs status --verbose               # ¿qué changesets faltan?
lbs update-sql --contexts=dev      # PREVIEW: muestra el SQL sin ejecutarlo (léelo con calma)
lbs update --contexts=dev          # aplica
lbs history                        # qué se aplicó y cuándo
curl.exe http://localhost:8080/ready      # ahora sí: 200 "ready"
curl.exe http://localhost:8080/products
```

Inspecciona la tabla de control en tu cliente SQL:
```sql
SELECT ID, AUTHOR, FILENAME, ORDEREXECUTED, EXECTYPE, MD5SUM, CONTEXTS, LABELS
FROM DATABASECHANGELOG ORDER BY ORDEREXECUTED;
```

### Oracle 11g
```powershell
lbo validate
lbo update --contexts=dev
lbo history
lbo rollback-sql --tag=v1.0        # preview del rollback
lbo rollback --tag=v1.0            # elimina la vista V_CUSTOMERS
lbo update --contexts=dev          # la vuelve a crear
```

Comprueba el trigger en Oracle:
```sql
INSERT INTO CUSTOMERS (DOC_NUMBER, FULL_NAME) VALUES ('10000003', 'Rosa Díaz');
SELECT * FROM V_CUSTOMERS;   -- el ID lo asignó el trigger
```

---

## 2.4 Experimentos

1. **Checksum:** edita `001-create-categories.sql` (cambia `100` por `120`) y ejecuta `lbs update`.
   Lee el error de *checksum*. Deshaz el cambio. Esto es lo que te protege de editar historia.
2. **Contexts:** con una BD limpia (`docker compose down -v`), ejecuta `lbs update --contexts=prod`.
   ¿Hay productos? ¿Qué changesets se saltaron?
3. **Labels:** limpia la BD y ejecuta `lbs update --label-filter=v1`. ¿Existe la columna `stock`?
   ¿Funciona `/products`? (Pista: la app ya espera la v2 — así descubres el acoplamiento app↔esquema.)
4. **IDENTITY en 11g:** crea un changeset YAML con `autoIncrement: true` en Oracle y observa el
   error. Bórralo después (y su fila en `DATABASECHANGELOG` si llegó a registrarse).
5. **Candado:** en dos terminales lanza `lbs update` a la vez. Una espera "Waiting for changelog lock".
   Si un proceso muere con el candado tomado: `lbs release-locks`.
6. **runOnChange:** cambia `UPPER(FULL_NAME)` por `INITCAP(FULL_NAME)` en la vista y ejecuta
   `lbo update`. Mira `EXECTYPE` en `DATABASECHANGELOG` (`RERAN`).

---

## Autoevaluación

<details><summary>1. ¿Cómo sabe Liquibase que un changeset ya se aplicó?</summary>

Busca una fila en `DATABASECHANGELOG` con el mismo id + author + ruta de archivo. Si existe y el
checksum coincide, lo salta.
</details>

<details><summary>2. Renombras el archivo <code>002-create-products.sql</code> a <code>002-products.sql</code>. ¿Qué pasa en el próximo update?</summary>

La ruta forma parte de la identidad, así que Liquibase lo considera un changeset **nuevo** e
intentará crear otra vez la tabla → error "ya existe". Por eso no se renombran archivos aplicados
(o se usa el atributo `logicalFilePath` para fijar la identidad).
</details>

<details><summary>3. Diferencia entre context y label. ¿Cuál usarías para datos de prueba y cuál para una funcionalidad que sale en el sprint 5?</summary>

Context = entorno (datos de prueba → `context:dev`). Label = agrupación lógica/versión
(funcionalidad del sprint 5 → `labels:sprint5`). Ambos se filtran al ejecutar, pero las expresiones
de filtro de labels se deciden en el despliegue y las de contexts las define quien escribe el changeset.
</details>

<details><summary>4. ¿Por qué en Oracle 11g usamos secuencia + trigger?</summary>

Porque las columnas `IDENTITY` no existen hasta 12c. El trigger `BEFORE INSERT` toma
`SEQ_CUSTOMERS.NEXTVAL` cuando el ID viene nulo.
</details>

<details><summary>5. ¿Por qué el changeset del trigger necesita <code>endDelimiter:/</code> y <code>splitStatements:false</code>?</summary>

Porque el bloque PL/SQL tiene `;` internos. Si Liquibase partiera por `;` mandaría fragmentos
inválidos a Oracle. Así envía el bloque completo hasta `/`.
</details>

<details><summary>6. Producción falla a mitad de un update con 3 changesets: el 1º se aplicó, el 2º falló. ¿En qué estado queda?</summary>

El 1º quedó registrado en `DATABASECHANGELOG`. El 2º no se registra (cada changeset corre en su
transacción y se revierte, **salvo DDL en motores donde el DDL hace commit implícito, como
Oracle**). El 3º no se ejecutó. Al corregir y relanzar, Liquibase continúa desde el 2º. Por eso
conviene **un cambio DDL por changeset**.
</details>

<details><summary>7. ¿Para qué sirve <code>update-sql</code> en un pipeline?</summary>

Genera el SQL exacto que se ejecutaría sin tocar la BD. Se publica como artefacto para que un
revisor o DBA lo apruebe antes de aplicar en producción.
</details>

## Retos
1. Añade el changeset `005` en SQL Server: tabla `orders` con FK a `products`, con rollback.
2. En Oracle, crea un paquete PL/SQL `PKG_CUSTOMERS` con una función `COUNT_ACTIVE` usando
   `runOnChange:true`.
3. Ejecuta `diff-changelog` entre dos BDs (crea una segunda BD `labdb2`) para generar un changelog
   automáticamente a partir de diferencias.
4. Usa `generate-changelog` contra un esquema existente de Oracle (ingeniería inversa de una BD legada).
5. Crea un usuario de BD con permisos mínimos para la app y otro con permisos DDL solo para Liquibase.
