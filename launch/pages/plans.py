def render(c):
    pricing_inner = c.pricing_inner
    return f'<main class="wrap" style="display:flex;justify-content:center;padding:48px 16px 80px"><div class="md w">{pricing_inner(False)}</div></main>'
