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
            assert "summary" not in third
            assert "score" not in third
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
            assert "summary" not in blocked
            assert "score" not in blocked
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
            cur.execute(
                "select new_legal_matter, score_change from fund_alert_settings where profile_id = %s and firm_id = %s",
                (ada, a16z),
            )
            assert cur.fetchone() == (True, True)
            cur.execute("select set_fund_alert_kind('a16z', 'score_change', false)")
            kind = cur.fetchone()[0]
            assert kind["ok"] is True and kind["score_change"] is False and kind["new_legal_matter"] is True
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
            cur.execute(
                "select new_legal_matter, score_change from fund_alert_settings where profile_id = %s and firm_id = %s",
                (ada, a16z),
            )
            assert cur.fetchone() == (True, True)
            cur.execute(
                "select new_legal_matter, score_change from fund_alert_settings where profile_id = %s and firm_id = %s",
                (ada, battery),
            )
            assert cur.fetchone() == (True, True)
            cur.execute("select set_watch_alert_kind('score_change', false)")
            shared = cur.fetchone()[0]
            assert shared["ok"] is True and shared["score_change"] is False and shared["new_legal_matter"] is True
            cur.execute(
                "select new_legal_matter, score_change from alert_preferences where profile_id = %s",
                (ada,),
            )
            assert cur.fetchone() == (True, False)
            cur.execute(
                """
                select bool_and(new_legal_matter), bool_and(score_change) = false
                from fund_alert_settings where profile_id = %s
                """,
                (ada,),
            )
            assert cur.fetchone() == (True, True)
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

            bob = _user(cur, "alert-bob@example.com")
            cur.execute("alter table public.fund_alert_settings disable trigger user")
            cur.execute(
                """
                insert into fund_alert_settings (profile_id, firm_id, enabled, new_legal_matter, score_change)
                values (%s, %s, true, true, false), (%s, %s, true, false, false)
                """,
                (bob, a16z, bob, battery),
            )
            cur.execute("alter table public.fund_alert_settings enable trigger user")
            cur.execute(
                """
                update public.alert_preferences p
                set new_legal_matter = exists (
                      select 1 from public.fund_alert_settings s
                      where s.profile_id = p.profile_id and s.new_legal_matter
                    ),
                    score_change = exists (
                      select 1 from public.fund_alert_settings s
                      where s.profile_id = p.profile_id and s.score_change
                    )
                where p.profile_id = %s
                  and exists (
                    select 1 from public.fund_alert_settings s
                    where s.profile_id = p.profile_id
                  )
                """,
                (bob,),
            )
            cur.execute(
                "select new_legal_matter, score_change from alert_preferences where profile_id = %s",
                (bob,),
            )
            assert cur.fetchone() == (True, False)
            cara = _user(cur, "alert-cara@example.com")
            cur.execute(
                """
                update public.alert_preferences p
                set new_legal_matter = false, score_change = false
                where p.profile_id = %s
                  and exists (
                    select 1 from public.fund_alert_settings s where s.profile_id = p.profile_id
                  )
                """,
                (cara,),
            )
            cur.execute(
                "select new_legal_matter, score_change from alert_preferences where profile_id = %s",
                (cara,),
            )
            assert cur.fetchone() == (True, True)
        conn.rollback()


def test_open_report_reads_bundle_and_hides_it():
    import psycopg

    from scripts.seed import main as seed_main

    seed_main()
    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            cur.execute("select id from firms where slug = 'a16z'")
            a16z = cur.fetchone()[0]
            cur.execute("delete from report_pages where slug = 'a16z'")
            cur.execute("delete from report_bundles where firm_id = %s", (a16z,))
            cur.execute(
                """
                insert into report_bundles (firm_id, payload)
                values (%s, jsonb_build_object('html', '<article id="evidence">bundle-a16z</article>'))
                """,
                (a16z,),
            )
            cur.execute("select set_config('request.jwt.claim.sub', '', true)")
            cur.execute("set role anon")
            cur.execute("savepoint no_read")
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                cur.execute("select payload from report_bundles")
            cur.execute("rollback to savepoint no_read")
            opened = _open(cur, "a16z", ANON)
            assert opened["ok"] is True
            assert opened["tier"] == "visitor"
            assert "bundle-a16z" in opened["html"]
            assert "id=\"evidence\"" in opened["html"]
            again = _open(cur, "a16z", ANON)
            assert again["repeat"] is True
            cur.execute("reset role")
        conn.rollback()


def _correction(cur, uid, firm):
    cur.execute(
        """
        insert into corrections (user_id, fund_id, page_url, message, source_url)
        values (%s, %s, 'https://example.com/vc/a16z/', 'The date is wrong', 'https://example.com/source')
        returning id
        """,
        (uid, firm),
    )
    return cur.fetchone()[0]


def test_corrections_are_paid_only():
    import psycopg

    from scripts.seed import main as seed_main

    seed_main()
    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            ada = _user(cur, "correct-ada@example.com")
            bea = _user(cur, "correct-bea@example.com")
            mod = _user(cur, "correct-mod@example.com")
            cur.execute("select id from firms where slug = 'a16z'")
            a16z = cur.fetchone()[0]
            cur.execute("update profiles set is_admin = true where id = %s", (mod,))
            cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (str(ada),))
            cur.execute("set role authenticated")
            cur.execute("savepoint free_insert")
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                _correction(cur, ada, a16z)
            cur.execute("rollback to savepoint free_insert")
            cur.execute("reset role")

            cur.execute(
                "select apply_subscription(%s, 'monthly', 'active', now() + interval '1 month')",
                (ada,),
            )
            cur.execute("set role authenticated")
            saved = _correction(cur, ada, a16z)
            cur.execute("select status from corrections where id = %s", (saved,))
            assert cur.fetchone()[0] == "pending"
            cur.execute("savepoint bad_source")
            with pytest.raises(psycopg.errors.CheckViolation):
                cur.execute(
                    """
                    insert into corrections (user_id, fund_id, page_url, message, source_url)
                    values (%s, %s, 'https://example.com/vc/a16z/', 'Wrong', 'javascript:alert(1)')
                    """,
                    (ada, a16z),
                )
            cur.execute("rollback to savepoint bad_source")
            cur.execute("reset role")

            cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (str(bea),))
            cur.execute("set role authenticated")
            cur.execute("select count(*) from corrections where id = %s", (saved,))
            assert cur.fetchone()[0] == 0
            cur.execute("reset role")

            cur.execute(
                "update subscriptions set payment_failed_at = now() - interval '25 hours' where profile_id = %s",
                (ada,),
            )
            cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (str(ada),))
            cur.execute("set role authenticated")
            cur.execute("savepoint lapsed_insert")
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                _correction(cur, ada, a16z)
            cur.execute("rollback to savepoint lapsed_insert")
            cur.execute("reset role")

            cur.execute(
                "update subscriptions set payment_failed_at = now() - interval '1 hour' where profile_id = %s",
                (ada,),
            )
            cur.execute("set role authenticated")
            grace = _correction(cur, ada, a16z)
            assert grace is not None
            cur.execute("reset role")

            cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (str(mod),))
            cur.execute("set role authenticated")
            cur.execute("update corrections set status = 'approved' where id = %s", (saved,))
            cur.execute("select status from corrections where id = %s", (saved,))
            assert cur.fetchone()[0] == "approved"
            cur.execute("reset role")
        conn.rollback()
