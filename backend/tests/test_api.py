import pytest
from app.config import Settings


def test_shallow_health_check(client):
    """Verify /health is 200 OK and independent of DB."""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert data["service"] == "notes-api"
    assert "timestamp" in data


def test_deep_database_health_check(client):
    """Verify /health/db checks database connectivity."""
    response = client.get("/health/db")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert data["database"] == "connected"


def test_security_headers_present(client):
    """Verify essential defense-in-depth security headers are present on responses."""
    response = client.get("/health")
    assert response.headers.get("X-Content-Type-Options") == "nosniff"
    assert response.headers.get("X-Frame-Options") == "DENY"
    assert response.headers.get("X-XSS-Protection") == "1; mode=block"
    assert response.headers.get("Referrer-Policy") == "strict-origin-when-cross-origin"


def test_crud_note_lifecycle(client):
    """Full lifecycle test: Create -> Read -> Update -> Search -> Delete -> 404."""
    # 1. Create a note
    payload = {
        "title": "Cloud Architecture Study",
        "content": "Designing high-availability 3-tier cloud web apps with Terraform.",
    }
    create_resp = client.post("/api/notes", json=payload)
    assert create_resp.status_code == 201
    created_note = create_resp.json()
    assert created_note["id"] is not None
    assert created_note["title"] == payload["title"]
    assert created_note["content"] == payload["content"]
    note_id = created_note["id"]

    # 2. Get the note by ID
    get_resp = client.get(f"/api/notes/{note_id}")
    assert get_resp.status_code == 200
    assert get_resp.json()["id"] == note_id

    # 3. List notes
    list_resp = client.get("/api/notes")
    assert list_resp.status_code == 200
    notes = list_resp.json()
    assert len(notes) >= 1
    assert any(n["id"] == note_id for n in notes)

    # 4. Search notes with query matching
    search_resp = client.get("/api/notes?q=Terraform")
    assert search_resp.status_code == 200
    search_results = search_resp.json()
    assert len(search_results) == 1
    assert search_results[0]["id"] == note_id

    # 5. Search notes with non-matching query
    search_empty_resp = client.get("/api/notes?q=nonexistent_xyz_term")
    assert search_empty_resp.status_code == 200
    assert len(search_empty_resp.json()) == 0

    # 6. Update the note
    update_payload = {
        "title": "Updated Cloud Architecture",
        "content": "Now including Application Load Balancer and Auto Scaling Groups.",
    }
    update_resp = client.put(f"/api/notes/{note_id}", json=update_payload)
    assert update_resp.status_code == 200
    updated_note = update_resp.json()
    assert updated_note["title"] == update_payload["title"]
    assert updated_note["content"] == update_payload["content"]

    # 7. Delete the note
    delete_resp = client.delete(f"/api/notes/{note_id}")
    assert delete_resp.status_code == 204

    # 8. Verify note no longer exists (404)
    get_deleted_resp = client.get(f"/api/notes/{note_id}")
    assert get_deleted_resp.status_code == 404


def test_create_note_validation_error(client):
    """Verify empty title is rejected with 422."""
    response = client.post("/api/notes", json={"title": "", "content": "Missing title"})
    assert response.status_code == 422


def test_unbounded_content_rejected(client):
    """Verify content exceeding 50,000 characters is rejected with 422."""
    oversized_content = "A" * 50001
    response = client.post("/api/notes", json={"title": "Oversized", "content": oversized_content})
    assert response.status_code == 422


def test_unconstrained_search_query_rejected(client):
    """Verify search query parameter exceeding 100 characters is rejected with 422."""
    long_query = "x" * 101
    response = client.get(f"/api/notes?q={long_query}")
    assert response.status_code == 422


def test_wildcard_cors_rejected():
    """Verify that wildcard '*' in CORS_ORIGINS is rejected at configuration time."""
    with pytest.raises(ValueError, match="Wildcard '\\*' CORS origin is strictly forbidden"):
        Settings(CORS_ORIGINS="*,http://localhost:3000")


def test_update_nonexistent_note_404(client):
    """Verify updating a non-existent note yields 404."""
    response = client.put("/api/notes/99999", json={"title": "Ghost"})
    assert response.status_code == 404


def test_delete_nonexistent_note_404(client):
    """Verify deleting a non-existent note yields 404."""
    response = client.delete("/api/notes/99999")
    assert response.status_code == 404
