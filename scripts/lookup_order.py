#!/usr/bin/env python3
"""Confirm a customer's order ID against Apple's App Store Server API.

    scripts/lookup_order.py MXXXXXXXXX --key ~/keys/AuthKey_ABC123.p8 --issuer <issuer-id>

Needs the *In-App Purchase* key (Users and Access > Integrations > In-App Purchase),
not the App Store Connect API key. Key ID is read from the AuthKey_<KEYID>.p8 filename.
Issuer ID may also come from $APP_STORE_IAP_ISSUER_ID.

Scope, so a "not found" is read correctly: this endpoint knows *in-app purchases* for
this bundle id only. An order ID from a free app download, or from another app, or from
another Apple Account, comes back status 1 — that is not proof the customer is lying.
"""
import argparse, base64, json, os, re, sys, time, urllib.error, urllib.request
from datetime import datetime, timezone
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import (decode_dss_signature,
                                                            encode_dss_signature)

BUNDLE_ID = "de.valentinlehmann.swiftnzb"
ASC = "https://api.appstoreconnect.apple.com"
HOSTS = {"production": "https://api.storekit.itunes.apple.com",
         "sandbox": "https://api.storekit-sandbox.itunes.apple.com"}


def b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def unb64url(segment: str) -> bytes:
    return base64.urlsafe_b64decode(segment + "=" * (-len(segment) % 4))


def make_jwt(pem: bytes, key_id: str, issuer: str, bundle_id: str | None = None) -> str:
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    # 20 minutes is the App Store Connect ceiling; stay under it for clock skew.
    payload = {"iss": issuer, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}
    # The bundle id claim is what scopes an In-App Purchase key; an ASC key must not carry it.
    if bundle_id:
        payload["bid"] = bundle_id
    signing_input = f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(payload).encode())}"
    key = serialization.load_pem_private_key(pem, password=None)
    # ES256 wants raw r||s, 32 bytes each; cryptography hands back DER.
    r, s = decode_dss_signature(key.sign(signing_input.encode(), ec.ECDSA(hashes.SHA256())))
    return f"{signing_input}.{b64url(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))}"


def get(url: str, token: str):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        try:
            return e.code, json.loads(body)
        except ValueError:
            return e.code, {"raw": body}


