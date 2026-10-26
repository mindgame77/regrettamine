"""Leads stay visible and read one way: 'Not confirmed' (display only; stored lead wording is unchanged)."""
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
COPY = json.loads((ROOT / "launch" / "copy.json").read_text())
JS = (ROOT / "launch" / "js" / "company.js").read_text()


def test_label_set_once():
    assert COPY["company"]["not_confirmed"] == "Not confirmed"
    assert "ncValue(x.value)" in JS and "ncPill" in JS and "isLeadTag(x.badge)" in JS and "isLeadTag(x.kind)" in JS


def test_rewrites():
    start = JS.index("const NC = ")
    end = JS.index("const ncPill")
    src = "const COPY={not_confirmed:'Not confirmed'};" + JS[start:end] + """
const out = [ncValue('Pension · Y Combinator (2026 vehicle) · $370M · 2026 · Lead (not confirmed)'),
  ncValue('LEAD: GSK and J&J as LPs'), ncStrip('Lead (allegation, not verified): DOJ probe'), ncValue('Endowment · Confirmed'),
  isLeadTag('Lead · allegation'), isLeadTag('Lead (unverified)'), isLeadTag('Open DOJ probe')];
console.log(JSON.stringify(out));"""
    out = json.loads(subprocess.run(["node", "-e", src], capture_output=True, text=True, check=True).stdout)
    assert out == ["Pension · Y Combinator (2026 vehicle) · $370M · 2026 · Not confirmed", "GSK and J&J as LPs · Not confirmed",
                   "DOJ probe", "Endowment · Confirmed", True, True, False]
