def press(c):
    S, E = c.S, c.E
    L = S['landing']
    wm = lambda o: f'<span class="wm{" s" if o in L["press_small_wordmarks"] else ""}">{E(o)}</span>'
    li = ''.join(f'<li><a href="{E(u)}" target="_blank" rel="noopener">{wm(o)}<span>{E(h)}</span><em>{d}</em></a></li>' for o, h, d, u in L['press'])
    return f'<section class="press"><h2>{L["press_h2"]}</h2><div class="logos">{"".join(wm(o) for o, *_ in L["press"])}</div><ul>{li}</ul></section>'

def render(c):
    S = c.S
    E = c.E
    SB = c.SB
    L, PILL = S['landing'], S['pills']
    cnt = lambda st, c: f"<span class='cnt {'ca' if st == 'review' else 'cg'}'>{E(c)}</span>" if c else ''
    demo = ''.join(f'<div class="dr"><span>{E(t)}</span><span class="pc"><span class="pill {PILL[st][0]}"><i></i>{PILL[st][1]}</span>{cnt(st, c)}</span></div>' for t, st, c in L['demo_rows'])
    return f'''<main class="wrap"><div class="hero"><h1>{L["h1"]}<br><span>{L["h1_accent"]}</span></h1>
{SB()}<div class="chips">{"".join(f"<span>{c}</span>" for c in L["chips"])}</div></div>
<div class="demo" aria-hidden="true"><div class="dh"><b>{L["demo_firm"]}</b><em>{L["demo_tag"]}</em></div>{demo}<div class="dr fade"><span>{L["demo_more"]}</span></div></div><div style="height:64px"></div></main>{press(c)}<div style="height:80px"></div>'''
