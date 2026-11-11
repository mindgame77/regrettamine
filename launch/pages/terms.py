from legal import _render

def render(c):
    return _render("terms.md", raw=c.S["legal"]["terms"])
