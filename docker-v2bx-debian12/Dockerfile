FROM debian:12-slim

ARG V2BX_VERSION
ARG TARGETARCH=amd64

RUN set -eux; \
    test -n "$V2BX_VERSION"; \
    test "$(dpkg --print-architecture)" = 'amd64'; \
    case "$TARGETARCH" in \
      amd64) v2bx_arch='64' ;; \
      *) echo "Unsupported architecture: $TARGETARCH (only amd64 is supported)" >&2; exit 1 ;; \
    esac; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl unzip; \
    rm -rf /var/lib/apt/lists/*; \
    mkdir -p /usr/local/V2bX /usr/local/share/V2bX; \
    curl --fail --location --retry 3 --silent --show-error \
      "https://github.com/wyx2685/V2bX/releases/download/${V2BX_VERSION}/V2bX-linux-${v2bx_arch}.zip" \
      --output /tmp/v2bx.zip; \
    unzip -q /tmp/v2bx.zip -d /usr/local/V2bX; \
    rm /tmp/v2bx.zip; \
    chmod +x /usr/local/V2bX/V2bX; \
    cp /usr/local/V2bX/geoip.dat /usr/local/V2bX/geosite.dat /usr/local/share/V2bX/

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["server"]
