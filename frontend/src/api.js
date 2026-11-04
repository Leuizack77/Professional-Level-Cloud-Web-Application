const API_BASE = (typeof import.meta !== "undefined" && import.meta?.env?.VITE_API_URL) || "";

async function request(endpoint, options = {}) {
  const url = `${API_BASE}${endpoint}`;
  const config = {
    headers: {
      "Content-Type": "application/json",
      ...options.headers,
    },
    ...options,
  };

  const response = await fetch(url, config);

  if (response.status === 204) {
    return null;
  }

  const data = await response.json().catch(() => null);

  if (!response.ok) {
    const errorMsg = data?.detail || `Request failed with status ${response.status}`;
    throw new Error(typeof errorMsg === "string" ? errorMsg : JSON.stringify(errorMsg));
  }

  return data;
}

export const api = {
  // Health checks
  checkHealth: () => request("/health"),
  checkDbHealth: () => request("/health/db"),

  // Notes CRUD
  listNotes: (searchQuery = "") => {
    const query = searchQuery ? `?q=${encodeURIComponent(searchQuery)}` : "";
    return request(`/api/notes${query}`);
  },

  getNote: (id) => request(`/api/notes/${id}`),

  createNote: (payload) =>
    request("/api/notes", {
      method: "POST",
      body: JSON.stringify(payload),
    }),

  updateNote: (id, payload) =>
    request(`/api/notes/${id}`, {
      method: "PUT",
      body: JSON.stringify(payload),
    }),

  deleteNote: (id) =>
    request(`/api/notes/${id}`, {
      method: "DELETE",
    }),
};
