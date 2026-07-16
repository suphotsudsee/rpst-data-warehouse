from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.security import create_access_token, get_current_user, verify_password
from app.core.database import get_db
from app.models.entities import User
from app.schemas.common import Token, UserRead

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post("/login", response_model=Token)
def login(form: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)) -> Token:
    user = db.scalar(select(User).where(User.username == form.username))
    if not user or not user.is_active or not verify_password(form.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid username or password")
    return Token(access_token=create_access_token(user), user=UserRead.model_validate(user))


@router.get("/me", response_model=UserRead)
def me(user: User = Depends(get_current_user)) -> User:
    return user
