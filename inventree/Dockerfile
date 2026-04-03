ARG BUILD_FROM=inventree/inventree:stable
FROM ${BUILD_FROM}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV INVENTREE_DATA_DIR=/data \
    INVENTREE_STATIC_ROOT=/data/static \
    INVENTREE_MEDIA_ROOT=/data/media \
    INVENTREE_BACKUP_DIR=/data/backup \
    INVENTREE_PLUGIN_DIR=/data/plugins \
    INVENTREE_CONFIG_FILE=/data/config.yaml \
    INVENTREE_SECRET_KEY_FILE=/data/secret_key.txt \
    INVENTREE_OIDC_PRIVATE_KEY_FILE=/data/oidc.pem \
    INVENTREE_PLUGIN_FILE=/data/plugins.txt \
    INVENTREE_WEB_ADDR=127.0.0.1 \
    INVENTREE_WEB_PORT=8001 \
    PYTHONUNBUFFERED=1

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    gosu \
    jq \
    nginx \
    postgresql \
    redis-server \
    && rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY run.sh /run.sh
RUN chmod 755 /run.sh

EXPOSE 8000

ARG BUILD_ARCH
ARG BUILD_DATE
ARG BUILD_DESCRIPTION
ARG BUILD_NAME
ARG BUILD_REF
ARG BUILD_REPOSITORY
ARG BUILD_VERSION

LABEL \
    io.hass.name="${BUILD_NAME}" \
    io.hass.description="${BUILD_DESCRIPTION}" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.type="addon" \
    io.hass.version="${BUILD_VERSION}" \
    org.opencontainers.image.title="${BUILD_NAME}" \
    org.opencontainers.image.description="${BUILD_DESCRIPTION}" \
    org.opencontainers.image.vendor="Home Assistant Community Add-ons" \
    org.opencontainers.image.authors="Repository owner" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.url="https://github.com/${BUILD_REPOSITORY}" \
    org.opencontainers.image.source="https://github.com/${BUILD_REPOSITORY}" \
    org.opencontainers.image.documentation="https://github.com/${BUILD_REPOSITORY}/blob/main/README.md" \
    org.opencontainers.image.created="${BUILD_DATE}" \
    org.opencontainers.image.revision="${BUILD_REF}" \
    org.opencontainers.image.version="${BUILD_VERSION}"

CMD ["/run.sh"]
