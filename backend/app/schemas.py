from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field, ConfigDict


class NoteBase(BaseModel):
    title: str = Field(
        ...,
        min_length=1,
        max_length=255,
        description="Title of the note",
    )
    content: str = Field(
        ...,
        min_length=1,
        max_length=50000,
        description="Main content or body of the note (enforces 50,000 character maximum limit)",
    )


class NoteCreate(NoteBase):
    pass


class NoteUpdate(BaseModel):
    title: Optional[str] = Field(
        None,
        min_length=1,
        max_length=255,
        description="Updated title",
    )
    content: Optional[str] = Field(
        None,
        min_length=1,
        max_length=50000,
        description="Updated content (enforces 50,000 character maximum limit)",
    )


class NoteResponse(NoteBase):
    id: int
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)
