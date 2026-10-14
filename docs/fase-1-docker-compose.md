# Fase 1 — Docker y Docker Compose

**Objetivo:** levantar en tu PC la API + SQL Server 2022 + Oracle XE 11g con un solo comando y
entender qué ocurre por debajo.

---

## 1.1 Conceptos

### Imagen vs contenedor
- **Imagen**: plantilla de solo lectura (sistema de archivos + metadatos: comando de arranque,
  puertos, variables). Es como una *clase*.
- **Contenedor**: una instancia en ejecución de una imagen, con una capa escribible encima. Es
  como un *objeto*. Puedes crear 10 contenedores de la misma imagen.
- Un contenedor **no es una máquina virtual**: comparte el kernel del host. Por eso arranca en
  segundos. Lo aíslan dos mecanismos del kernel Linux: *namespaces* (qué ve: procesos, red,
  archivos) y *cgroups* (cuánto consume: CPU, RAM). En Windows, Docker Desktop corre todo dentro
  de una VM Linux ligera (WSL2).

### Capas y caché
Cada instrucción del `Dockerfile` (`FROM`, `COPY`, `RUN`) produce una **capa**. Docker reutiliza
una capa si la instrucción y sus archivos de entrada no cambiaron. **Consecuencia práctica:** copia
primero lo que cambia poco (`requirements.txt`) y al final lo que cambia mucho (`app.py`). Así,
editar el código no reinstala dependencias.

### Multi-stage build
`app/Dockerfile` tiene dos `FROM`. La etapa `deps` instala paquetes; la final solo copia el
resultado (`COPY --from=deps`). La imagen final no lleva caché de pip ni herramientas de build →
más pequeña y con menos superficie de ataque.

### Registro y tags
Una imagen se identifica como `registro/usuario/nombre:tag`
(`ghcr.io/tuusuario/lab-api:sha-1a2b3c4`). `latest` es solo un tag más, **no** significa "la
más nueva" de forma garantizada. En CI/CD se usan tags inmutables (el SHA del commit) para saber
exactamente qué código corre.

### Volúmenes
La capa escribible del contenedor se pierde al borrarlo. Para datos persistentes (archivos de BD)
se usa un **volumen**: `mssql-data:/var/opt/mssql`. Si haces `docker compose down` los datos
siguen; con `docker compose down -v` se borran.

### Redes y DNS
Compose crea una red privada para el proyecto y registra cada **nombre de servicio como nombre
DNS**. Por eso la API se conecta a `DB_HOST: sqlserver` y no a una IP. `ports: "1433:1433"`
(host:contenedor) solo sirve para entrar **desde tu PC**; entre contenedores no hace falta.

### Compose: declarativo
`docker-compose.yml` describe servicios, redes y volúmenes. `docker compose up -d` compara lo
declarado con lo que corre y crea/recrea solo lo necesario.

---

## 1.2 Lectura guiada de `docker-compose.yml`

| Fragmento | Qué hace y por qué |
|---|---|
| `${MSSQL_SA_PASSWORD}` | Interpolación: Compose lee el valor del archivo `.env` junto al yml |
| `$$MSSQL_SA_PASSWORD` | `$$` escapa el `$`: Compose no lo interpola y llega `$VAR` al shell **dentro** del contenedor |
| `healthcheck` | Comando que Docker ejecuta periódicamente; marca el contenedor `healthy`/`unhealthy` |
| `depends_on: condition: service_healthy` | No arranca el dependiente hasta que la BD **responde**, no solo hasta que el proceso existe |
| `sqlserver-init` + `service_completed_successfully` | Contenedor de un solo uso que crea la BD `labdb`; la API espera a que termine con código 0 |
| `shm_size: 1g` | Oracle 11g usa memoria compartida (`/dev/shm`); con el valor por defecto (64 MB) no arranca |
| `x-liquibase: &liquibase-base` y `<<: *liquibase-base` | Ancla YAML: define una vez la configuración común y la reutiliza en dos servicios |
| `profiles: ["migrations"]` | Esos servicios solo existen si activas el perfil; `up` normal los ignora |

---

## 1.3 Práctica

```powershell
cd devops-lab
docker compose up -d --build          # construye la API y levanta todo
docker compose ps                     # mira la columna STATUS: (healthy)
docker compose logs -f oracle         # Oracle 11g tarda 1-2 min la primera vez. Ctrl+C para salir
```

Prueba la API:

