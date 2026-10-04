"""Watchlist cap, signup profile, and review visibility."""
import os

import pytest

pytest.importorskip("psycopg")

DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


def _user(cur, email):
    cur.execute(
        "insert into auth.users (id, email) values (gen_random_uuid(), %s) returning id",
        (email,),
    )
    return cur.fetchone()[0]


def test_watchlist_cap_profile_and_review_rls():
    import psycopg

    from scripts.seed import main as seed_main

    seed_main()
    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            ada = _user(cur, "ada@example.com")
            bea = _user(cur, "bea@example.com")
            cur.execute("select display_name from profiles where id = %s", (ada,))
            assert cur.fetchone()[0] == "ada"
            cur.execute(
                "select new_legal_matter, regulatory_record, partner_exit, score_change from alert_preferences where profile_id = %s",
                (ada,),
            )
            assert cur.fetchone() == (True, True, False, True)

            cur.execute(
                """
                insert into firms (slug, name, published)
                select 'cap-' || g, 'Cap ' || g, true
                from generate_series(1, 101) g
                """
            )
            cur.execute("select id from firms where slug like 'cap-%'")
            firm_ids = [row[0] for row in cur.fetchall()]
            assert len(firm_ids) == 101
            for firm_id in firm_ids[:100]:
                cur.execute(
                    "insert into watchlist (profile_id, firm_id) values (%s, %s)",
                    (ada, firm_id),
                )
            cur.execute("savepoint over_cap")
            with pytest.raises(psycopg.errors.CheckViolation):
                cur.execute(
                    "insert into watchlist (profile_id, firm_id) values (%s, %s)",
                    (ada, firm_ids[100]),
                )
            cur.execute("rollback to savepoint over_cap")
            cur.execute("select count(*) from watchlist where profile_id = %s", (ada,))
            assert cur.fetchone()[0] == 100
            cur.execute("delete from firms where slug like 'cap-%'")

            cur.execute("select id from firms where slug = 'a16z'")
            a16z = cur.fetchone()[0]
            cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (str(ada),))
            cur.execute("set role authenticated")
            cur.execute(
                "insert into watchlist (profile_id, firm_id) values (%s, %s)",
                (ada, a16z),
            )
            cur.execute("savepoint steal")
            with pytest.raises(psycopg.Error):
                cur.execute(
                    "insert into watchlist (profile_id, firm_id) values (%s, %s)",
                    (bea, a16z),
                )
            cur.execute("rollback to savepoint steal")
            cur.execute(
                """
                insert into reviews (
                  firm_id, profile_id, body, moderation_status, anonymous,
                  role_label, round_label, would_again, verification_method
                ) values (%s, %s, 'kept private', 'pending', true, 'Founder / CEO', 'Seed', true, 'linkedin')
                returning id
                """,
                (a16z, ada),
            )
            review_id = cur.fetchone()[0]
            cur.execute(
                "insert into review_ratings (review_id, dimension, score) values (%s, 'transparency', 4)",
                (review_id,),
            )
            cur.execute("savepoint approve")
            with pytest.raises(psycopg.Error):
                cur.execute(
                    "insert into reviews (firm_id, profile_id, moderation_status) values (%s, %s, 'approved')",
                    (a16z, ada),
                )
            cur.execute("rollback to savepoint approve")
            cur.execute("reset role")

            cur.execute("set role anon")
            cur.execute("select count(*) from reviews where id = %s", (review_id,))
            assert cur.fetchone()[0] == 0
            cur.execute("savepoint anon_wl")
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                cur.execute("select count(*) from watchlist")
            cur.execute("rollback to savepoint anon_wl")
            cur.execute("reset role")

            cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (str(bea),))
            cur.execute("set role authenticated")
            cur.execute("select count(*) from reviews where id = %s", (review_id,))
            assert cur.fetchone()[0] == 0
            cur.execute("select count(*) from watchlist")
            assert cur.fetchone()[0] == 0
            cur.execute("reset role")

            cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (str(ada),))
            cur.execute("set role authenticated")
            cur.execute("select body from reviews where id = %s", (review_id,))
            assert cur.fetchone()[0] == "kept private"

            cur.execute("savepoint server_fields")
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                cur.execute(
                    """
                    insert into reviews (firm_id, profile_id, first_hand, verification_status)
                    values (%s, %s, true, 'verified')
                    """,
                    (a16z, ada),
                )
            cur.execute("rollback to savepoint server_fields")
            cur.execute("savepoint bad_link")
            with pytest.raises(psycopg.errors.CheckViolation):
                cur.execute(
                    "insert into reviews (firm_id, profile_id, linkedin_url) values (%s, %s, 'https://example.com/in/ada')",
                    (a16z, ada),
                )
            cur.execute("rollback to savepoint bad_link")
            cur.execute("savepoint bad_score")
            with pytest.raises(psycopg.errors.CheckViolation):
                cur.execute(
                    "insert into reviews (firm_id, profile_id, honesty) values (%s, %s, 6)",
                    (a16z, ada),
                )
            cur.execute("rollback to savepoint bad_score")
            cur.execute(
                """
                insert into reviews (
                  firm_id, profile_id, connection_type, linkedin_url, honesty,
                  support_after_check, founder_friendly_terms, responsiveness, hard_times,
                  round_label, anonymous, moderation_status
                ) values (
                  %s, %s, 'founder_ceo', 'https://www.linkedin.com/in/ada-example', 4,
                  3, 5, 2, 1, 'Seed', true, 'pending'
                )
                returning id, first_hand, verification_status, moderation_status
                """,
                (a16z, ada),
            )
            share_id, first_hand, verification, moderation = cur.fetchone()
            assert (first_hand, verification, moderation) == (False, "unverified", "pending")
            cur.execute("savepoint own_url")
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                cur.execute("select linkedin_url from reviews where id = %s", (share_id,))
            cur.execute("rollback to savepoint own_url")
            cur.execute("reset role")

            cur.execute(
                """
                update reviews
                set moderation_status = 'approved', first_hand = true, verification_status = 'verified'
                where id = %s
                """,
                (share_id,),
            )
            cur.execute("select first_hand, verification_status from reviews where id = %s", (share_id,))
            assert cur.fetchone() == (True, "verified")
            cur.execute("set role anon")
            cur.execute("savepoint hide_url")
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                cur.execute("select linkedin_url from reviews where id = %s", (share_id,))
            cur.execute("rollback to savepoint hide_url")
            cur.execute("select honesty, hard_times from reviews where id = %s", (share_id,))
            assert cur.fetchone() is None
            cur.execute("reset role")
            cur.execute("select published_site_bundle()::text")
            blob = cur.fetchone()[0]
            assert "ada-example" not in blob
            assert '"honesty": 4' in blob or '"honesty":4' in blob
        conn.rollback()


