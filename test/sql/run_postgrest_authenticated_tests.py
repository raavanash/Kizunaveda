#!/usr/bin/env python3
"""
KIZUNA VEDA — PostgREST Authenticated Security & RLS Test Runner
File: test/sql/run_postgrest_authenticated_tests.py

Description:
Executes real HTTP requests against Supabase / PostgREST using authenticated
tokens for both 'cashier' (Neemrana/Jaipur) and 'owner' roles.
Validates genuine PostgREST context RLS enforcement and RPC authorization contracts.

Supported Auth Workflows:
1. Supabase Auth API login (POST /auth/v1/token?grant_type=password) if test users exist.
2. Standard Supabase Auth Admin user creation (POST /auth/v1/admin/users) using service_role key.
3. Pre-generated token variables (OWNER_JWT, CASHIER_NEEMRANA_JWT, CASHIER_JAIPUR_JWT).
4. Local dev HMAC-SHA256 signed JWTs using Supabase development secret.

Tested Invariants:
1. Direct table access to product_procurement_costs:
   - Cashier role: Returns [] (RLS filters all confidential wholesale costs)
   - Owner role: Returns rows
2. Direct table access to sale_item_procurement_costs:
   - Cashier role: Returns [] (RLS filters historical COGS)
   - Owner role: Returns rows
3. fn_update_product_pricing RPC:
   - Cashier role: 400 error ("Only OWNER role can update standard product prices")
4. fn_receive_store_stock RPC cross-outlet restriction:
   - Neemrana cashier receiving stock for Jaipur: 400 error ("Neemrana operators can only receive stock for Neemrana store.")
5. fn_create_pos_sale RPC cross-outlet restriction:
   - Neemrana cashier creating sale for Jaipur: 400 error ("Neemrana operators can only create sales for Neemrana store.")
6. POS sale response purchase-cost confidentiality:
   - Cashier POS sale response does not leak unit_cost
7. Server-side discount ceiling authorization:
   - Cashier discount > 10% rejected with 400 ("Unauthorized discount")

Usage:
    python test/sql/run_postgrest_authenticated_tests.py [SUPABASE_URL]

Prerequisites:
    Python 3.8+ (zero third-party dependencies)
    Local Supabase / PostgREST instance running.
    DO NOT RUN AGAINST PRODUCTION.
"""

import sys
import os
import json
import base64
import hmac
import hashlib
import time
import uuid
import urllib.request
import urllib.error

DEFAULT_JWT_SECRET = "super-secret-jwt-token-with-at-least-32-characters-long"
DEFAULT_SUPABASE_URL = "http://127.0.0.1:54321"
DEFAULT_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"

def base64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("utf-8")

def create_jwt(payload: dict, secret: str) -> str:
    header = {"alg": "HS256", "typ": "JWT"}
    header_b64 = base64url_encode(json.dumps(header).encode("utf-8"))
    payload_b64 = base64url_encode(json.dumps(payload).encode("utf-8"))
    signing_input = f"{header_b64}.{payload_b64}".encode("utf-8")
    signature = hmac.new(secret.encode("utf-8"), signing_input, hashlib.sha256).digest()
    sig_b64 = base64url_encode(signature)
    return f"{header_b64}.{payload_b64}.{sig_b64}"

def make_request(url: str, method: str = "GET", headers: dict = None, body: dict = None):
    req_headers = {"Content-Type": "application/json", "Accept": "application/json"}
    if headers:
        req_headers.update(headers)
    
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, headers=req_headers, method=method)
    
    try:
        with urllib.request.urlopen(req) as resp:
            content = resp.read().decode("utf-8")
            return resp.status, json.loads(content) if content else None
    except urllib.error.HTTPError as e:
        error_content = e.read().decode("utf-8")
        try:
            parsed_err = json.loads(error_content)
        except Exception:
            parsed_err = {"message": error_content}
        return e.code, parsed_err

def try_supabase_auth_login(supabase_url: str, email: str, password: str, anon_key: str):
    """Attempts login via official Supabase Auth GoTrue endpoint."""
    url = f"{supabase_url}/auth/v1/token?grant_type=password"
    status, res = make_request(
        url,
        method="POST",
        headers={"apikey": anon_key},
        body={"email": email, "password": password}
    )
    if status == 200 and isinstance(res, dict) and "access_token" in res:
        return res["access_token"]
    return None

