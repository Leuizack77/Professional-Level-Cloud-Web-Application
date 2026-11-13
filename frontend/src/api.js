// Resolves API Base URL:
// - Empty string ("") in production CloudFront dual-origin setup (routes directly through CloudFront behaviors)
// - Custom URL (e.g. "http://localhost:8000" or ALB DNS) when VITE_API_URL is supplied in .env
const RAW_API_BASE = (typeof import.meta !== "undefined" && import.meta?.env?.VITE_API_URL) || "";
export const API_BASE = RAW_API_BASE.replace(/\/+$/, "");

/**
 * Builds a clean target URL ensuring single slash joining.
 */
export function buildUrl(endpoint) {
  const cleanEndpoint = endpoint.startsWith("/") ? endpoint : `/${endpoint}`;
  return `${API_BASE}${cleanEndpoint}`;
}

/**
 * Low-level HTTP request helper with timeout and graceful error extraction.
 */
async function request(endpoint, options = {}) {
  const url = buildUrl(endpoint);
  const timeoutMs = options.timeout || 15000;

  // Support client request timeouts
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  const config = {
    headers: {
      "Content-Type": "application/json",
      ...options.headers,
    },
    signal: options.signal || controller.signal,
    ...options,
  };
  delete config.timeout;

  try {
    const response = await fetch(url, config);

    if (response.status === 204) {
      return null;
    }

    const data = await response.json().catch(() => null);

    if (!response.ok) {
      let errorMsg = data?.detail;
      if (!errorMsg) {
        if (response.status === 502) errorMsg = "Bad Gateway: Backend instances unreachable via ALB/CloudFront.";
        else if (response.status === 503) errorMsg = "Service Unavailable: Backend is undergoing maintenance or initialization.";
        else if (response.status === 504) errorMsg = "Gateway Timeout: Backend did not respond in time.";
        else errorMsg = `Request failed with status ${response.status}`;
      }
      throw new Error(typeof errorMsg === "string" ? errorMsg : JSON.stringify(errorMsg));
    }

    return data;
  } catch (err) {
    if (err.name === "AbortError") {
      throw new Error(`Request timed out after ${timeoutMs / 1000}s while contacting ${url}`);
    }
    throw err;
  } finally {
    clearTimeout(timeoutId);
  }
}

export const api = {
  // Base configuration inspection
  getBaseUrl: () => API_BASE,

  // Health & Readiness Probes
  checkHealth: (options) => request("/health", options),
  checkDbHealth: (options) => request("/health/db", options),
  checkReadiness: (options) => request("/health/ready", options),

  // Notes CRUD
  listNotes: (searchQuery = "", options) => {
    const query = searchQuery ? `?q=${encodeURIComponent(searchQuery)}` : "";
    return request(`/api/notes${query}`, options);
  },

  getNote: (id, options) => request(`/api/notes/${id}`, options),

  createNote: (payload, options) =>
    request("/api/notes", {
      method: "POST",
      body: JSON.stringify(payload),
      ...options,
    }),

  updateNote: (id, payload, options) =>
    request(`/api/notes/${id}`, {
      method: "PUT",
      body: JSON.stringify(payload),
      ...options,
    }),

  deleteNote: (id, options) =>
    request(`/api/notes/${id}`, {
      method: "DELETE",
      ...options,
    }),
};