def test_settings_website_billing_and_delete():
    import psycopg

    from scripts.seed import main as seed_main

    seed_main()
    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            ada = _user(cur, "ada@example.com")
            bea = _user(cur, "bea@example.com")
            cur.execute("update profiles set website = 'example.com' where id = %s", (ada,))
            cur.execute("select website from profiles where id = %s", (ada,))
            assert cur.fetchone()[0] == "https://example.com"
            cur.execute("update profiles set website = 'http://fund.example/path' where id = %s", (ada,))
            cur.execute("select website from profiles where id = %s", (ada,))
            assert cur.fetchone()[0] == "http://fund.example/path"
            cur.execute("update profiles set website = '  ' where id = %s", (ada,))
            cur.execute("select website from profiles where id = %s", (ada,))
            assert cur.fetchone()[0] is None
            cur.execute("savepoint bad_site")
            with pytest.raises(psycopg.errors.CheckViolation):
                cur.execute("update profiles set website = 'javascript:alert(1)' where id = %s", (ada,))
            cur.execute("rollback to savepoint bad_site")

            cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (str(ada),))
            cur.execute("set role authenticated")
            cur.execute("select my_billing()")
            billing = cur.fetchone()[0]
            assert billing["plan"] == "Free" and billing["tier"] == "free"
            assert billing["card"] is None and billing["payments"] == []
            assert billing["payment_failed"] is False and billing["next_charge_label"] is None
            cur.execute("reset role")

            cur.execute(
                "select apply_subscription(%s, 'founder', 'active', now() + interval '1 month')",
                (ada,),
            )
            cur.execute("set role authenticated")
            cur.execute("select my_billing()")
            assert cur.fetchone()[0]["plan"] == "Paid"
            cur.execute("reset role")

            cur.execute("select id from firms where slug = 'a16z'")
            a16z = cur.fetchone()[0]
            cur.execute(
                """
                insert into reviews (firm_id, profile_id, body, moderation_status)
                values (%s, %s, 'mine', 'pending') returning id
                """,
                (a16z, ada),
            )
            review_id = cur.fetchone()[0]
            cur.execute(
                "insert into review_ratings (review_id, dimension, score) values (%s, 'honesty', 3)",
                (review_id,),
            )
            cur.execute("insert into watchlist (profile_id, firm_id) values (%s, %s)", (ada, a16z))
            cur.execute(
                "insert into report_views (profile_id, firm_id, counted) values (%s, %s, true)",
                (ada, a16z),
            )
            cur.execute(
                "insert into fund_alert_settings (profile_id, firm_id, enabled) values (%s, %s, true)",
                (ada, a16z),
            )

            cur.execute("set role anon")
            cur.execute("savepoint no_delete")
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                cur.execute("select delete_my_account()")
            cur.execute("rollback to savepoint no_delete")
            cur.execute("reset role")

            cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (str(ada),))
            cur.execute("set role authenticated")
            cur.execute("select delete_my_account()")
            cur.execute("reset role")

            cur.execute("select count(*) from auth.users where id = %s", (ada,))
            assert cur.fetchone()[0] == 0
            cur.execute("select count(*) from profiles where id = %s", (ada,))
            assert cur.fetchone()[0] == 0
            cur.execute("select count(*) from reviews where id = %s", (review_id,))
            assert cur.fetchone()[0] == 0
            cur.execute("select count(*) from watchlist where profile_id = %s", (ada,))
            assert cur.fetchone()[0] == 0
            cur.execute("select count(*) from report_views where profile_id = %s", (ada,))
            assert cur.fetchone()[0] == 0
            cur.execute("select count(*) from fund_alert_settings where profile_id = %s", (ada,))
            assert cur.fetchone()[0] == 0
            cur.execute("select count(*) from profiles where id = %s", (bea,))
            assert cur.fetchone()[0] == 1
        conn.rollback()