```powershell
curl.exe http://localhost:8080/health
curl.exe http://localhost:8080/ready      # 503: ¡todavía no hay tablas! (se crean en la fase 2)
```

Que `/ready` falle es **intencional**: demuestra la diferencia entre *vivo* (liveness) y *listo
para atender* (readiness), concepto que reaparece en Kubernetes.

Comandos para explorar:

```powershell
docker compose exec sqlserver bash                     # entrar al contenedor
docker compose exec api env                            # ver variables que recibió la API
docker network ls; docker volume ls
docker image history devops-lab-api                    # ver las capas de la imagen
docker stats --no-stream                               # consumo de CPU/RAM por contenedor
```

Conéctate desde tu PC con un cliente (SSMS / Azure Data Studio / DBeaver):
- SQL Server: `localhost,1433` usuario `sa`
- Oracle: `localhost:1521/XE` usuario `LAB`

---

## 1.4 Experimentos (rompe cosas a propósito)

1. **Caché de capas:** cambia un texto en `app.py` y ejecuta `docker compose build api`. Observa
   que el paso `pip install` dice `CACHED`. Ahora añade un paquete a `requirements.txt` y repite.
2. **Persistencia:** crea una tabla a mano en SQL Server, ejecuta `docker compose down` y luego
   `up -d`. La tabla sigue. Repite con `down -v`: desaparece.
3. **Healthcheck:** pon una contraseña incorrecta en el healthcheck de `sqlserver` y observa cómo
   `api` nunca arranca (`docker compose ps`). ¿Qué te dice `docker inspect --format '{{json .State.Health}}' devops-lab-sqlserver-1`?
4. **DNS:** `docker compose exec api python -c "import socket; print(socket.gethostbyname('sqlserver'))"`.

---

## Autoevaluación

<details><summary>1. Si borras un contenedor de SQL Server, ¿pierdes los datos? ¿De qué depende?</summary>

Depende de si `/var/opt/mssql` está en un volumen. Aquí sí (`mssql-data`), así que los datos
sobreviven. Sin volumen, viven en la capa escribible del contenedor y se pierden con él.
</details>

<details><summary>2. ¿Por qué la API usa <code>DB_HOST=sqlserver</code> y no <code>localhost</code>?</summary>

Dentro del contenedor de la API, `localhost` es el propio contenedor de la API. `sqlserver` es el
nombre del servicio, que el DNS interno de Compose resuelve a la IP del contenedor de la BD.
</details>

<details><summary>3. ¿Qué diferencia hay entre <code>depends_on</code> sin condición y con <code>service_healthy</code>?</summary>

Sin condición, solo garantiza el **orden de arranque** del contenedor (el proceso existe). Con
`service_healthy`, espera a que el healthcheck pase, es decir, que la BD acepte conexiones.
</details>

<details><summary>4. ¿Por qué en el Dockerfile se copia <code>requirements.txt</code> antes que <code>app.py</code>?</summary>

Por la caché de capas: si solo cambia `app.py`, la capa de `pip install` se reutiliza y el build
tarda segundos.
</details>

<details><summary>5. ¿Qué pasaría si escribes <code>$MSSQL_SA_PASSWORD</code> (un solo $) en el <code>entrypoint</code> de <code>sqlserver-init</code>?</summary>

Compose lo interpolaría al leer el archivo usando `.env`. En este caso funcionaría igual porque el
valor existe, pero si la variable solo existiera dentro del contenedor quedaría vacía. `$$` deja
la expansión al shell del contenedor, que es lo correcto cuando el valor viene de `environment:`.
</details>

## Retos
1. Añade un servicio `adminer` (imagen `adminer`) para administrar SQL Server desde el navegador.
2. Limita la memoria de `sqlserver` a 2 GB con `deploy.resources.limits.memory`.
3. Crea un `docker-compose.override.yml` que monte `./app` como volumen y arranque Flask en modo
   debug con recarga automática. Entiende cómo Compose fusiona ambos archivos (`docker compose config`).
4. Crea un usuario no-root en SQL Server para la app en lugar de `sa`.

## Problemas comunes
- **Oracle reinicia en bucle:** falta `shm_size` o Docker tiene poca RAM.
- **`sqlserver` unhealthy:** la contraseña no cumple la política de complejidad de SQL Server.
- **Puerto 1433/1521 ocupado:** tienes una instancia local instalada; cambia el lado izquierdo del
  mapeo, p. ej. `"14330:1433"`.
