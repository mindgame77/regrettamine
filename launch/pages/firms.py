def render(c):
    E, F = c.E, c.S['pages']['investors']
    return f"""<main class="wrap firms-pg">
<div class="firms-search-hero">
<label class="srch firms-qbox" for="firms-q"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="10" cy="10" r="7"></circle><path d="m15 15 6 6"></path></svg><span class="firms-qfield"><span id="firms-chips" class="firms-chips"></span><input id="firms-q" type="text" placeholder="{E(F["search"])}" aria-label="{E(F["search"])}" autocomplete="off" spellcheck="false" enterkeyhint="done"></span></label>
</div>
<div class="sidebar-layout">
<aside class="sidebar" id="firms-sidebar">
<div class="sidebar-head"><h2>Filters</h2></div>
<div id="facet-groups"></div>
</aside>
<div class="flist-wrap">
<div class="table-toolbar">
<button type="button" class="filters-open-btn" id="filters-open" aria-expanded="false">Filters<span class="facet-badge" id="filters-open-badge" hidden></span></button>
</div>
<div class="flist" id="firms-list"></div>
<p class="hint" id="firms-none" hidden>{E(F["none"])}</p>
<div id="firms-miss" hidden data-out="{E(F["miss_out"])}" data-in="{E(F["miss_in"])}">
<form class="frm" id="firms-miss-form"><input class="in" type="email" name="email" required maxlength="200" placeholder="{E(F["miss_placeholder"])}" aria-label="{E(F["miss_placeholder"])}" autocomplete="email"><button class="btn" type="submit">{E(F["miss_button"])}</button></form>
<p class="msg" id="firms-miss-msg"></p>
</div>
</div>
</div>
<div class="filters-backdrop" id="filters-backdrop" hidden></div>
<aside id="facet-panel" class="facet-panel" role="dialog" aria-modal="false" aria-labelledby="panel-title" hidden>
<div class="panel-top">
<div class="panel-title-row"><h2><span id="panel-title">Industries</span><span id="panel-total" class="panel-total"></span></h2><button type="button" id="panel-close" aria-label="Close">×</button></div>
<label class="panel-search"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="10" cy="10" r="7"></circle><path d="m15 15 6 6"></path></svg><input id="facet-search" placeholder="Search"></label>
</div>
<div id="pinned-options" class="pinned-options"></div>
<div id="remaining-label" class="list-caption panel-list-label"></div>
<div class="scroll-options"><div id="full-options" class="panel-option-grid"></div></div>
<div class="panel-bottom"><div><button type="button" class="panel-clear" id="panel-clear">Clear</button><span id="draft-count" class="draft-count"></span></div><button type="button" class="primary" id="panel-apply">Apply filters →</button></div>
</aside>
</main>"""
