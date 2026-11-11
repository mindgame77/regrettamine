def render(c):
    t = c.S["pages"]["pricing"]["redirect_label"]
    return f'<main class="wrap"><div class="hero"><h1>{c.E(t)}</h1><a href="../?pricing=1">{c.E(t)}</a></div></main>'
