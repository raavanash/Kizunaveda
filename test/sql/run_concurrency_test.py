#!/usr/bin/env python3
"""
KIZUNA VEDA — Automated Multi-Session Concurrency Test Harness
File: test/sql/run_concurrency_test.py

Description:
Connects to a local PostgreSQL / Supabase database using two simultaneous
connections (Session A and Session B) in parallel worker threads to validate:
1. Safe concurrent first-time stock receipts on unstocked products:
   - Both concurrent receipts succeed without unique constraint conflicts.
   - Final stock equals exactly the initial baseline + sum of both receipts.
   - Exactly two correct audit ledger entries recorded in public.stock_adjustments.
2. Safe concurrent submission of the same client_request_id:
   - Serialized via advisory transaction locking.
   - Exactly one sale row created in public.sales.
   - Both sessions receive identical sale JSON responses.
   - Stock decremented exactly once, not double-deducted.

Safety & Repeatability Guarantees:
- Fixture ownership verified using prefix 'CONCURRENCY-FIXTURE-'.
- Pre-checks ensure no real product SKU is overwritten.
- Initial baseline stock is recorded before testing.
- Timeouts (statement_timeout = '20s', lock_timeout = '15s') protect against deadlocks.
- Safe cleanup of test fixtures only, resilient to partial failures.

Usage:
    python test/sql/run_concurrency_test.py [DATABASE_URL]

Prerequisites:
    pip install psycopg2-binary
    Local or staging PostgreSQL instance (e.g. postgresql://postgres:postgres@localhost:54322/postgres)
    DO NOT RUN AGAINST PRODUCTION.
"""

import sys
import os
import time
import threading
import json
import uuid

def print_help():
    print(__doc__)

