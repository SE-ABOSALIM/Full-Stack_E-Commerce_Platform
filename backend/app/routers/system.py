"""Application health and database diagnostic routes."""

from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.dependencies import get_db

router = APIRouter()


@router.get("/check-db")
def check_database(db: Session = Depends(get_db)):
    try:
        # Check if sellers table exists
        from sqlalchemy import text
        result = db.execute(text("SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'sellers')"))
        sellers_exists = result.scalar()

        return {
            "sellers_table_exists": sellers_exists,
            "message": "Database check completed"
        }
    except Exception as e:
        return {"error": str(e)}


@router.get("/")
def root():
    return {"message": "Backend is running!"}
