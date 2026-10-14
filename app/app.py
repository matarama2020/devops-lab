"""API mínima de productos sobre SQL Server.

El esquema NO lo crea la app: lo crea Liquibase (fase 2). La app solo lee/escribe.
"""
import os

import pymssql
from flask import Flask, jsonify, request

app = Flask(__name__)

DB_CONFIG = {
    "server": os.getenv("DB_HOST", "localhost"),
    "port": os.getenv("DB_PORT", "1433"),
    "user": os.getenv("DB_USER", "sa"),
    "password": os.getenv("DB_PASSWORD", ""),
    "database": os.getenv("DB_NAME", "labdb"),
    "login_timeout": 5,
}


def get_conn():
    return pymssql.connect(**DB_CONFIG)


@app.get("/health")
def health():
    """Liveness: el proceso responde. No toca la BD."""
    return jsonify(status="ok", version=os.getenv("APP_VERSION", "dev"))


@app.get("/ready")
def ready():
    """Readiness: la BD responde y el esquema de Liquibase existe."""
    try:
        with get_conn() as conn, conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM DATABASECHANGELOG")
            applied = cur.fetchone()[0]
        return jsonify(status="ready", changesets_applied=applied)
    except Exception as exc:  # noqa: BLE001 - queremos reportar cualquier fallo
        return jsonify(status="not-ready", error=str(exc)), 503


@app.get("/products")
def list_products():
    with get_conn() as conn, conn.cursor(as_dict=True) as cur:
        cur.execute(
            """SELECT p.id, p.name, p.price, p.stock, c.name AS category
                 FROM products p JOIN categories c ON c.id = p.category_id
                ORDER BY p.id"""
        )
        rows = cur.fetchall()
    for r in rows:
        r["price"] = float(r["price"])
    return jsonify(rows)


@app.post("/products")
def create_product():
    data = request.get_json(force=True)
    missing = [f for f in ("name", "price", "category_id") if f not in data]
    if missing:
        return jsonify(error=f"faltan campos: {missing}"), 400
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO products (name, price, stock, category_id) "
            "OUTPUT INSERTED.id VALUES (%s, %s, %s, %s)",
            (data["name"], data["price"], data.get("stock", 0), data["category_id"]),
        )
        new_id = cur.fetchone()[0]
        conn.commit()
    return jsonify(id=new_id), 201


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
