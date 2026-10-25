"""Terms and Privacy are rendered from launch/legal/*.md into the existing page shell."""
import importlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "launch"))
legal = importlib.import_module("legal")


def test_terms_and_privacy_render_the_approved_pages():
    terms, privacy = legal.terms(), legal.privacy()
    for page in (terms, privacy):
        assert page.startswith('<main class="hp lg"><span class="ey">Legal</span><h1>')
        assert '<p class="lead">' in page and '<p class="eff">' in page and '<div class="toc">' in page
        assert "October 25, 2026" in page
        assert "[DATE]" not in page and "{{" not in page
        assert "Know Your Group INC." in page
        assert 'href="mailto:malytskyyo@gmail.com"' in page
        assert page.count("<h2>") >= 10
        assert page.count('<a href="#') == page.count("<h2>")
    assert "Terms of Service" in terms and 'href="../privacy/"' in terms
    assert "Privacy Policy" in privacy and 'href="../terms/"' in privacy
    assert "not a consumer reporting agency" in terms
    assert "<code>regretamin.anon</code>" in privacy
    assert "Starter" in terms and "$19" in terms and "$190" in terms
    assert "Pro" in terms and "$49" in terms and "$490" in terms and "$10" in terms
    assert 'id="8-credits"' in terms and 'id="10-subscriptions-and-promo-codes"' in terms
    # A heading in the table of contents points at the section it names.
    assert '<a href="#1-agreement">1. Agreement</a>' in terms
    assert '<section id="1-agreement"><h2>1. Agreement</h2>' in terms


def test_unknown_plan_placeholder_fails_the_build():
    try:
        legal._fill("Costs {{plan.nope.price}}.")
    except ValueError as err:
        assert "plan.nope.price" in str(err)
    else:
        raise AssertionError("missing plan placeholder was filled")
