# ============================================================================
# Multi-stage Dockerfile for FastAPI sample app
# Conventions: ai-ops-harness /dockerfile skill
#   - Multi-stage build (builder → runtime)
#   - Minimal base (python:3.12-slim), version pinned (no :latest)
#   - Non-root user
#   - HEALTHCHECK included
#   - Layer caching: dependencies first, then source
# ============================================================================

# ── Stage 1: Builder ───────────────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Stage 2: Runtime ──────────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

# KST timezone (SEEMEDI standard)
ENV TZ=Asia/Seoul
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Non-root user
RUN groupadd --gid 1001 appuser && \
    useradd --uid 1001 --gid 1001 --no-create-home appuser

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Copy application source
COPY src/ ./

# Switch to non-root user
USER appuser

EXPOSE 8000

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/healthz')"]

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