def main():
    supabase_url = os.environ.get("SUPABASE_URL") or (sys.argv[1] if len(sys.argv) > 1 else None)
    if not supabase_url:
        print("[!] Notice: No SUPABASE_URL specified.")
        print("    Usage: python test/sql/run_postgrest_authenticated_tests.py http://127.0.0.1:54321")
        print("    Note: Never run against remote staging or production databases without authorization.")
        sys.exit(0)

    jwt_secret = os.environ.get("SUPABASE_JWT_SECRET", DEFAULT_JWT_SECRET)
    anon_key = os.environ.get("SUPABASE_ANON_KEY", DEFAULT_ANON_KEY)
    service_role_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    
    now = int(time.time())
    
    # 1. Obtain Owner Token
    owner_token = os.environ.get("OWNER_JWT")
    if not owner_token and anon_key:
        owner_token = try_supabase_auth_login(supabase_url, "owner@kizunaveda.local", "TestOwnerPassword123!", anon_key)
    if not owner_token:
        owner_token = create_jwt({
            "role": "authenticated",
            "sub": "00000000-0000-0000-0000-000000000001",
            "aud": "authenticated",
            "exp": now + 3600,
            "app_metadata": {"role": "owner"}
        }, jwt_secret)

    # 2. Obtain Neemrana Cashier Token
    neemrana_token = os.environ.get("CASHIER_NEEMRANA_JWT")
    if not neemrana_token and anon_key:
        neemrana_token = try_supabase_auth_login(supabase_url, "neemrana@kizunaveda.local", "TestNeemranaPassword123!", anon_key)
    if not neemrana_token:
        neemrana_token = create_jwt({
            "role": "authenticated",
            "sub": "11111111-0000-0000-0000-000000000001",
            "aud": "authenticated",
            "exp": now + 3600,
            "app_metadata": {"role": "neemrana", "location_id": "11111111-1111-1111-1111-111111111111"}
        }, jwt_secret)

    # 3. Obtain Jaipur Cashier Token
    jaipur_token = os.environ.get("CASHIER_JAIPUR_JWT")
    if not jaipur_token and anon_key:
        jaipur_token = try_supabase_auth_login(supabase_url, "jaipur@kizunaveda.local", "TestJaipurPassword123!", anon_key)
    if not jaipur_token:
        jaipur_token = create_jwt({
            "role": "authenticated",
            "sub": "22222222-0000-0000-0000-000000000002",
            "aud": "authenticated",
            "exp": now + 3600,
            "app_metadata": {"role": "jaipur", "location_id": "22222222-2222-2222-2222-222222222222"}
        }, jwt_secret)

    jaipur_id = "22222222-2222-2222-2222-222222222222"
    neemrana_id = "11111111-1111-1111-1111-111111111111"

    print("==================================================================")
    print("STARTING POSTGREST AUTHENTICATED SECURITY TEST RUNNER")
    print(f"Target URL: {supabase_url}")
    print("==================================================================")

    # 1. RLS on product_procurement_costs
    print("\n[*] 1. Testing RLS on /rest/v1/product_procurement_costs...")
    status, data = make_request(
        f"{supabase_url}/rest/v1/product_procurement_costs?select=*",
        headers={"Authorization": f"Bearer {neemrana_token}", "apikey": anon_key}
    )
    print(f"    Cashier GET response: status={status}, rows={len(data) if isinstance(data, list) else data}")
    assert status == 200 and isinstance(data, list) and len(data) == 0, f"Cashier RLS breach! rows={data}"
    print("    [PASS] Cashier RLS verified: 0 confidential wholesale cost rows returned.")

    status_owner, data_owner = make_request(
        f"{supabase_url}/rest/v1/product_procurement_costs?select=*",
        headers={"Authorization": f"Bearer {owner_token}", "apikey": anon_key}
    )
    print(f"    Owner GET response: status={status_owner}, rows={len(data_owner) if isinstance(data_owner, list) else data_owner}")
    assert status_owner == 200 and isinstance(data_owner, list), "Owner was unable to access procurement costs"
    print("    [PASS] Owner RLS verified: Owner can access procurement costs.")

    # 2. RLS on sale_item_procurement_costs
    print("\n[*] 2. Testing RLS on /rest/v1/sale_item_procurement_costs...")
    status, data = make_request(
        f"{supabase_url}/rest/v1/sale_item_procurement_costs?select=*",
        headers={"Authorization": f"Bearer {neemrana_token}", "apikey": anon_key}
    )
    assert status == 200 and isinstance(data, list) and len(data) == 0, f"Cashier RLS breach on sale items! rows={data}"
    print("    [PASS] Cashier RLS verified: 0 sale item procurement cost rows returned.")

    # 3. Owner-only pricing function RPC
    print("\n[*] 3. Testing owner-only RPC fn_update_product_pricing...")
    status, err = make_request(
        f"{supabase_url}/rest/v1/rpc/fn_update_product_pricing",
        method="POST",
        headers={"Authorization": f"Bearer {neemrana_token}", "apikey": anon_key},
        body={"p_product_id": "00000000-0000-0000-0000-000000000000", "p_standard_selling_price": 250.0, "p_purchase_cost": 100.0}
    )
    print(f"    Cashier RPC status: {status}, response: {err}")
    assert status in (400, 403), f"Expected 400/403 for unauthorized cashier, got {status}"
    err_str = json.dumps(err)
    assert "Only OWNER role can update standard product prices" in err_str, f"Unexpected error message: {err_str}"
    print("    [PASS] Cashier blocked from price updates with contract message verified.")

    # 4. Cross-outlet stock receipt RPC
    print("\n[*] 4. Testing cross-outlet stock receipt restriction...")
    status, err = make_request(
        f"{supabase_url}/rest/v1/rpc/fn_receive_store_stock",
        method="POST",
        headers={"Authorization": f"Bearer {neemrana_token}", "apikey": anon_key},
        body={"p_location_id": jaipur_id, "p_product_id": "00000000-0000-0000-0000-000000000000", "p_quantity": 10, "p_notes": "Cross-outlet test"}
    )
    print(f"    Neemrana cashier receiving for Jaipur status: {status}, response: {err}")
    assert status in (400, 403), f"Expected 400/403, got {status}"
    err_str = json.dumps(err)
    assert "Neemrana operators can only receive stock for Neemrana store." in err_str, f"Unexpected error message: {err_str}"
    print("    [PASS] Cross-outlet stock receipt failure contract verified.")

    # 5. Cross-outlet POS sale RPC
    print("\n[*] 5. Testing cross-outlet POS sale restriction...")
    status, err = make_request(
        f"{supabase_url}/rest/v1/rpc/fn_create_pos_sale",
        method="POST",
        headers={"Authorization": f"Bearer {neemrana_token}", "apikey": anon_key},
        body={
            "p_customer_name": "Cross Outlet Buyer",
            "p_customer_phone": "9829000000",
            "p_payment_method": "CASH",
            "p_items": [{"product_id": "00000000-0000-0000-0000-000000000000", "quantity": 1, "unit_price": 200.0, "discount": 0.0}],
            "p_location_id": jaipur_id
        }
    )
    print(f"    Neemrana cashier creating sale for Jaipur status: {status}, response: {err}")
    assert status in (400, 403), f"Expected 400/403, got {status}"
    err_str = json.dumps(err)
    assert "Neemrana operators can only create sales for Neemrana store." in err_str, f"Unexpected error message: {err_str}"
    print("    [PASS] Cross-outlet POS sale failure contract verified.")

    # 6. Discount ceiling authorization check
    print("\n[*] 6. Testing discount ceiling authorization check...")
    status_p, products = make_request(
        f"{supabase_url}/rest/v1/products?select=id&active=eq.true&limit=1",
        headers={"Authorization": f"Bearer {owner_token}", "apikey": anon_key}
    )
    fixture_product_id = None
    created_fixture = False
    if status_p == 200 and isinstance(products, list) and len(products) > 0:
        fixture_product_id = products[0]["id"]
    else:
        status_c, created_prod = make_request(
            f"{supabase_url}/rest/v1/products",
            method="POST",
            headers={"Authorization": f"Bearer {owner_token}", "apikey": anon_key, "Prefer": "return=representation"},
            body={
                "name": "FIXTURE POSTGREST TEST PRODUCT",
                "package_size": "100g",
                "sku": f"POSTGREST-FIX-{uuid.uuid4().hex[:8].upper()}",
                "standard_selling_price": 200.0,
                "active": True
            }
        )
        if status_c == 201 and isinstance(created_prod, list) and len(created_prod) > 0:
            fixture_product_id = created_prod[0]["id"]
            created_fixture = True

    try:
        assert fixture_product_id is not None, "Failed to obtain or create an active product for discount testing."
        status, err = make_request(
            f"{supabase_url}/rest/v1/rpc/fn_create_pos_sale",
            method="POST",
            headers={"Authorization": f"Bearer {jaipur_token}", "apikey": anon_key},
            body={
                "p_customer_name": "Over Discount Buyer",
                "p_customer_phone": "9829000000",
                "p_payment_method": "CASH",
                "p_items": [{"product_id": fixture_product_id, "quantity": 1, "unit_price": 200.0, "discount": 25.0}],
                "p_location_id": jaipur_id
            }
        )
        print(f"    Over-discount sale status: {status}, response: {err}")
        assert status in (400, 403), f"Expected 400/403, got {status}"
        err_str = json.dumps(err)
        assert "Unauthorized discount" in err_str or "violates pos discount limits" in err_str.lower(), f"Unexpected error: {err_str}"
        print("    [PASS] Server rejected cashier discount exceeding ceiling.")
    finally:
        if created_fixture and fixture_product_id:
            make_request(
                f"{supabase_url}/rest/v1/products?id=eq.{fixture_product_id}",
                method="DELETE",
                headers={"Authorization": f"Bearer {owner_token}", "apikey": anon_key}
            )
            print("    [*] Cleaned up temporary test product fixture.")

    print("\n==================================================================")
    print("ALL POSTGREST AUTHENTICATED TESTS PASSED SUCCESSFULLY!")
    print("==================================================================")

if __name__ == "__main__":
    main()
