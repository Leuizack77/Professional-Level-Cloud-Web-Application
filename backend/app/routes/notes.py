from datetime import datetime, timezone
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models import Note
from app.schemas import NoteCreate, NoteResponse, NoteUpdate

router = APIRouter(prefix="/api/notes", tags=["Notes"])


@router.post("", response_model=NoteResponse, status_code=status.HTTP_201_CREATED)
def create_note(payload: NoteCreate, db: Session = Depends(get_db)):
    """Create a new note."""
    note = Note(
        title=payload.title.strip(),
        content=payload.content.strip(),
    )
    db.add(note)
    db.commit()
    db.refresh(note)
    return note


@router.get("", response_model=List[NoteResponse], status_code=status.HTTP_200_OK)
def list_notes(
    q: Optional[str] = Query(
        None,
        max_length=100,
        description="Optional search query filter for title or content (constrained to max 100 characters)",
    ),
    db: Session = Depends(get_db),
):
    """List all notes, ordered by updated_at descending."""
    query = db.query(Note)
    if q and q.strip():
        term = f"%{q.strip()}%"
        query = query.filter((Note.title.ilike(term)) | (Note.content.ilike(term)))
    return query.order_by(Note.updated_at.desc()).all()


@router.get("/{note_id}", response_model=NoteResponse, status_code=status.HTTP_200_OK)
def get_note(note_id: int, db: Session = Depends(get_db)):
    """Retrieve a single note by its ID."""
    note = db.query(Note).filter(Note.id == note_id).first()
    if not note:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Note with ID {note_id} not found",
        )
    return note


@router.put("/{note_id}", response_model=NoteResponse, status_code=status.HTTP_200_OK)
def update_note(note_id: int, payload: NoteUpdate, db: Session = Depends(get_db)):
    """Update an existing note."""
    note = db.query(Note).filter(Note.id == note_id).first()
    if not note:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Note with ID {note_id} not found",
        )

    if payload.title is not None:
        note.title = payload.title.strip()
    if payload.content is not None:
        note.content = payload.content.strip()

    note.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(note)
    return note


@router.delete("/{note_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_note(note_id: int, db: Session = Depends(get_db)):
    """Delete a note by its ID."""
    note = db.query(Note).filter(Note.id == note_id).first()
    if not note:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Note with ID {note_id} not found",
        )
    db.delete(note)
    db.commit()
    return None
