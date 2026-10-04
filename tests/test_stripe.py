"""Stripe payment links: paid grace period, webhook events, and secret lockdown."""
import json
import os
import time

import pytest

pytest.importorskip("psycopg")

DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")

MONTHLY = "price_1UMuSQHcbGkfjKgmtUM0PxPv"


def _user(cur, email):
    cur.execute(
        "insert into auth.users (id, email) values (gen_random_uuid(), %s) returning id",
        (email,),
    )
    return cur.fetchone()[0]


def _event(eid, kind, obj):
    return json.dumps({"id": eid, "type": kind, "data": {"object": obj}})


def test_stripe_webhook_grace_and_secrets():
    import psycopg

    from scripts.seed import main as seed_main

    seed_main()
    period = int(time.time()) + 30 * 24 * 3600
    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            ada = _user(cur, "ada-stripe@example.com")
            bea = _user(cur, "bea-stripe@example.com")

            cur.execute("set role anon")
            cur.execute("savepoint secrets")
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                cur.execute("select * from app_secrets")
            cur.execute("rollback to savepoint secrets")
            cur.execute("reset role")

            cur.execute("set role authenticated")
            cur.execute("savepoint no_event")
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                cur.execute("select apply_stripe_event('{}'::jsonb)")
            cur.execute("rollback to savepoint no_event")
            cur.execute("reset role")

            cur.execute(
                "select apply_stripe_event(%s::jsonb)",
                (_event("evt_cs", "checkout.session.completed", {
                    "id": "cs_ada",
                    "mode": "subscription",
                    "client_reference_id": str(ada),
                    "customer": "cus_ada",
                    "subscription": "sub_ada",
                    "payment_status": "paid",
                    "amount_total": 4900,
                    "currency": "usd",
                }),),
            )
            cur.execute(
                "select apply_stripe_event(%s::jsonb)",
                (_event("evt_sub", "customer.subscription.updated", {
                    "id": "sub_ada",
                    "customer": "cus_ada",
                    "status": "active",
                    "current_period_end": period,
                    "items": {"data": [{"price": {"id": MONTHLY}, "current_period_end": period}]},
                }),),
            )
            cur.execute("select is_paid(%s)", (ada,))
            assert cur.fetchone()[0] is True
            cur.execute("select plan, price_id, stripe_customer_id from subscriptions where profile_id = %s", (ada,))
            assert cur.fetchone() == ("monthly", MONTHLY, "cus_ada")

            cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (str(ada),))
            cur.execute("set role authenticated")
            cur.execute("select my_billing()")
            billing = cur.fetchone()[0]
            assert billing["plan"] == "Monthly" and billing["tier"] == "paid"
            assert billing["price_label"] == "$49/month"
            assert billing["payment_failed"] is False and billing["manage_card"] is True
            assert "$49" in billing["next_charge_label"]
            cur.execute("reset role")

            cur.execute(
                "select apply_stripe_event(%s::jsonb)",
                (_event("evt_fail", "invoice.payment_failed", {
                    "id": "in_fail",
                    "customer": "cus_ada",
                    "subscription": "sub_ada",
                    "amount_due": 4900,
                    "currency": "usd",
                    "status": "open",
                    "hosted_invoice_url": "https://pay.stripe.com/invoice/test",
                    "created": int(time.time()),
                    "lines": {"data": [{"price": {"id": MONTHLY}}]},
                }),),
            )
            cur.execute("select is_paid(%s), payment_failed_at is not null from subscriptions where profile_id = %s", (ada, ada))
            still_paid, failed = cur.fetchone()
            assert still_paid is True and failed is True

            cur.execute(
                "update subscriptions set payment_failed_at = now() - interval '25 hours' where profile_id = %s",
                (ada,),
            )
            cur.execute("select is_paid(%s)", (ada,))
            assert cur.fetchone()[0] is False
            cur.execute("select downgrade_lapsed_payments()")
            assert cur.fetchone()[0] == 1
            cur.execute("select status from subscriptions where profile_id = %s", (ada,))
            assert cur.fetchone()[0] == "unpaid"

            cur.execute(
                "select apply_stripe_event(%s::jsonb)",
                (_event("evt_paid", "invoice.paid", {
                    "id": "in_paid",
                    "customer": "cus_ada",
                    "subscription": "sub_ada",
                    "amount_paid": 4900,
                    "currency": "usd",
                    "status": "paid",
                    "hosted_invoice_url": "https://pay.stripe.com/invoice/paid",
                    "created": int(time.time()),
                    "period_end": period,
                    "lines": {"data": [{"price": {"id": MONTHLY}, "period": {"end": period}}]},
                }),),
            )
            cur.execute("select status, payment_failed_at is null from subscriptions where profile_id = %s", (ada,))
            assert cur.fetchone() == ("active", True)
            cur.execute("select is_paid(%s)", (ada,))
            assert cur.fetchone()[0] is True
            cur.execute("select count(*), max(status), max(amount) from payments where profile_id = %s", (ada,))
            assert cur.fetchone() == (2, "paid", 4900)

            cur.execute(
                "select apply_stripe_event(%s::jsonb)",
                (_event("evt_paid", "invoice.paid", {
                    "id": "in_paid",
                    "customer": "cus_ada",
                    "subscription": "sub_ada",
                    "amount_paid": 4900,
                    "currency": "usd",
                    "status": "paid",
                }),),
            )
            cur.execute("select count(*) from payments where profile_id = %s", (ada,))
            assert cur.fetchone()[0] == 2

            cur.execute(
                "select apply_stripe_event(%s::jsonb)",
                (_event("evt_dollar", "checkout.session.completed", {
                    "id": "cs_bea",
                    "mode": "payment",
                    "client_reference_id": str(bea),
                    "customer": "cus_bea",
                    "amount_total": 100,
                    "currency": "usd",
                    "payment_status": "paid",
                }),),
            )
            cur.execute("select count(*) from subscriptions where profile_id = %s", (bea,))
            assert cur.fetchone()[0] == 0
            cur.execute("select is_paid(%s)", (bea,))
            assert cur.fetchone()[0] is False
            cur.execute("select amount, description, status from payments where profile_id = %s", (bea,))
            assert cur.fetchone() == (100, "$1 test", "paid")

            cur.execute(
                "select apply_stripe_event(%s::jsonb)",
                (_event("evt_del", "customer.subscription.deleted", {
                    "id": "sub_ada",
                    "customer": "cus_ada",
                    "status": "canceled",
                }),),
            )
            cur.execute("select status from subscriptions where profile_id = %s", (ada,))
            assert cur.fetchone()[0] == "canceled"
            cur.execute("select is_paid(%s)", (ada,))
            assert cur.fetchone()[0] is False

            cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (str(bea),))
            cur.execute("set role authenticated")
            cur.execute("select count(*) from payments")
            assert cur.fetchone()[0] == 1
        conn.rollback()
