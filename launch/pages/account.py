def render(c):
    A = c.A
    signed_out = c.signed_out
    why = c.why
    return f'''<main class="ac" id="account"><h1>{A["h1"]}</h1><p class="sub" id="aem"></p>{signed_out("account")}<div data-in hidden>
<div class="sum"><div><small>{A["plan"]}</small><b id="aplan"></b><span id="aplan2"></span></div><div><small>{A["checks_left"]}</small><b class="v" id="aleft"></b><span id="aleft2"></span></div><div><small id="arenl">{A["renews"]}</small><b id="aren"></b><span id="aren2"></span></div></div>
<div class="banner" id="cban" hidden></div><div class="acts"><button class="btn" id="resume" hidden>{A["resume"]}</button><button class="btn o" id="manage" hidden>{A["manage"]}</button><button class="btn o" data-open="cancelsub" id="cancel" hidden>{A["cancel"]}</button><button class="btn o" data-open="paywall" id="pick" hidden>{A["pick"]}</button><button class="btn" data-open="paywall" id="buymore">{A["buy_more"]}</button></div><p class="msg err" id="amsg"></p>
<section class="sec"><h2>{A["my_checks_h2"]}</h2><div class="card mck"><div><b id="mcn"></b><p id="mcl"></p></div><a class="btn o" href="firms/">{A["view_all"]}</a></div></section>
<section class="sec"><h2>{A["email_h2"]}</h2><p class="d">{A["email_d"]}</p><form class="card" id="emform"><label for="nem">{A["email_label"]}</label><div class="frm"><input class="in" id="nem" name="email" type="email" required placeholder="{A["email_placeholder"]}"><button class="btn o">{A["email_button"]}</button></div><p class="hint" id="emmsg">{A["email_hint"]}</p></form></section>
<section class="sec"><h2>{A["danger_h2"]}</h2><div class="dz"><div><b>{A["delete_b"]}</b><p id="dzp">{A["delete_p"]}</p></div><button class="btn dg" data-open="delacct">{A["delete_button"]}</button></div></section></div></main>
<div class="ov tall" id="delacct" hidden><div class="md" role="dialog" aria-modal="true" aria-labelledby="delh"><button class="x" data-close>×</button><h2 id="delh">{A["del_h2"]}</h2><p class="s">{A["del_s"]}</p><ul class="cons" id="cons"></ul>
{why('del', A['del_why'])}<div class="row2"><button class="btn o" data-close>{A["del_keep"]}</button><button class="btn dgs" id="delgo">{A["del_go"]}</button></div><p class="msg err" id="delmsg"></p></div></div>
<div class="ov tall" id="cancelsub" hidden><div class="md" role="dialog" aria-modal="true" aria-labelledby="canh"><button class="x" data-close>×</button><h2 id="canh"></h2><p class="s" id="cans"></p>
{why('can', A['can_why'])}<div class="row2"><button class="btn o" data-close>{A["can_keep"]}</button><button class="btn dgs" id="cango">{A["can_go"]}</button></div><p class="msg err" id="canmsg"></p></div></div>'''
