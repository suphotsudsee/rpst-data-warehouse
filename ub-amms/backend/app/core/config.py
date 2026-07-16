from functools import lru_cache

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "UB-AMMS"
    environment: str = "development"
    secret_key: str = "development-only-change-me"
    access_token_expire_minutes: int = 480
    database_url: str = "sqlite:///./ub_amms.db"
    cors_origins: str = "http://localhost:5173,http://localhost:8080"
    initial_admin_username: str = "admin"
    initial_admin_password: str = "ChangeMe123!"
    initial_admin_email: str = "admin@example.local"
    upload_dir: str = "uploads"
    backup_dir: str = "backups"
    max_upload_mb: int = 20

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    @property
    def cors_origin_list(self) -> list[str]:
        return [item.strip() for item in self.cors_origins.split(",") if item.strip()]

    @model_validator(mode="after")
    def validate_production_secrets(self) -> "Settings":
        if self.environment.lower() == "production":
            if self.secret_key == "development-only-change-me" or len(self.secret_key) < 32:
                raise ValueError("SECRET_KEY must be a strong secret in production")
            if self.initial_admin_password == "ChangeMe123!":
                raise ValueError("INITIAL_ADMIN_PASSWORD must be changed in production")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