def main():
    db_url = os.environ.get("DATABASE_URL")
    if len(sys.argv) > 1:
        db_url = sys.argv[1]

    if not db_url:
        print("[!] Notice: No DATABASE_URL provided.")
        print("    To run against a local PostgreSQL database, specify the connection string:")
        print("    python test/sql/run_concurrency_test.py postgresql://postgres:postgres@127.0.0.1:54322/postgres\n")
        print("    Note: As per safety instructions, this test harness must only be run against an explicitly approved disposable test database, never production.")
        sys.exit(0)

    try:
        import psycopg2
    except ImportError:
        print("[!] Error: 'psycopg2' is required to execute multi-session concurrency tests.")
        print("    Install it via: pip install psycopg2-binary")
        sys.exit(1)

    print("==================================================================")
    print("STARTING MULTI-SESSION CONCURRENCY TEST HARNESS")
    print("==================================================================")

    test_product_id = str(uuid.uuid4())
    fixture_name = f"CONCURRENCY-FIXTURE-{test_product_id[:8].upper()}"
    fixture_sku = f"CONC-FIX-{test_product_id[:8].upper()}"
    shared_req_id = str(uuid.uuid4())
    jaipur_id = "22222222-2222-2222-2222-222222222222"

    # Setup connection
    conn_setup = psycopg2.connect(db_url)
    conn_setup.autocommit = True
    cur_setup = conn_setup.cursor()

    try:
        # Pre-check: Safety check on SKU ownership
        print("[*] 0. Safety Pre-Check: Verifying fixture SKU namespace...")
        cur_setup.execute(
            "SELECT count(*) FROM public.products WHERE sku = %s AND name NOT LIKE 'CONCURRENCY-FIXTURE-%%';",
            (fixture_sku,)
        )
        if cur_setup.fetchone()[0] > 0:
            raise RuntimeError(f"SAFETY ABORT: SKU {fixture_sku} is already owned by a non-fixture product!")

        print(f"[*] 1. Setup: Creating dedicated test product fixture ({fixture_name})...")
        cur_setup.execute(
            """
            INSERT INTO public.products (id, name, package_size, sku, standard_selling_price, purchase_cost, active)
            VALUES (%s, %s, '100g', %s, 200.00, 0.00, true);
            """,
            (test_product_id, fixture_name, fixture_sku)
        )
        cur_setup.execute(
            """
            INSERT INTO public.product_procurement_costs (product_id, purchase_cost)
            VALUES (%s, 80.00);
            """,
            (test_product_id,)
        )

        # Baseline stock recording
        cur_setup.execute(
            "SELECT COALESCE(current_quantity, 0) FROM public.store_inventory WHERE location_id = %s AND product_id = %s;",
            (jaipur_id, test_product_id)
        )
        row = cur_setup.fetchone()
        baseline_stock = row[0] if row else 0
        print(f"    Recorded initial baseline stock: {baseline_stock} units")

        # -------------------------------------------------------------
        # TEST 1: Simultaneous First-Time Stock Receipts (50 + 30 units)
        # -------------------------------------------------------------
        print("\n[*] 2. Executing concurrent first-time stock receipts on two connections (50 + 30 units)...")
        results = {}
        barrier = threading.Barrier(2)

        def worker_receipt(session_name, qty):
            try:
                conn = psycopg2.connect(db_url)
                cur = conn.cursor()
                cur.execute("SET statement_timeout = '20s';")
                cur.execute("SET lock_timeout = '15s';")
                cur.execute("SELECT set_config('request.jwt.claims', '{\"role\": \"authenticated\", \"app_metadata\": {\"role\": \"jaipur\"}}', true);")
                barrier.wait()
                cur.execute(
                    "SELECT public.fn_receive_store_stock(%s, %s, %s, %s);",
                    (jaipur_id, test_product_id, qty, f"Concurrent receipt from {session_name}")
                )
                conn.commit()
                results[session_name] = True
            except Exception as e:
                results[session_name] = str(e)
            finally:
                conn.close()

        t1 = threading.Thread(target=worker_receipt, args=("SessionA", 50))
        t2 = threading.Thread(target=worker_receipt, args=("SessionB", 30))
        t1.start()
        t2.start()
        t1.join()
        t2.join()

        print(f"    Receipt Execution Status: {results}")
        for s_name, res in results.items():
            if res is not True:
                raise RuntimeError(f"Concurrent receipt failed in {s_name}: {res}")

        # Assert stock is baseline + 80
        expected_stock = baseline_stock + 80
        cur_setup.execute(
            "SELECT current_quantity FROM public.store_inventory WHERE location_id = %s AND product_id = %s;",
            (jaipur_id, test_product_id)
        )
        final_stock = cur_setup.fetchone()[0]
        print(f"    Final stock after concurrent receipts: {final_stock} (Expected: {expected_stock})")
        assert final_stock == expected_stock, f"Expected {expected_stock} units, got {final_stock}"

        # Assert exactly 2 audit entries in public.stock_adjustments
        cur_setup.execute(
            """
            SELECT previous_quantity, new_quantity, change_quantity, reason
            FROM public.stock_adjustments
            WHERE location_id = %s AND product_id = %s
            ORDER BY created_at ASC, new_quantity ASC;
            """,
            (jaipur_id, test_product_id)
        )
        audit_rows = cur_setup.fetchall()
        print(f"    Audit entries recorded: {len(audit_rows)}")
        assert len(audit_rows) == 2, f"Expected exactly 2 stock_adjustments entries, found {len(audit_rows)}"

        # Verify quantities in audit entries
        row1, row2 = audit_rows[0], audit_rows[1]
        print(f"    Audit Entry 1: prev={row1[0]}, new={row1[1]}, change={row1[2]}, reason={row1[3]}")
        print(f"    Audit Entry 2: prev={row2[0]}, new={row2[1]}, change={row2[2]}, reason={row2[3]}")
        assert row1[3] == 'STOCK_RECEIPT' and row2[3] == 'STOCK_RECEIPT', "Audit reason mismatch"
        assert row1[1] + row2[2] == final_stock or (row1[2] + row2[2] == 80), "Audit quantity math mismatch"
        print("    [PASS] Concurrent first-time receipt passed without conflicts! Total and audit ledger correct.")

        # -------------------------------------------------------------
        # TEST 2: Simultaneous POS Sale Submissions with Same Request ID
        # -------------------------------------------------------------
        print(f"\n[*] 3. Executing concurrent POS sales with identical request ID ({shared_req_id})...")
        sale_results = {}
        barrier_sale = threading.Barrier(2)

        def worker_sale(session_name):
            try:
                conn = psycopg2.connect(db_url)
                cur = conn.cursor()
                cur.execute("SET statement_timeout = '20s';")
                cur.execute("SET lock_timeout = '15s';")
                cur.execute("SELECT set_config('request.jwt.claims', '{\"role\": \"authenticated\", \"app_metadata\": {\"role\": \"jaipur\"}}', true);")
                items_payload = json.dumps([{
                    "product_id": test_product_id,
                    "quantity": 2,
                    "unit_price": 200.00,
                    "discount": 0.00
                }])
                barrier_sale.wait()
                cur.execute(
                    """
                    SELECT public.fn_create_pos_sale(
                        p_customer_name => 'Concurrent Buyer',
                        p_customer_phone => '9829012345',
                        p_payment_method => 'UPI',
                        p_items => %s::jsonb,
                        p_location_id => %s::uuid,
                        p_client_request_id => %s::uuid
                    );
                    """,
                    (items_payload, jaipur_id, shared_req_id)
                )
                sale_data = cur.fetchone()[0]
                conn.commit()
                sale_results[session_name] = sale_data
            except Exception as e:
                sale_results[session_name] = str(e)
            finally:
                conn.close()

        t_sale1 = threading.Thread(target=worker_sale, args=("SessionA",))
        t_sale2 = threading.Thread(target=worker_sale, args=("SessionB",))
        t_sale1.start()
        t_sale2.start()
        t_sale1.join()
        t_sale2.join()

        # Both sessions must return a valid sale
        assert isinstance(sale_results.get("SessionA"), dict), f"SessionA failed: {sale_results.get('SessionA')}"
        assert isinstance(sale_results.get("SessionB"), dict), f"SessionB failed: {sale_results.get('SessionB')}"

        sale_id_a = sale_results["SessionA"].get("id")
        sale_id_b = sale_results["SessionB"].get("id")
        print(f"    Session A Sale ID: {sale_id_a}")
        print(f"    Session B Sale ID: {sale_id_b}")
        assert sale_id_a == sale_id_b, f"Expected same sale ID, got {sale_id_a} and {sale_id_b}"

        # Assert neither cashier response leaked unit_cost
        assert "unit_cost" not in json.dumps(sale_results["SessionA"]), "unit_cost leaked in Session A!"
        assert "unit_cost" not in json.dumps(sale_results["SessionB"]), "unit_cost leaked in Session B!"

        # Assert exactly ONE sale row exists
        cur_setup.execute("SELECT count(*) FROM public.sales WHERE client_request_id = %s;", (shared_req_id,))
        count_sales = cur_setup.fetchone()[0]
        print(f"    Total sales rows in database for request ID: {count_sales}")
        assert count_sales == 1, f"Expected exactly 1 sale row, found {count_sales}"

        # Assert stock decremented by exactly 2 (80 - 2 = 78), NOT double-deducted to 76
        cur_setup.execute(
            "SELECT current_quantity FROM public.store_inventory WHERE location_id = %s AND product_id = %s;",
            (jaipur_id, test_product_id)
        )
        post_sale_stock = cur_setup.fetchone()[0]
        expected_post_sale_stock = expected_stock - 2
        print(f"    Final stock after concurrent sale: {post_sale_stock} (Expected: {expected_post_sale_stock})")
        assert post_sale_stock == expected_post_sale_stock, f"Expected stock {expected_post_sale_stock}, found {post_sale_stock}"
        print("    [PASS] Concurrent idempotency passed! Exactly 1 sale created and 1 stock deduction occurred.")

        print("\n==================================================================")
        print("ALL CONCURRENCY INVARIANTS VERIFIED SUCCESSFULLY!")
        print("==================================================================")

    finally:
        print("\n[*] Cleaning up test fixture records...")
        try:
            # Disable anti-deletion triggers temporarily to clean up test fixtures
            cur_setup.execute("ALTER TABLE public.sale_items DISABLE TRIGGER trg_no_delete_sale_items;")
            cur_setup.execute("ALTER TABLE public.sales DISABLE TRIGGER trg_no_delete_sales;")
            cur_setup.execute(
                """
                DELETE FROM public.sale_items
                WHERE product_id = %s OR sale_id IN (SELECT id FROM public.sales WHERE client_request_id = %s);
                """,
                (test_product_id, shared_req_id)
            )
            cur_setup.execute("DELETE FROM public.sales WHERE client_request_id = %s;", (shared_req_id,))
            cur_setup.execute("ALTER TABLE public.sale_items ENABLE TRIGGER trg_no_delete_sale_items;")
            cur_setup.execute("ALTER TABLE public.sales ENABLE TRIGGER trg_no_delete_sales;")
            cur_setup.execute("DELETE FROM public.stock_adjustments WHERE product_id = %s;", (test_product_id,))
            cur_setup.execute("DELETE FROM public.store_inventory WHERE product_id = %s;", (test_product_id,))
            cur_setup.execute("DELETE FROM public.product_procurement_costs WHERE product_id = %s;", (test_product_id,))
            cur_setup.execute(
                "DELETE FROM public.products WHERE id = %s AND name LIKE 'CONCURRENCY-FIXTURE-%%';",
                (test_product_id,)
            )
            print("[*] Cleanup complete: Test fixture deleted safely.")
        except Exception as e:
            print(f"[!] Cleanup warning: {e}")
        conn_setup.close()

if __name__ == "__main__":
    main()
