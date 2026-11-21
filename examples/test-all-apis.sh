#!/usr/bin/env bash
# Smoke-test every API exposed by examples/basic-server.ts (createServer default routes).
# Usage: BASE=http://localhost:3001 ./examples/test-all-apis.sh

set -euo pipefail
BASE="${BASE:-http://localhost:3001}"
RAND="$(openssl rand -hex 4)"
USER_ID="$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
json() { python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])))' "$1"; }
SHORT_CODE="t-${RAND}"
WEBHOOK_URL="https://httpbin.org/post"

hr() { echo ""; echo "======== $1 ========"; }
ok() { echo "HTTP $1"; }

hr "Health"
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' "$BASE/health")"
cat /tmp/lf_out.json; echo
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' "$BASE/health/ready")"
cat /tmp/lf_out.json; echo
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' "$BASE/api/sdk/v1/health")"
cat /tmp/lf_out.json; echo

hr "Well-known (empty without IOS/Android env)"
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' "$BASE/.well-known/apple-app-site-association")"
head -c 200 /tmp/lf_out.json; echo
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' "$BASE/.well-known/assetlinks.json")"
head -c 200 /tmp/lf_out.json; echo

hr "Templates — POST create"
BODY="$(json "{\"userId\":\"$USER_ID\",\"name\":\"tpl-$RAND\",\"description\":\"random $RAND\",\"isDefault\":false}")"
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' -X POST "$BASE/api/templates" \
  -H 'Content-Type: application/json' -d "$BODY")"
TEMPLATE_ID="$(python3 -c "import json; print(json.load(open('/tmp/lf_out.json'))['id'])" 2>/dev/null || true)"
TEMPLATE_SLUG="$(python3 -c "import json; print(json.load(open('/tmp/lf_out.json'))['slug'])" 2>/dev/null || true)"
cat /tmp/lf_out.json; echo

hr "Templates — GET list / GET one"
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' "$BASE/api/templates?userId=$USER_ID")"
echo "count: $(python3 -c "import json; print(len(json.load(open('/tmp/lf_out.json'))))")"
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' "$BASE/api/templates/$TEMPLATE_ID")"
head -c 300 /tmp/lf_out.json; echo

hr "Links — POST create"
BODY="$(python3 - <<PY
import json
print(json.dumps({
  "userId": "$USER_ID",
  "originalUrl": f"https://example.com/p/$RAND",
  "title": f"link-$RAND",
  "customCode": "$SHORT_CODE",
  "utmParameters": {"source": f"test-$RAND", "medium": "curl", "campaign": "smoke"},
  "webFallbackUrl": f"https://example.com/fallback/$RAND",
}))
PY
)"
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' -X POST "$BASE/api/links" \
  -H 'Content-Type: application/json' -d "$BODY")"
LINK_ID="$(python3 -c "import json; print(json.load(open('/tmp/lf_out.json'))['id'])")"
cat /tmp/lf_out.json; echo

hr "Links — GET list / GET one / PUT / duplicate"
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' "$BASE/api/links?userId=$USER_ID")"
echo "links: $(python3 -c "import json; print(len(json.load(open('/tmp/lf_out.json'))))")"
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' "$BASE/api/links/$LINK_ID?userId=$USER_ID")"
head -c 200 /tmp/lf_out.json; echo
BODY="$(json "{\"title\":\"updated-$RAND\"}")"
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' -X PUT "$BASE/api/links/$LINK_ID?userId=$USER_ID" \
  -H 'Content-Type: application/json' -d "$BODY")"
head -c 200 /tmp/lf_out.json; echo
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' -X POST "$BASE/api/links/$LINK_ID/duplicate?userId=$USER_ID")"
DUP_ID="$(python3 -c "import json; print(json.load(open('/tmp/lf_out.json'))['id'])" 2>/dev/null || echo "")"
echo "duplicate id: $DUP_ID"

hr "Public redirect (records click)"
ok "$(curl -s -o /dev/null -w '%{http_code}' -A "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) LinkFortyTest/$RAND" "$BASE/$SHORT_CODE")"

hr "Analytics"
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' "$BASE/api/analytics/overview?userId=$USER_ID&days=7")"
head -c 400 /tmp/lf_out.json; echo
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' "$BASE/api/analytics/links/$LINK_ID?userId=$USER_ID&days=7")"
head -c 400 /tmp/lf_out.json; echo

hr "QR code"
ok "$(curl -s -o /tmp/lf_qr.png -w '%{http_code}' "$BASE/api/links/$LINK_ID/qr?format=png&size=256&color=%23${RAND:0:6}")"
echo "png bytes: $(wc -c </tmp/lf_qr.png)"
ok "$(curl -s -o /tmp/lf_qr.svg -w '%{http_code}' "$BASE/api/links/$LINK_ID/qr?format=svg&size=256")"
head -c 80 /tmp/lf_qr.svg; echo

