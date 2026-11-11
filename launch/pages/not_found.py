def render(c):
    p = c.S["pages"]["404"]
    return f'<main class="wrap"><div class="hero"><h1>{c.E(p["h1"])}</h1><p>{c.E(p["body"])}</p>{c.SB()}</div></main>'
