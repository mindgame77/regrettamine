"""Database-enforced visitor, free, and paid access."""
import os

import pytest

pytest.importorskip("psycopg")

DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")

ANON = "anon-tier-key-12345678"


def _user(cur, email):
    cur.execute(
        "insert into auth.users (id, email) values (gen_random_uuid(), %s) returning id",
        (email,),
    )
    return cur.fetchone()[0]


def _open(cur, slug, anon_key=None):
    cur.execute("select open_report(%s, %s)", (slug, anon_key))
    return cur.fetchone()[0]


def test_visitor_free_and_paid_tiers():
    import psycopg

    from scripts.seed import main as seed_main

    seed_main()
    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                insert into firms (slug, name, list_score, published, is_test)
                values ('zz-extra', 'Zz Extra Fund', 1, true, false)
                """
            )
            cur.execute(
                """
                insert into report_pages (slug, html)
                select slug, '<article data-report-body="' || slug || '">secret</article>'
                from firms
                where published and not is_test
                """
            )
            cur.execute(
                """
                select slug from firms
                where published and not is_test
                order by list_score desc nulls last, name
                """
            )
            ranked = [row[0] for row in cur.fetchall()]
            assert ranked[0] == "a16z"
            assert "zz-extra" in ranked
            assert len(ranked) == 12

            cur.execute("select set_config('request.jwt.claim.sub', '', true)")
            cur.execute("set role anon")
            cur.execute("select landing_funds()")
            visitor = cur.fetchone()[0]
            assert visitor["tier"] == "visitor"
            assert visitor["limit"] == 3
            assert visitor["total"] == 12
            assert [row["id"] for row in visitor["funds"]] == ["a16z", "battery", "bessemer"]
            cur.execute("select search_funds('sequoia')")
            sequoia = cur.fetchone()[0]
            assert len(sequoia) == 1
            assert sequoia[0]["slug"] == "sequoia"
            assert sequoia[0]["name"]
            assert sequoia[0]["inTier"] is False
            assert "score" not in sequoia[0]
            cur.execute("select search_funds('Andreessen')")
            andreessen = cur.fetchone()[0][0]
            assert andreessen["inTier"] is True
            assert andreessen["score"] == 95
            cur.execute("select search_funds('')")
            assert cur.fetchone()[0] == []
            first = _open(cur, ranked[0], ANON)
            second = _open(cur, ranked[1], ANON)
            assert first["ok"] is True and ranked[0] in first["html"]
            assert second["ok"] is True and second["repeat"] is False
            third = _open(cur, ranked[2], ANON)
            assert third["ok"] is False
            assert third["reason"] == "limit"
            assert third["plans"] is False
            assert "html" not in third
            again = _open(cur, ranked[0], ANON)
            assert again["ok"] is True and again["repeat"] is True
            cur.execute("select count(*) from firms")
            assert cur.fetchone()[0] == 0
            cur.execute("select count(*) from report_pages")
            assert cur.fetchone()[0] == 0
            cur.execute("select count(*) from legal_matters")
            assert cur.fetchone()[0] == 0
            cur.execute("select count(*) from evidence_cards")
            assert cur.fetchone()[0] == 0
            cur.execute("savepoint no_bundle")
            with pytest.raises(psycopg.Error):
                cur.execute("select published_site_bundle()")
            cur.execute("rollback to savepoint no_bundle")
            cur.execute("savepoint no_store")
            with pytest.raises(psycopg.Error):
                cur.execute("select store_report_page('a16z', '<p>nope</p>')")
            cur.execute("rollback to savepoint no_store")
            cur.execute("reset role")

            ada = _user(cur, "tier-ada@example.com")
            cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (str(ada),))
            cur.execute("set role authenticated")
            cur.execute("select access_tier()")
            assert cur.fetchone()[0] == "free"
            cur.execute("select landing_funds()")
            free = cur.fetchone()[0]
            assert free["tier"] == "free"
            assert free["limit"] == 11
            assert free["total"] == 12
            assert len(free["funds"]) == 11
            assert "zz-extra" not in [row["id"] for row in free["funds"]]
            opened = []
            for slug in ranked[:7]:
                row = _open(cur, slug)
                assert row["ok"] is True, slug
                assert row["tier"] == "free"
                opened.append(slug)
            repeat = _open(cur, opened[0])
            assert repeat["ok"] is True and repeat["repeat"] is True
            blocked = _open(cur, ranked[7])
            assert blocked["ok"] is False
            assert blocked["reason"] == "limit"
            assert blocked["plans"] is True
            assert "html" not in blocked
            cur.execute("savepoint no_apply")
            with pytest.raises(psycopg.Error):
                cur.execute(
                    "select apply_subscription(%s, 'founder', 'active', now() + interval '1 month')",
                    (ada,),
                )
            cur.execute("rollback to savepoint no_apply")
            cur.execute("reset role")

            cur.execute(
                "select apply_subscription(%s, 'founder', 'active', now() + interval '1 month')",
                (ada,),
            )
            cur.execute("set role authenticated")
            cur.execute("select access_tier()")
            assert cur.fetchone()[0] == "paid"
            cur.execute("select landing_funds()")
            paid = cur.fetchone()[0]
            assert paid["tier"] == "paid"
            assert paid["limit"] is None
            assert len(paid["funds"]) == paid["total"] == 12
            assert "zz-extra" in [row["id"] for row in paid["funds"]]
            eighth = _open(cur, ranked[7])
            assert eighth["ok"] is True and eighth["tier"] == "paid"
            extra = _open(cur, "zz-extra")
            assert extra["ok"] is True and "zz-extra" in extra["html"]
            cur.execute("select search_funds('sequoia')")
            assert cur.fetchone()[0][0]["inTier"] is True
            cur.execute("reset role")

            cur.execute(
                "update subscriptions set current_period_end = now() - interval '1 day' where profile_id = %s",
                (ada,),
            )
            cur.execute("set role authenticated")
            cur.execute("select access_tier()")
            assert cur.fetchone()[0] == "free"
            cur.execute("select landing_funds()")
            expired = cur.fetchone()[0]
            assert expired["limit"] == 11
            assert len(expired["funds"]) == 11
            still = _open(cur, opened[0])
            assert still["ok"] is True and still["repeat"] is True
            cur.execute("reset role")

            cur.execute(
                """
                update subscriptions
                set status = 'canceled', current_period_end = now() + interval '1 month'
                where profile_id = %s
                """,
                (ada,),
            )
            cur.execute("set role authenticated")
            cur.execute("select access_tier()")
            assert cur.fetchone()[0] == "free"
            cur.execute("select is_paid(%s)", (ada,))
            assert cur.fetchone()[0] is False
            cur.execute("reset role")

            bea = _user(cur, "tier-bea@example.com")
            cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (str(bea),))
            cur.execute("set role authenticated")
            cur.execute("select carry_anon_views(%s)", (ANON,))
            carried = cur.fetchone()[0]
            assert carried["ok"] is True
            cur.execute("select count(*) from report_views where profile_id = %s", (bea,))
            assert cur.fetchone()[0] == 2
            for slug in ranked[2:7]:
                assert _open(cur, slug)["ok"] is True
            assert _open(cur, ranked[7])["plans"] is True
            cur.execute("reset role")

            cur.execute("set role service_role")
            cur.execute("select published_site_bundle()")
            bundle = cur.fetchone()[0]
            slugs = [firm["slug"] for firm in bundle["firms"]]
            assert "a16z" in slugs
            assert "zz-extra" in slugs
            cur.execute("reset role")
        conn.rollback()


def test_alerts_require_an_opened_report_or_paid():
    import psycopg

    from scripts.seed import main as seed_main

    seed_main()
    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                insert into report_pages (slug, html)
                select slug, '<article>' || slug || '</article>'
                from firms
                where published and not is_test
                """
            )
            ada = _user(cur, "alert-ada@example.com")
            cur.execute("select count(*) from alert_preferences where profile_id = %s", (ada,))
            assert cur.fetchone()[0] == 1
            cur.execute("select id from firms where slug = 'a16z'")
            a16z = cur.fetchone()[0]
            cur.execute("select id from firms where slug = 'battery'")
            battery = cur.fetchone()[0]
            cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (str(ada),))
            cur.execute("set role authenticated")
            cur.execute(
                "update alert_preferences set partner_exit = true where profile_id = %s",
                (ada,),
            )
            cur.execute(
                "insert into watchlist (profile_id, firm_id) values (%s, %s)",
                (ada, a16z),
            )
            cur.execute("savepoint alerts_on")
            with pytest.raises(psycopg.errors.CheckViolation):
                cur.execute(
                    "update watchlist set alerts = true where profile_id = %s and firm_id = %s",
                    (ada, a16z),
                )
            cur.execute("rollback to savepoint alerts_on")
            cur.execute("savepoint settings_on")
            with pytest.raises(psycopg.errors.CheckViolation):
                cur.execute(
                    "insert into fund_alert_settings (profile_id, firm_id, enabled) values (%s, %s, true)",
                    (ada, a16z),
                )
            cur.execute("rollback to savepoint settings_on")
            cur.execute("select set_fund_alert('a16z', true)")
            denied = cur.fetchone()[0]
            assert denied["ok"] is False and denied["reason"] == "unopened"
            cur.execute("select alerts from watchlist where profile_id = %s and firm_id = %s", (ada, a16z))
            assert cur.fetchone()[0] is False
            cur.execute("reset role")

            cur.execute("set role anon")
            cur.execute("savepoint anon_alert")
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                cur.execute(
                    "insert into fund_alert_settings (profile_id, firm_id, enabled) values (%s, %s, true)",
                    (ada, a16z),
                )
            cur.execute("rollback to savepoint anon_alert")
            cur.execute("savepoint anon_rpc")
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                cur.execute("select set_fund_alert('a16z', true)")
            cur.execute("rollback to savepoint anon_rpc")
            cur.execute("reset role")

            cur.execute("alter table public.fund_alert_settings disable trigger user")
            cur.execute("alter table public.watchlist disable trigger user")
            cur.execute("set role authenticated")
            cur.execute("savepoint rls_settings")
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                cur.execute(
                    "insert into fund_alert_settings (profile_id, firm_id, enabled) values (%s, %s, true)",
                    (ada, a16z),
                )
            cur.execute("rollback to savepoint rls_settings")
            cur.execute("savepoint rls_watch")
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                cur.execute(
                    "update watchlist set alerts = true where profile_id = %s and firm_id = %s",
                    (ada, a16z),
                )
            cur.execute("rollback to savepoint rls_watch")
            cur.execute("reset role")
            cur.execute("alter table public.fund_alert_settings enable trigger user")
            cur.execute("alter table public.watchlist enable trigger user")

            cur.execute("set role authenticated")
            opened = _open(cur, "a16z")
            assert opened["ok"] is True
            cur.execute("select set_fund_alert('a16z', true)")
            allowed = cur.fetchone()[0]
            assert allowed["ok"] is True and allowed["on"] is True
            cur.execute("select alerts from watchlist where profile_id = %s and firm_id = %s", (ada, a16z))
            assert cur.fetchone()[0] is True
            cur.execute(
                "select enabled from fund_alert_settings where profile_id = %s and firm_id = %s",
                (ada, a16z),
            )
            assert cur.fetchone()[0] is True
            cur.execute("select set_fund_alert('battery', true)")
            still = cur.fetchone()[0]
            assert still["ok"] is False and still["reason"] == "unopened"
            cur.execute("select my_alert_funds()")
            mine = cur.fetchone()[0]
            a16z_row = next(row for row in mine if row["slug"] == "a16z")
            assert a16z_row["alerts"] is True and a16z_row["opened"] is True
            cur.execute("reset role")

            cur.execute(
                "select apply_subscription(%s, 'founder', 'active', now() + interval '1 month')",
                (ada,),
            )
            cur.execute("set role authenticated")
            cur.execute("select set_fund_alert('battery', true)")
            paid = cur.fetchone()[0]
            assert paid["ok"] is True and paid["on"] is True
            cur.execute("select count(*) from report_views where profile_id = %s and firm_id = %s", (ada, battery))
            assert cur.fetchone()[0] == 0
            cur.execute("reset role")

            cur.execute(
                "update subscriptions set current_period_end = now() - interval '1 day' where profile_id = %s",
                (ada,),
            )
            cur.execute("set role authenticated")
            cur.execute("select set_fund_alert('sequoia', true)")
            expired = cur.fetchone()[0]
            assert expired["ok"] is False and expired["reason"] == "unopened"
            cur.execute("select set_fund_alert('battery', false)")
            off = cur.fetchone()[0]
            assert off["ok"] is True and off["on"] is False
            cur.execute("select count(*) from fund_alert_settings where profile_id = %s and firm_id = %s", (ada, battery))
            assert cur.fetchone()[0] == 0
            cur.execute("reset role")
        conn.rollback()
