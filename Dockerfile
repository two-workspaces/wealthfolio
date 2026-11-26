# Upstream's web-edition image, pinned. The wrapper adds the Railway entrypoint and the
# tools it needs: argon2 (password -> WF_AUTH_PASSWORD_HASH), su-exec (drop to the
# image's uid 1000 after fixing the volume's owner), openssl (key derivation) and
# busybox-extras (httpd for the notice page when the server can't start).
FROM wealthfolio/wealthfolio:3.13.1

USER root
RUN apk add --no-cache argon2 su-exec openssl busybox-extras

COPY --chmod=0755 railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh

# The entrypoint runs as root only to chown the Railway volume (mounted root-owned),
# then runs wealthfolio-server as uid 1000 like upstream.
ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
