def render(c):
    signup_inner = c.signup_inner
    return f'<main class="wrap" style="display:flex;justify-content:center;padding:48px 16px 80px"><div class="md sgm">{signup_inner(False)}</div></main>'