def ms(value):
    if not value:
        return "—"
    return datetime.fromtimestamp(value / 1000, timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")


def show(response):
    # 0 = the order ID is valid and these are its transactions. 1 = no match.
    # 1 covers both "made up" and "real, but not an in-app purchase of this app" — Apple
    # gives no way to tell those apart, so do not read it as proof the customer invented it.
    print(f"  status {response.get('status')} "
          f"({'valid IAP order' if response.get('status') == 0 else 'no IAP match for this app'})")
    for jws in response.get("signedTransactions", []):
        # Read-only display of Apple's own TLS response; the JWS signature is not re-verified.
        t = json.loads(unb64url(jws.split(".")[1]))
        print(f"  - {t.get('productId')}  {t.get('type', 'non-consumable')}")
        print(f"      transaction {t.get('transactionId')}  original {t.get('originalTransactionId')}")
        print(f"      purchased {ms(t.get('purchaseDate'))}  original {ms(t.get('originalPurchaseDate'))}")
        print(f"      expires {ms(t.get('expiresDate'))}  ownership {t.get('inAppOwnershipType')}")
        print(f"      environment {t.get('environment')}  storefront {t.get('storefront')}")
        if t.get("revocationDate"):
            print(f"      REFUNDED {ms(t.get('revocationDate'))} reason {t.get('revocationReason')}")


def builds(token: str, bundle_id: str):
    """Every App Store version and the CFBundleVersion it shipped as.

    This is what `Grandfathering.paywallCutoffBuild` rests on: if any version released before
    the paywall shows a build other than 1, the cutoff is wrong and those customers are locked
    out. Needs an App Store Connect API key, not the In-App Purchase one.
    """
    code, body = get(f"{ASC}/v1/apps?filter[bundleId]={bundle_id}", token)
    if code != 200 or not body.get("data"):
        return print(f"  HTTP {code}: {json.dumps(body)[:300]}")
    app_id = body["data"][0]["id"]
    code, body = get(f"{ASC}/v1/apps/{app_id}/appStoreVersions?limit=50&include=build"
                     # `build` has to be listed here too: fields[] narrows relationships as
                     # well as attributes, so omitting it drops the link and every build reads "?".
                     f"&fields[appStoreVersions]=versionString,appStoreState,createdDate,build"
                     f"&fields[builds]=version,uploadedDate", token)
    if code != 200:
        return print(f"  HTTP {code}: {json.dumps(body)[:300]}")
    build_of = {b["id"]: b["attributes"] for b in body.get("included", [])}
    for v in body["data"]:
        a = v["attributes"]
        rel = (v.get("relationships", {}).get("build", {}).get("data") or {}).get("id")
        b = build_of.get(rel, {})
        print(f"  {a['versionString']:<8} {a.get('appStoreState', ''):<22} "
              f"build {b.get('version', '?'):<14} created {(a.get('createdDate') or '')[:10]}")


def selftest():
    key = ec.generate_private_key(ec.SECP256R1())
    pem = key.private_bytes(serialization.Encoding.PEM,
                            serialization.PrivateFormat.PKCS8,
                            serialization.NoEncryption())
    token = make_jwt(pem, "KEYID", "issuer", BUNDLE_ID)
    head, payload, sig = token.split(".")
    assert json.loads(unb64url(head))["alg"] == "ES256"
    assert json.loads(unb64url(payload))["bid"] == BUNDLE_ID
    assert len(unb64url(sig)) == 64, "ES256 signature must be raw r||s, 64 bytes"
    raw = unb64url(sig)
    key.public_key().verify(
        encode_dss_signature(int.from_bytes(raw[:32], "big"), int.from_bytes(raw[32:], "big")),
        f"{head}.{payload}".encode(), ec.ECDSA(hashes.SHA256()))
    assert ms(1725782400000).endswith("Z") and ms(None) == "—"
    print("selftest ok")


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("order_id", nargs="?", help="order ID from the customer's Apple receipt")
    p.add_argument("--key", help="path to AuthKey_<KEYID>.p8 (In-App Purchase key)")
    p.add_argument("--key-id", help="override the key ID inferred from the filename")
    p.add_argument("--issuer", default=os.environ.get("APP_STORE_IAP_ISSUER_ID"))
    p.add_argument("--bundle-id", default=BUNDLE_ID)
    p.add_argument("--builds", action="store_true",
                   help="list App Store versions and their build numbers (App Store Connect key)")
    p.add_argument("--selftest", action="store_true")
    a = p.parse_args()

    if a.selftest:
        return selftest()
    if not ((a.order_id or a.builds) and a.key and a.issuer):
        p.error("need order_id (or --builds), --key and --issuer")

    # Apple names these AuthKey_<KEYID>.p8 or SubscriptionKey_<KEYID>.p8; key IDs are 10 chars.
    key_id = a.key_id or (re.search(r"[_-]([A-Z0-9]{10})\.p8$", a.key) or [None, None])[1]
    if not key_id:
        p.error("could not read the key ID from the filename; pass --key-id")

    pem = open(os.path.expanduser(a.key), "rb").read()

    if a.builds:
        return builds(make_jwt(pem, key_id, a.issuer), a.bundle_id)

    token = make_jwt(pem, key_id, a.issuer, a.bundle_id)
    for env, host in HOSTS.items():
        print(f"{env}:")
        code, body = get(f"{host}/inApps/v1/lookup/{a.order_id}", token)
        if code == 200:
            show(body)
        elif code == 404:
            print("  404 — no such order ID for this app")
        else:
            print(f"  HTTP {code}: {json.dumps(body)[:300]}")


if __name__ == "__main__":
    main()
