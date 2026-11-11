def render(c):
    t = c.S["pages"]["my-checks"]["redirect_label"]
    return f'<main class="wrap"><div class="hero"><h1>{c.E(t)}</h1><a href="../account/firms/">{c.E(t)}</a></div></main>'
