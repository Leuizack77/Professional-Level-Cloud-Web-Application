def test_example_shallow_health_check(client):
    """
    Passing Example Test for Backend Layer.
    Validates that /health returns HTTP 200 with expected metadata
    strictly without establishing a database session.
    """
    response = client.get("/health")
    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "healthy"
    assert payload["service"] == "notes-api"
    assert "timestamp" in payload

