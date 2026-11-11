from legal import _render

def render(c):
    return _render("privacy.md", raw=c.S["legal"]["privacy"])
