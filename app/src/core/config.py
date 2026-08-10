"""Application configuration via pydantic-settings."""

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_name: str = "k8s-local-lab"
    app_version: str = "0.1.0"
    environment: str = "local"
    log_level: str = "INFO"
    database_url: str = "postgresql://seemedi:seemedi@localhost:5432/seemedi"

    model_config = {"env_prefix": "", "case_sensitive": False}


settings = Settings()
