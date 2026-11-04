import React, { useState, useEffect, useCallback } from "react";
import { api } from "./api";

export default function App() {
  const [notes, setNotes] = useState([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState("");
  const [apiHealth, setApiHealth] = useState({ status: "checking", service: "" });
  const [dbHealth, setDbHealth] = useState({ status: "checking", database: "" });
  const [error, setError] = useState(null);
  const [successMsg, setSuccessMsg] = useState(null);

  // Modal / Form state
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingNote, setEditingNote] = useState(null);
  const [formData, setFormData] = useState({ title: "", content: "" });
  const [submitting, setSubmitting] = useState(false);

  // Check system health
  const checkHealthStatus = useCallback(async () => {
    try {
      const health = await api.checkHealth();
      setApiHealth({ status: "healthy", service: health.service });
    } catch (err) {
      setApiHealth({ status: "unhealthy", service: err.message });
    }

    try {
      const db = await api.checkDbHealth();
      setDbHealth({ status: "healthy", database: db.database });
    } catch (err) {
      setDbHealth({ status: "unhealthy", database: err.message });
    }
  }, []);

  // Fetch notes list
  const loadNotes = useCallback(async (query = "") => {
    try {
      setLoading(true);
      setError(null);
      const data = await api.listNotes(query);
      setNotes(data || []);
    } catch (err) {
      setError(`Failed to load notes: ${err.message}`);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    checkHealthStatus();
    loadNotes();
  }, [checkHealthStatus, loadNotes]);

  // Handle Search input
  const handleSearch = (e) => {
    const val = e.target.value;
    setSearchQuery(val);
    loadNotes(val);
  };

  // Open Create Modal
  const openCreateModal = () => {
    setEditingNote(null);
    setFormData({ title: "", content: "" });
    setIsModalOpen(true);
  };

  // Open Edit Modal
  const openEditModal = (note) => {
    setEditingNote(note);
    setFormData({ title: note.title, content: note.content });
    setIsModalOpen(true);
  };

  // Close Modal
  const closeModal = () => {
    setIsModalOpen(false);
    setEditingNote(null);
    setFormData({ title: "", content: "" });
  };

  // Submit Note (Create or Update)
  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!formData.title.trim()) {
      alert("Title is required");
      return;
    }

    try {
      setSubmitting(true);
      if (editingNote) {
        await api.updateNote(editingNote.id, formData);
        setSuccessMsg("Note updated successfully");
      } else {
        await api.createNote(formData);
        setSuccessMsg("Note created successfully");
      }
      closeModal();
      loadNotes(searchQuery);
      setTimeout(() => setSuccessMsg(null), 3500);
    } catch (err) {
      setError(`Operation failed: ${err.message}`);
    } finally {
      setSubmitting(false);
    }
  };

  // Delete Note
  const handleDelete = async (id, title) => {
    if (!window.confirm(`Are you sure you want to delete note "${title}"?`)) {
      return;
    }

    try {
      await api.deleteNote(id);
      setSuccessMsg("Note deleted successfully");
      loadNotes(searchQuery);
      setTimeout(() => setSuccessMsg(null), 3500);
    } catch (err) {
      setError(`Failed to delete note: ${err.message}`);
    }
  };

  const formatDate = (isoString) => {
    if (!isoString) return "";
    const date = new Date(isoString);
    return date.toLocaleString(undefined, {
      month: "short",
      day: "numeric",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  };

  return (
    <div className="app-container">
      {/* Top Header */}
      <header className="app-header">
        <div className="header-brand">
          <div className="brand-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path>
              <polyline points="14 2 14 8 20 8"></polyline>
              <line x1="16" y1="13" x2="8" y2="13"></line>
              <line x1="16" y1="17" x2="8" y2="17"></line>
              <polyline points="10 9 9 9 8 9"></polyline>
            </svg>
          </div>
          <div>
            <h1>Cloud Notes</h1>
            <p className="subtitle">3-Tier Cloud Architecture &bull; Local Environment</p>
          </div>
        </div>

        {/* Health Indicators */}
        <div className="health-badges">
          <div className={`health-pill ${apiHealth.status === "healthy" ? "pill-ok" : "pill-err"}`} title="Application Load Balancer shallow check">
            <span className="dot"></span>
            <span>API: {apiHealth.status === "healthy" ? "Healthy (200)" : "Unreachable"}</span>
          </div>

          <div className={`health-pill ${dbHealth.status === "healthy" ? "pill-ok" : "pill-err"}`} title="Deep database connection probe">
            <span className="dot"></span>
            <span>DB: {dbHealth.status === "healthy" ? "Connected" : "Disconnected"}</span>
          </div>

          <button className="icon-btn" onClick={checkHealthStatus} title="Recheck Health Probes">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" width="16" height="16">
              <polyline points="23 4 23 10 17 10"></polyline>
              <polyline points="1 20 1 14 7 14"></polyline>
              <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"></path>
            </svg>
          </button>
        </div>
      </header>

      {/* Action Alerts */}
      {successMsg && (
        <div className="alert alert-success">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" width="18" height="18">
            <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"></path>
            <polyline points="22 4 12 14.01 9 11.01"></polyline>
          </svg>
          <span>{successMsg}</span>
        </div>
      )}

      {error && (
        <div className="alert alert-error">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" width="18" height="18">
            <circle cx="12" cy="12" r="10"></circle>
            <line x1="12" y1="8" x2="12" y2="12"></line>
            <line x1="12" y1="16" x2="12.01" y2="16"></line>
          </svg>
          <span>{error}</span>
          <button className="alert-close" onClick={() => setError(null)}>&times;</button>
        </div>
      )}

      {/* Main Content Area */}
      <main className="app-main">
        {/* Controls: Search and Add Button */}
        <div className="controls-row">
          <div className="search-box">
            <svg className="search-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" width="18" height="18">
              <circle cx="11" cy="11" r="8"></circle>
              <line x1="21" y1="21" x2="16.65" y2="16.65"></line>
            </svg>
            <input
              type="text"
              placeholder="Search notes by title or content..."
              value={searchQuery}
              onChange={handleSearch}
            />
            {searchQuery && (
              <button className="clear-search" onClick={() => { setSearchQuery(""); loadNotes(""); }}>
                &times;
              </button>
            )}
          </div>

          <button className="btn btn-primary" onClick={openCreateModal}>
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" width="18" height="18">
              <line x1="12" y1="5" x2="12" y2="19"></line>
              <line x1="5" y1="12" x2="19" y2="12"></line>
            </svg>
            <span>New Note</span>
          </button>
        </div>

        {/* Loading Spinner */}
        {loading && (
          <div className="state-container">
            <div className="spinner"></div>
            <p>Loading your notes from database...</p>
          </div>
        )}

        {/* Empty State */}
        {!loading && notes.length === 0 && (
          <div className="state-container empty-state">
            <div className="empty-icon">📝</div>
            <h3>{searchQuery ? "No matching notes found" : "No notes yet"}</h3>
            <p>{searchQuery ? "Try searching with different keywords." : "Create your first note to get started."}</p>
            {!searchQuery && (
              <button className="btn btn-primary" onClick={openCreateModal} style={{ marginTop: "1rem" }}>
                Create First Note
              </button>
            )}
          </div>
        )}

        {/* Notes Grid */}
        {!loading && notes.length > 0 && (
          <div className="notes-grid">
            {notes.map((note) => (
              <article key={note.id} className="note-card">
                <div className="card-header">
                  <h3 className="card-title">{note.title}</h3>
                  <div className="card-actions">
                    <button
                      className="card-action-btn edit"
                      onClick={() => openEditModal(note)}
                      title="Edit note"
                    >
                      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" width="16" height="16">
                        <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"></path>
                        <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"></path>
                      </svg>
                    </button>
                    <button
                      className="card-action-btn delete"
                      onClick={() => handleDelete(note.id, note.title)}
                      title="Delete note"
                    >
                      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" width="16" height="16">
                        <polyline points="3 6 5 6 21 6"></polyline>
                        <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
                      </svg>
                    </button>
                  </div>
                </div>

                <p className="card-body">{note.content}</p>

                <footer className="card-footer">
                  <span className="card-time">Updated {formatDate(note.updated_at)}</span>
                  <span className="card-id">ID: #{note.id}</span>
                </footer>
              </article>
            ))}
          </div>
        )}
      </main>

      {/* Create / Edit Note Modal */}
      {isModalOpen && (
        <div className="modal-backdrop" onClick={closeModal}>
          <div className="modal-card" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h2>{editingNote ? "Edit Note" : "Create New Note"}</h2>
              <button className="modal-close" onClick={closeModal}>&times;</button>
            </div>

            <form onSubmit={handleSubmit}>
              <div className="form-group">
                <label htmlFor="note-title">Title</label>
                <input
                  id="note-title"
                  type="text"
                  required
                  placeholder="e.g. Deploying to AWS EC2"
                  value={formData.title}
                  onChange={(e) => setFormData({ ...formData, title: e.target.value })}
                  autoFocus
                />
              </div>

              <div className="form-group">
                <label htmlFor="note-content">Content</label>
                <textarea
                  id="note-content"
                  rows="6"
                  required
                  placeholder="Write your note description, commands, architecture details..."
                  value={formData.content}
                  onChange={(e) => setFormData({ ...formData, content: e.target.value })}
                />
              </div>

              <div className="modal-footer">
                <button type="button" className="btn btn-secondary" onClick={closeModal}>
                  Cancel
                </button>
                <button type="submit" className="btn btn-primary" disabled={submitting}>
                  {submitting ? "Saving..." : editingNote ? "Update Note" : "Save Note"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
