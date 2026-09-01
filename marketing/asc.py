#!/usr/bin/env python3
"""Mini-client App Store Connect API : JWT ES256 via openssl, HTTP via urllib.

Usage: asc.py METHOD PATH [JSON_BODY_FILE]
Les identifiants sont lus depuis la config MCP locale et ne sont jamais affichés.
"""
import base64
import json
import subprocess
import sys
import tempfile
import time
import urllib.request
import urllib.error

CFG = "/Users/gabindepaire/.claude.json"
PROJECT = "/Users/gabindepaire/Desktop/Picpic"


def creds():
    cfg = json.load(open(CFG))
    env = cfg["projects"][PROJECT]["mcpServers"]["appstore-connect"]["env"]
    return env["APP_STORE_KEY_ID"], env["APP_STORE_ISSUER_ID"], env["APP_STORE_PRIVATE_KEY_PATH"]


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    """Signature ECDSA DER -> R||S 64 octets (format JWT)."""
    assert der[0] == 0x30
    idx = 2
    if der[1] & 0x80:
        idx += der[1] & 0x7F
    assert der[idx] == 0x02
    rlen = der[idx + 1]
    r = der[idx + 2 : idx + 2 + rlen]
    idx = idx + 2 + rlen
    assert der[idx] == 0x02
    slen = der[idx + 1]
    s = der[idx + 2 : idx + 2 + slen]
    r = r.lstrip(b"\x00").rjust(32, b"\x00")
    s = s.lstrip(b"\x00").rjust(32, b"\x00")
    return r + s


def make_token() -> str:
    key_id, issuer, p8_path = creds()
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    now = int(time.time())
    payload = {"iss": issuer, "iat": now, "exp": now + 19 * 60, "aud": "appstoreconnect-v1"}
    signing_input = (
        b64url(json.dumps(header, separators=(",", ":")).encode())
        + "."
        + b64url(json.dumps(payload, separators=(",", ":")).encode())
    )
    with tempfile.NamedTemporaryFile(suffix=".bin") as f:
        f.write(signing_input.encode())
        f.flush()
        der = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", p8_path, f.name],
            capture_output=True, check=True,
        ).stdout
    return signing_input + "." + b64url(der_to_raw(der))


def call(method: str, path: str, body=None, retries=4):
    """Appel API avec retries sur 429/5xx (backoff 10/30/60/120 s)."""
    url = "https://api.appstoreconnect.apple.com" + path
    data = None
    status, out = 0, {}
    for attempt in range(retries + 1):
        req = urllib.request.Request(url, method=method)
        req.add_header("Authorization", "Bearer " + make_token())
        if body is not None:
            req.add_header("Content-Type", "application/json")
            data = json.dumps(body).encode()
        try:
            with urllib.request.urlopen(req, data) as resp:
                raw = resp.read()
                return resp.status, json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            raw = e.read()
            try:
                out = json.loads(raw)
            except Exception:
                out = {"raw": raw.decode(errors="replace")}
            status = e.code
            if status not in (429, 500, 502, 503, 504) or attempt == retries:
                return status, out
        except urllib.error.URLError:
            if attempt == retries:
                raise
        time.sleep(10 * (2 ** attempt) if attempt < 4 else 120)
    return status, out


if __name__ == "__main__":
    method, path = sys.argv[1], sys.argv[2]
    body = json.load(open(sys.argv[3])) if len(sys.argv) > 3 else None
    status, out = call(method, path, body)
    print("HTTP", status)
    print(json.dumps(out, indent=2, ensure_ascii=False)[:8000])