hr "SDK resolve"
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' "$BASE/api/sdk/v1/resolve/$SHORT_CODE")"
head -c 300 /tmp/lf_out.json; echo

hr "SDK install + event"
BODY="$(python3 - <<PY
import json
print(json.dumps({
  "userAgent": f"LinkFortyTest/$RAND Mozilla/5.0",
  "timezone": "Asia/Kolkata",
  "language": "en-IN",
  "screenWidth": 390,
  "screenHeight": 844,
  "platform": "ios",
  "platformVersion": "17.0",
  "deviceId": f"device-$RAND",
  "sdkName": "curl-smoke",
  "sdkVersion": f"1.0.0-$RAND",
}))
PY
)"
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' -X POST "$BASE/api/sdk/v1/install" \
  -H 'Content-Type: application/json' -d "$BODY")"
INSTALL_ID="$(python3 -c "import json; print(json.load(open('/tmp/lf_out.json'))['installId'])")"
cat /tmp/lf_out.json; echo
CLIENT_EVENT_ID="$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
BODY="$(python3 - <<PY
import json
print(json.dumps({
  "installId": "$INSTALL_ID",
  "eventName": f"signup_$RAND",
  "eventData": {"plan": "pro", "trial": True},
  "clientEventId": "$CLIENT_EVENT_ID",
  "sdkName": "curl-smoke",
  "sdkVersion": "1.0.0",
}))
PY
)"
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' -X POST "$BASE/api/sdk/v1/event" \
  -H 'Content-Type: application/json' -d "$BODY")"
cat /tmp/lf_out.json; echo

hr "SDK attribution (404 expected if no fingerprint row)"
FP="$(openssl rand -hex 32)"
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' "$BASE/api/sdk/v1/attribution/$FP")"
cat /tmp/lf_out.json; echo

hr "Webhooks"
BODY="$(python3 - <<PY
import json
print(json.dumps({
  "userId": "$USER_ID",
  "name": f"wh-$RAND",
  "url": "$WEBHOOK_URL",
  "events": ["click_event", "install_event"],
}))
PY
)"
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' -X POST "$BASE/api/webhooks" \
  -H 'Content-Type: application/json' -d "$BODY")"
WEBHOOK_ID="$(python3 -c "import json; print(json.load(open('/tmp/lf_out.json'))['id'])")"
cat /tmp/lf_out.json; echo
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' "$BASE/api/webhooks?userId=$USER_ID")"
echo "webhooks: $(python3 -c "import json; print(len(json.load(open('/tmp/lf_out.json'))))")"
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' "$BASE/api/webhooks/$WEBHOOK_ID?userId=$USER_ID")"
head -c 200 /tmp/lf_out.json; echo
BODY="$(json "{\"name\":\"wh-updated-$RAND\",\"isActive\":true}")"
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' -X PUT "$BASE/api/webhooks/$WEBHOOK_ID?userId=$USER_ID" \
  -H 'Content-Type: application/json' -d "$BODY")"
head -c 200 /tmp/lf_out.json; echo
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' -X POST "$BASE/api/webhooks/$WEBHOOK_ID/test?userId=$USER_ID")"
cat /tmp/lf_out.json; echo

hr "Templates — set-default / PUT / DELETE link dup / DELETE webhook / DELETE template"
if [[ -n "$TEMPLATE_ID" ]]; then
  ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' -X PUT "$BASE/api/templates/$TEMPLATE_ID/set-default?userId=$USER_ID")"
  head -c 200 /tmp/lf_out.json; echo
fi
if [[ -n "$DUP_ID" ]]; then
  ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' -X DELETE "$BASE/api/links/$DUP_ID?userId=$USER_ID")"
  cat /tmp/lf_out.json; echo
fi
ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' -X DELETE "$BASE/api/webhooks/$WEBHOOK_ID?userId=$USER_ID")"
cat /tmp/lf_out.json; echo
if [[ -n "$TEMPLATE_ID" ]]; then
  ok "$(curl -s -o /tmp/lf_out.json -w '%{http_code}' -X DELETE "$BASE/api/templates/$TEMPLATE_ID?userId=$USER_ID")"
  cat /tmp/lf_out.json; echo
fi

echo ""
echo "Done. userId=$USER_ID shortCode=$SHORT_CODE linkId=$LINK_ID"
echo "Note: /api/debug/* and /:shortCode/preview are NOT registered on the default server."
