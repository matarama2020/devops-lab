"""Tests unitarios: no necesitan BD (se simula la conexión)."""
import app as api


def client():
    api.app.config["TESTING"] = True
    return api.app.test_client()


def test_health_no_toca_bd(monkeypatch):
    monkeypatch.setenv("APP_VERSION", "test-123")
    res = client().get("/health")
    assert res.status_code == 200
    assert res.get_json() == {"status": "ok", "version": "test-123"}


def test_ready_devuelve_503_si_la_bd_falla(monkeypatch):
    def boom():
        raise ConnectionError("sin BD")

    monkeypatch.setattr(api, "get_conn", boom)
    res = client().get("/ready")
    assert res.status_code == 503
    assert res.get_json()["status"] == "not-ready"


def test_post_valida_campos():
    res = client().post("/products", json={"name": "x"})
    assert res.status_code == 400
