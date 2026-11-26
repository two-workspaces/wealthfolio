#!/bin/sh
# Maps Railway onto Wealthfolio's web edition (wealthfolio-server):
# - listens on $PORT, keeps everything on the /data volume (owned by uid 1000);
# - WF_PASSWORD (plain, a template secret) becomes the Argon2id WF_AUTH_PASSWORD_HASH
#   upstream requires, with a fresh salt each boot, so changing the variable and
#   redeploying changes the password;
# - WF_SECRET_KEY must decode to exactly 32 bytes; anything else is turned into one
#   with SHA-256 (stable across boots) instead of refusing to start;
# - WF_CORS_ALLOW_ORIGINS defaults to the Railway domain (upstream refuses "*" with auth);
# - if the server exits within 60 s of starting (a bad variable), a notice page is served
#   instead of a crash loop. Later exits pass through so Railway restarts the service.
set -u
log() { echo "[railway] $*"; }

DATA=/data
mkdir -p "$DATA"
# Railway mounts volumes root-owned; upstream runs as 1000:1000.
find "$DATA" ! -user 1000 -exec chown 1000:1000 {} + 2>/dev/null

PORT="${PORT:-8088}"
case "$PORT" in '' | *[!0-9]*) log "PORT=$PORT is not a number, using 8088"; PORT=8088 ;; esac
export WF_LISTEN_ADDR="${WF_LISTEN_ADDR:-0.0.0.0:$PORT}"

# Master key: encrypts saved credentials and signs sessions. Keep it for the life of the data.
if [ -n "${WF_SECRET_KEY_FILE:-}" ]; then
  unset WF_SECRET_KEY
elif [ -z "${WF_SECRET_KEY:-}" ]; then
  f="$DATA/.railway-secret-key"
  if [ ! -s "$f" ]; then
    head -c 32 /dev/urandom | base64 > "$f"
    log "WF_SECRET_KEY is empty: generated a key in $f. Keep it with your backups."
  fi
  chown 1000:1000 "$f"; chmod 600 "$f"
  unset WF_SECRET_KEY
  export WF_SECRET_KEY_FILE="$f"
else
  key="$(printf %s "$WF_SECRET_KEY" | tr -d ' \r\n')"
  canonical="$(printf %s "$key" | base64 -d 2>/dev/null | base64 2>/dev/null | tr -d '\n')"
  bytes="$(printf %s "$key" | base64 -d 2>/dev/null | wc -c)"
  if [ "${#key}" -eq 44 ] && [ "$bytes" -eq 32 ] && [ "$canonical" = "$key" ]; then
    :
  elif [ "${#key}" -eq 32 ] && printf %s "$key" | grep -q '[^A-Za-z0-9+/=]'; then
    : # upstream takes a 32-character non-base64 string as the raw key
  else
    key="$(printf %s "$key" | openssl dgst -sha256 -binary | base64)"
    log "WF_SECRET_KEY isn't a base64 32-byte key: using its SHA-256 instead (same every boot)."
  fi
  export WF_SECRET_KEY="$key"
fi

# Login. An explicit WF_AUTH_PASSWORD_HASH wins; OIDC-only setups can leave both empty
# and set WF_AUTH_REQUIRED=false only behind their own auth proxy.
if [ -z "${WF_AUTH_PASSWORD_HASH:-}" ] && [ "${WF_AUTH_REQUIRED:-true}" != "false" ]; then
  pw="${WF_PASSWORD:-}"
  if [ -z "$pw" ]; then
    f="$DATA/.railway-password"
    if [ ! -s "$f" ]; then
      head -c 18 /dev/urandom | base64 | tr -d '/+=\n' > "$f"
      chmod 600 "$f"
      log "WF_PASSWORD is empty: generated the password $(cat "$f") (saved in $f). Set WF_PASSWORD and redeploy to choose your own."
    else
      log "WF_PASSWORD is empty: signing in with the password saved in $f."
    fi
    pw="$(cat "$f")"
  fi
  salt="$(head -c 16 /dev/urandom | base64)"
  if hash="$(printf %s "$pw" | argon2 "$salt" -id -e -k 19456 -t 2 -p 1)"; then
    export WF_AUTH_PASSWORD_HASH="$hash"
  else
    log "could not hash WF_PASSWORD"
  fi
fi
unset WF_PASSWORD pw

if [ -z "${WF_CORS_ALLOW_ORIGINS:-}" ] || [ "$WF_CORS_ALLOW_ORIGINS" = "*" ]; then
  if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
    export WF_CORS_ALLOW_ORIGINS="https://$RAILWAY_PUBLIC_DOMAIN"
  else
    export WF_CORS_ALLOW_ORIGINS="http://localhost:$PORT"
    log "no public domain: generate one under Settings > Networking, then redeploy."
  fi
fi

case "${WF_COOKIE_SECURE:-auto}" in
  auto | true | 1 | yes | false | 0 | no) ;;
  *) log "WF_COOKIE_SECURE=$WF_COOKIE_SECURE is not auto/true/false, using auto"; export WF_COOKIE_SECURE=auto ;;
esac

notice() {
  dir=/tmp/notice
  mkdir -p "$dir/api/v1"
  echo ok > "$dir/api/v1/healthz"
  cat > "$dir/index.html" <<EOF
<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Wealthfolio is not running</title>
<body style="font:16px/1.5 system-ui,sans-serif;max-width:40em;margin:4em auto;padding:0 1em">
<h1>Wealthfolio is not running</h1>
<p>The server stopped right after starting ($1). Open this service's <b>Deploy Logs</b> on Railway:
the line above "[railway] showing a notice page" says which variable to fix.
Fix it under <b>Variables</b>, then redeploy. Your data on the volume is untouched.</p>
</body>
EOF
  log "showing a notice page on port $PORT until the variables are fixed"
  exec httpd -f -p "0.0.0.0:$PORT" -h "$dir"
}

started=$(date +%s)
su-exec 1000:1000 /usr/local/bin/wealthfolio-server &
pid=$!
stopping=
trap 'stopping=1; kill -TERM "$pid" 2>/dev/null' TERM INT
wait "$pid"; rc=$?
# wait returns early when the trap fires; wait again for the real exit status.
while kill -0 "$pid" 2>/dev/null; do wait "$pid"; rc=$?; done
[ -n "$stopping" ] && exit "$rc"
if [ $(( $(date +%s) - started )) -lt 60 ]; then
  notice "exit code $rc"
fi
exit "$rc"
