"""Sample FastAPI application for k8s-local-lab.

Provides health-check endpoints for Kubernetes probes and a root info endpoint.
Follows SEEMEDI backend standards: KST timezone, structured logging, RFC 9457 errors.
"""

import logging
import os
import socket
from contextlib import asynccontextmanager
from datetime import datetime, timezone, timedelta

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from core.config import settings

# KST timezone (UTC+9)
KST = timezone(timedelta(hours=9))

# Logging — KST timestamp, structured format
logging.basicConfig(
    level=getattr(logging, settings.log_level.upper(), logging.INFO),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
logger = logging.getLogger(settings.app_name)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("[startup] %s %s started (env=%s)",
                settings.app_name, settings.app_version, settings.environment)
    yield
    logger.info("[shutdown] %s stopped", settings.app_name)


app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    lifespan=lifespan,
)


# ── Global exception handler (RFC 9457 problem+json) ──────────────────────

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error("[error] %s %s — %s", request.method, request.url.path, str(exc))
    return JSONResponse(
        status_code=500,
        content={
            "type": "about:blank",
            "title": "Internal Server Error",
            "status": 500,
            "detail": "서버 내부 오류가 발생했습니다.",
            "instance": str(request.url.path),
        },
    )


# ── Endpoints ──────────────────────────────────────────────────────────────

@app.get("/healthz")
async def healthz():
    """Liveness probe — 앱이 살아 있는지 확인.

    Kubernetes가 이 엔드포인트를 주기적으로 호출한다.
    실패하면 Pod를 재시작한다.
    """
    return {"status": "ok"}


@app.get("/readyz")
async def readyz():
    """Readiness probe — 앱이 트래픽을 받을 준비가 되었는지 확인.

    Kubernetes가 이 엔드포인트를 주기적으로 호출한다.
    실패하면 Service에서 Pod를 제외한다 (트래픽을 보내지 않는다).
    실제 프로덕션에서는 여기서 DB 연결 등을 확인한다.
    """
    return {"status": "ok", "db": "connected"}


@app.get("/")
async def root():
    """서비스 정보 엔드포인트."""
    return {
        "service": settings.app_name,
        "version": settings.app_version,
        "environment": settings.environment,
        "hostname": socket.gethostname(),
        "timestamp": datetime.now(KST).isoformat(),
    }
