# --- Etapa 1: dependencias (se cachea mientras requirements.txt no cambie) ---
FROM python:3.12-slim AS deps
WORKDIR /install
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install/pkgs -r requirements.txt

# --- Etapa 2: imagen final, sin herramientas de build ---
FROM python:3.12-slim
WORKDIR /app
COPY --from=deps /install/pkgs /usr/local
COPY app.py .

# No ejecutar como root
RUN useradd --uid 10001 --no-create-home appuser
USER 10001

ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} PYTHONUNBUFFERED=1
EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
