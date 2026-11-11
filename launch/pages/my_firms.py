def render(c):
    F_ = c.F_
    SO = c.SO
    SB = c.SB
    return f'''<main class="ac mf" id="myfirms"><h1>{F_["h1"]}</h1><p class="sub">{F_["sub"]}</p><div class="emp" data-out hidden><h2>{F_["signed_out_h2"]}</h2><p>{F_["signed_out_p"]}</p><button class="btn" data-open="signup" style="margin-top:20px">{SO["button"]}</button></div><div data-in hidden>
    <div id="flist" hidden><div class="tabs"><div class="tg" role="tablist" aria-label="{F_["tabs_aria"]}">{"".join(f'<button type="button" role="tab" data-tab="{k}"{' class="on" aria-selected="true"' if k == 'all' else ' aria-selected="false"'}>{t} <em id="fn-{k}"></em></button>' for k, t in F_["tabs"])}</div>
    <label class="srch">⌕<input id="fq" type="search" placeholder="{F_["search"]}" aria-label="{F_["search"]}"></label></div>
    <div class="ftab"><div class="mfr h">{"".join(f"<span>{c}</span>" for c in F_["cols"])}</div><div id="frows"></div></div><p class="hint" id="fnone" hidden></p></div>
    <div class="emp" id="fempty" hidden><h2>{F_["empty_h2"]}</h2><p>{F_["empty_p"]}</p>{SB()}</div></div></main>'''
