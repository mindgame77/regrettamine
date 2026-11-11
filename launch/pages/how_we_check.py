import re
from .video import render_video

SOURCE_PILL_JS = """
<script>
(function(){
  document.querySelectorAll(".checks10").forEach(function(grid){
    grid.addEventListener("click", function(e){
      var p = e.target.closest(".srcpill");
      if(!p || !grid.contains(p)) return;
      var card = p.closest(".c10");
      var on = p.classList.contains("is-on");
      grid.querySelectorAll(".srcpill.is-on").forEach(function(x){ x.classList.remove("is-on"); });
      grid.querySelectorAll(".srcpill-why").forEach(function(w){ w.hidden = true; w.textContent = ""; });
      if(on) return;
      p.classList.add("is-on");
      var why = card && card.querySelector(".srcpill-why");
      if(why && p.getAttribute("data-why")){ why.hidden = false; why.textContent = p.getAttribute("data-why"); }
    });
  });
})();
</script>
"""

def render(c):
    S = c.S
    COPY = c.COPY
    E = c.E
    H, SM = S['how_we_check'], S['how_we_check']['sample']
    li = lambda xs: '<ul>' + ''.join(f'<li><span>{x}</span></li>' for x in xs) + '</ul>'
    areas = ''.join(
        f'<div class="card area"><h3>{t}</h3><p>{p}</p><span class="tag">{g}</span></div>'
        for t, p, g in H['areas']
    )
    team = ''.join(f'<div class="who"><b>{n}</b><span>{r}</span></div>' for n, r in SM['team'])
    checks = ''.join(
        f'<div class="ck"><span>{n}</span><span class="pl {c}">{l}</span></div>'
        for n, c, l in SM['checks']
    )
    pills = ''.join(f'<span class="pl {c}">{t}</span>' for c, t in H['read_pills'])
    media = render_video(H.get('video'), H.get('video_caption') or 'Startup team at work')
    video = f'<figure class="vspot"><div class="vspot-frame">{media}</div></figure>'
    stat_url = (H.get('stat_url') or '').strip()
    stat_src = H.get('stat_source') or ''
    if stat_url and re.match(r'https://', stat_url, re.I):
        stat_cite = (
            f'<cite><a href="{E(stat_url, True)}" target="_blank" rel="noopener">{E(stat_src)}</a></cite>'
            if stat_src else ''
        )
    else:
        stat_cite = f'<cite>{E(stat_src)}</cite>' if stat_src else ''
    stat = ''
    if H.get('stat_figure') or H.get('stat_text'):
        stat = (
            '<div class="stat">'
            f'<b class="stat-n">{E(H.get("stat_figure") or "")}</b>'
            f'<p class="stat-t">{E(H.get("stat_text") or "")}</p>'
            f'{stat_cite}'
            '</div>'
        )
    def source_pills(item):
        srcs = item.get("sources") or []
        if isinstance(srcs, str):
            names = [s.strip() for s in re.sub(r"\s+and\s+", ", ", srcs).split(",") if s.strip()]
            srcs = [{"name": n, "why": ""} for n in names]
        pills = []
        for s in srcs:
            name = s["name"] if isinstance(s, dict) else str(s)
            why = (s.get("why") if isinstance(s, dict) else "") or ""
            pills.append(
                f'<button type="button" class="srcpill" data-why="{E(why)}">'
                f'{E(name)}<span class="srcpill-tip" role="tooltip">{E(why)}</span></button>'
            )
        return '<div class="c10-pills">' + "".join(pills) + '</div><p class="srcpill-why" hidden></p>'

    checks10 = "".join(
        f'<article class="c10"><b class="c10-n">{i:02d}</b><div><h3>{E(item["name"])}</h3>'
        f"{source_pills(item)}</div></article>"
        for i, item in enumerate(H.get("checks10") or [], 1)
    )
    checks10_p = H.get('checks10_p') or ''
    checks10_intro = f'<p class="checks10-p">{E(checks10_p)}</p>' if checks10_p else ''
    checks10_block = ''
    if checks10:
        checks10_block = (
            f'<h2>{E(H.get("checks10_h2") or "10 background checks")}</h2>'
            f'{checks10_intro}'
            f'<div class="checks10">{checks10}</div>'
        )

    ICONS = {
        'records': (
            '<svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true" fill="none" '
            'stroke="#6C3BFF" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">'
            '<path d="M7 7V5.8A1.8 1.8 0 0 1 8.8 4h8.4A1.8 1.8 0 0 1 19 5.8v10.4a1.8 1.8 0 0 1-1.8 1.8H16"/>'
            '<rect x="5" y="7" width="11" height="13" rx="1.8"/>'
            '<path d="M8 11h5M8 14h5M8 17h3"/></svg>'
        ),
        'match': (
            '<svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true" fill="none" '
            'stroke="#6C3BFF" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">'
            '<circle cx="10" cy="8" r="3.2"/>'
            '<path d="M4.8 19c.6-3.1 2.7-4.7 5.2-4.7 1 0 1.9.3 2.7.8"/>'
            '<circle cx="17" cy="16.2" r="3.3"/>'
            '<path d="M15.6 16.2l1 1.1 1.8-2"/></svg>'
        ),
        'link': (
            '<svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true" fill="none" '
            'stroke="#6C3BFF" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">'
            '<path d="M10 13.5 8.6 14.9a3 3 0 0 1-4.2-4.2l2.5-2.5a3 3 0 0 1 4.2 0L12 9"/>'
            '<path d="M14 10.5l1.4-1.4a3 3 0 0 1 4.2 4.2l-2.5 2.5a3 3 0 0 1-4.2 0L12 15"/>'
            '<path d="M9.8 14.2l4.4-4.4"/></svg>'
        ),
        'decide': (
            '<svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true" fill="none" '
            'stroke="#6C3BFF" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">'
            '<rect x="3.5" y="6.5" width="7.5" height="5" rx="2.5"/>'
            '<rect x="13" y="12.5" width="7.5" height="5" rx="2.5"/>'
            '<path d="M8 14.5c0 2.2 1.8 3.5 4 3.5h1M16 9.5c0-2.2-1.8-3.5-4-3.5h-1"/></svg>'
        ),
    }
    step_titles = [(s[0] if isinstance(s, (list, tuple)) else s) for s in H['steps']]
    chips = H.get('step_chips') or []
    icons = H.get('step_icons') or []
    badges = H.get('step_badges') or []
    heading = H.get('steps_h2') or ''
    heading_html = f'<h2>{E(heading)}</h2>' if heading else ''

    sample = (
        "<aside class=\"sample\">"
        f"<div class=\"sample-head\"><span class=\"badge\">{H['sample_label']}</span><p class=\"cap\">{H['sample_caption']}</p></div>"
        f"<b class=\"fname\">{SM['name']}</b>"
        f"<p class=\"meta\">{SM['meta']}</p>"
        "<div class=\"tiles\" data-part=\"tiles\">"
        f"<div class=\"tile mint\"><small>{SM['deals_label']}</small><b>{SM['deals_n']}</b><span>{SM['deals_last']}</span></div>"
        f"<div class=\"tile mint\"><small>{SM['fund_label']}</small><b>{SM['fund_n']}</b><span>{SM['fund_sub']}</span></div>"
        "</div>"
        f"<p class=\"sl\" data-part=\"team\">{SM['team_label']}</p>"
        f"<div class=\"team\" data-part=\"team\">{team}</div>"
        f"<p class=\"sl\" data-part=\"quote\">{SM['quote_label']}</p>"
        f"<blockquote data-part=\"quote\"><p>\u201c{SM['quote']}\u201d</p><cite>\u2014 {SM['quote_by']}</cite></blockquote>"
        f"<p class=\"sl\" data-part=\"look\">{SM['look_label']}</p>"
        f"<p class=\"look\" data-part=\"look\">{SM['look']}</p>"
        f"<p class=\"sl\" data-part=\"checks\">{SM['checks_label']}</p>"
        f"<div class=\"cks\" data-part=\"checks\">{checks}</div>"
        "</aside>"
    )

    step_items = []
    for i, title in enumerate(step_titles):
        icon = ICONS.get(icons[i] if i < len(icons) else "", ICONS["records"])
        step_items.append(
            '<li class="tl-step">'
            f'<b class="n">{i + 1}</b>'
            f'<h3>{E(title)}</h3>'
            "</li>"
        )
    steps = "".join(step_items)
    left, right = [], []
    for c in (H.get("callouts") or []):
        item = (
            f'<p class="callout {E(c.get("side") or "left")}" data-target="{E(c.get("target") or "")}">'
            f'<span>{E(c.get("label") or "")}</span></p>'
        )
        (left if c.get("side") == "left" else right).append(item)
    stage = (
        "<div class=\"stage\">" + heading_html + "<ol class=\"tl\">" + steps + "</ol>"
        + "<div class=\"anatomy\"><div class=\"callouts callouts-l\">" + "".join(left) + "</div>"
        + sample + "<div class=\"callouts callouts-r\">" + "".join(right) + "</div></div></div>"
    )

    pill_map = S.get("pills") or {}
    legend_items = []
    for key, text in (COPY.get("company") or {}).get("table", {}).get("legend") or []:
        meta = pill_map.get(key)
        if not meta:
            continue
        cls, label = meta[0], meta[1]
        legend_items.append(
            f'<li><span class="pill {E(cls)}"><i></i>{E(label)}</span><span>{E(text)}</span></li>'
        )
    read_block = ""
    if legend_items:
        read_block = (
            f'<h2>{H["read_h2"]}</h2>'
            f'<p class="read-p">{H["read_p"]}</p>'
            f'<ul class="pill-legend">{"".join(legend_items)}</ul>'
        )

    return f'''<main class="hwc hwc-a hwc-a1 hwc-a1b">
<div class="wash"><div class="inner">
<div class="hero">
{video}
<div class="hero-copy">
<h1>{H["h1"]}<br><span>{H["h1_accent"]}</span></h1>
</div>
</div>

{stage}

</div></div>
<div class="inner rest">
{checks10_block}
{read_block}
</div>
</main>''' + SOURCE_PILL_JS
