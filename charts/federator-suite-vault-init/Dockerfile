# Install dependencies in the target-platform image so pip resolves wheels
# for the same Python and architecture used by the runtime image.
FROM python:3.13-slim AS dependencies
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*
WORKDIR /build
ARG REQUIREMENTS=vault-init/requirements.txt
COPY ${REQUIREMENTS} requirements.txt
COPY --from=ghcr.io/astral-sh/uv:0.9.17 /uv /uvx /bin/
RUN uv pip install --no-cache --target=/python-deps -r requirements.txt


FROM python:3.13-slim AS runtime
RUN apt-get update && apt-get upgrade -y  && rm -rf /var/lib/apt/lists/*
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
WORKDIR /app
# The Python base image includes older copies of these packages. Remove them
# before copying the patched dependency set so stale dist-info is not scanned.
RUN python -m pip uninstall -y msgpack setuptools urllib3 || true
COPY --from=dependencies /python-deps /usr/local/lib/python3.13/site-packages
# pip is only needed while building the image. Its vendored packages are not
# required by the runtime and can otherwise be reported by the image scanner.
RUN rm -rf /usr/local/lib/python3.13/site-packages/pip \
           /usr/local/lib/python3.13/site-packages/pip-*.dist-info \
           /usr/local/bin/pip /usr/local/bin/pip3 /usr/local/bin/pip3.13
COPY vault-init/main.py /app/
USER 65532:65532
ENTRYPOINT ["python", "/app/main.py"]


FROM runtime AS test
COPY vault-init/test_main.py /app/
