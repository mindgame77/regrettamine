def render(c):
    S = c.S
    P = S['pending']
    return f'''<main class="wrap"><div class="pend"><div class="sp"></div><h1>{P["h1"]}</h1><p style="color:var(--ink2);font-size:18px"><b id="pq"></b> {P["body"]}</p>
<form id="notify"><input class="in" type="email" name="email" required maxlength="200" placeholder="{P["email_placeholder"]}"><input class="in" type="text" name="website" maxlength="300" placeholder="{P["website_placeholder"]}"><button class="btn">{P["button"]}</button></form><p class="msg" id="pmsg"></p><p class="note">{P["note"]}</p></div></main>'''
