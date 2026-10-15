#!/usr/bin/env python3
"""
KIZUNA VEDA — V1.7 Store Isolation & Transfers Hardening Database Test Runner
File: test/sql/run_v1_7_isolation_test.py

Description:
Connects to a PostgreSQL / Supabase database and executes the transactional SQL test suite:
test/sql/v1_7_store_isolation_and_security_tests.sql

Tests Verified:
1. Table-level grants & effective privileges (anon=0 privs, authenticated=SELECT only).
2. Owner-only historical transfer read access & Cashier RLS filtering (0 rows).
3. Total rejection of transfer mutations (INSERT, UPDATE, DELETE).
4. Fail-closed behavior & privilege revocation on fn_confirm_jaipur_receipt.
5. Complete operational and inventory isolation (receipts, sales, voids, shortfalls).
6. Cross-store role spoofing rejection (receipts, sales, voids, direct table writes).
7. Zero cross-store inventory contamination and clean rollback.

Usage:
    python test/sql/run_v1_7_isolation_test.py [DATABASE_URL]

Prerequisites:
    pip install psycopg2-binary
    Local or staging PostgreSQL instance.
    DO NOT RUN AGAINST PRODUCTION.
"""

import sys
import os
import psycopg2

def main():
    db_url = os.environ.get("DATABASE_URL")
    if len(sys.argv) > 1:
        db_url = sys.argv[1]

    if not db_url:
        print("[!] Notice: No DATABASE_URL provided.")
        print("    Usage: python test/sql/run_v1_7_isolation_test.py postgresql://postgres:postgres@127.0.0.1:54322/postgres")
        print("    Note: Never execute against production.")
        sys.exit(0)

    sql_file = os.path.join(os.path.dirname(__file__), "v1_7_store_isolation_and_security_tests.sql")
    if not os.path.exists(sql_file):
        print(f"[!] Error: Test file not found at {sql_file}")
        sys.exit(1)

    with open(sql_file, "r", encoding="utf-8") as f:
        sql_content = f.read()

    print("==================================================================")
    print("EXECUTING V1.7 STORE ISOLATION & TRANSFERS SECURITY SUITE")
    print(f"Target: {db_url}")
    print(f"File:   {sql_file}")
    print("==================================================================")

    try:
        conn = psycopg2.connect(db_url)
        conn.autocommit = True
        cur = conn.cursor()

        cur.execute(sql_content)
        for notice in conn.notices:
            print(f"[SQL NOTICE] {notice.strip()}")

        print("\n[PASS] V1.7 Store Isolation & Transfers Hardening Database Test Suite executed completely and rolled back successfully.")
        conn.close()
    except Exception as e:
        print(f"\n[!] SQL Execution Failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
