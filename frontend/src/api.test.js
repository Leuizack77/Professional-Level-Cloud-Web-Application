import test from "node:test";
import assert from "node:assert/strict";
import { api } from "./api.js";

test("frontend api client: listNotes constructs expected search URL and parses response", async () => {
  // Mock fetch globally for testing
  const originalFetch = globalThis.fetch;
  let requestedUrl = null;
  let requestOptions = null;

  globalThis.fetch = async (url, options) => {
    requestedUrl = url;
    requestOptions = options;
    return {
      ok: true,
      status: 200,
      json: async () => [
        { id: 1, title: "Test Note", content: "Test Content", created_at: "2026-11-04T00:00:00Z", updated_at: "2026-11-04T00:00:00Z" }
      ],
    };
  };

  try {
    const result = await api.listNotes("architecture");
    assert.strictEqual(requestedUrl, "/api/notes?q=architecture");
    assert.strictEqual(result.length, 1);
    assert.strictEqual(result[0].title, "Test Note");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("frontend api client: createNote sends POST with JSON payload", async () => {
  const originalFetch = globalThis.fetch;
  let requestedUrl = null;
  let requestOptions = null;

  globalThis.fetch = async (url, options) => {
    requestedUrl = url;
    requestOptions = options;
    return {
      ok: true,
      status: 201,
      json: async () => ({ id: 2, title: "Cloud Note", content: "S3 and EC2" }),
    };
  };

  try {
    const payload = { title: "Cloud Note", content: "S3 and EC2" };
    const result = await api.createNote(payload);

    assert.strictEqual(requestedUrl, "/api/notes");
    assert.strictEqual(requestOptions.method, "POST");
    assert.strictEqual(requestOptions.headers["Content-Type"], "application/json");
    assert.strictEqual(requestOptions.body, JSON.stringify(payload));
    assert.strictEqual(result.id, 2);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

