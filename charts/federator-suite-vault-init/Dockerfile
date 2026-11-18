# Install dependencies in the target-platform image so pip resolves wheels
# for the same Python and architecture used by the runtime image.
FROM python:3.13-slim AS dependencies
WORKDIR /build
ARG REQUIREMENTS=vault-init/requirements.txt
COPY ${REQUIREMENTS} requirements.txt
COPY --from=ghcr.io/astral-sh/uv:0.9.17 /uv /uvx /bin/
RUN uv pip install \
      --no-cache \
      --target=/python-deps \
      -r requirements.txt

FROM python:3.13-slim AS runtime
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
WORKDIR /app
COPY --from=dependencies /python-deps /usr/local/lib/python3.13/site-packages
COPY vault-init/main.py /app/
USER 65532:65532
ENTRYPOINT ["python", "/app/main.py"]

FROM runtime AS test
COPY vault-init/test_main.py /app/
