"""The SEC assets figure uses one label. Stored facts and My firms stay as they are."""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
COPY = json.loads((ROOT / "launch" / "copy.json").read_text())
JS = (ROOT / "launch" / "js" / "company.js").read_text()


def test_assets_label_is_set_once():
    assert COPY["company"]["header"]["assets"] == "Assets (SEC)"
    assert "Assets (SEC)" not in JS
    assert "label === 'Assets'" in JS and "Regulatory AUM" in JS and "label === 'AUM'" in JS
    assert COPY["site"]["my_firms"]["h1"] == "My firms"
    assert COPY["site"]["my_firms"]["title"] == "My firms"
    assert COPY["site"]["nav"]["my_checks"] == "My firms"
    assert COPY["site"]["account"]["my_checks_h2"] == "My firms"
