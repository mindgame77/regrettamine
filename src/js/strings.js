/* Regretamin UI strings. Single source of copy.
   Shape: key -> { note, status?, variants: { variant: { when, text } } }.
   Build time: build.py replaces s-tokens (HTML) and sjs-tokens (inside JS string literals)
   with variants[variant || 'default'] text. Runtime: RS.t(key, variant, vars).
   RS.load(supabase) overrides from the ui_strings table (migration 20261014120000) and
   falls back to this bundled copy on any error. Change wording only with Alex's approval. */
window.RS_STRINGS = /*BEGIN_STRINGS*/{
 "brand.name": {
  "note": "Product name shown to users. Domain stays regretamine.com.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Regretamin"
   }
  }
 },
 "brand.wordmark_html": {
  "note": "Logo wordmark in nav and footer (HTML).",
  "variants": {
   "default": {
    "when": "always",
    "text": "regret<em>amin</em>"
   }
  }
 },
 "brand.domain": {
  "note": "Public domain. Not a brand name; keep the e.",
  "variants": {
   "default": {
    "when": "always",
    "text": "regretamine.com"
   }
  }
 },
 "scoring.step3.body": {
  "note": "Scoring page, how-it-works step 03.",
  "variants": {
   "default": {
    "when": "always",
    "text": "0 to 100, higher means fewer red flags in the sources we checked, from published rules."
   }
  }
 },
 "report.sentiment.label": {
  "note": "Public tab sentiment tag and filter.",
  "variants": {
   "pos": {
    "when": "item.sentiment = pos",
    "text": "Positive"
   },
   "neu": {
    "when": "item.sentiment = neu",
    "text": "Neutral"
   },
   "neg": {
    "when": "item.sentiment = neg",
    "text": "Negative"
   }
  }
 },
 "score.band": {
  "note": "Risk band label from the score (fund list, report).",
  "variants": {
   "very_low": {
    "when": "score 90-100",
    "text": "Very low risk"
   },
   "low": {
    "when": "score 75-89",
    "text": "Low risk"
   },
   "moderate": {
    "when": "score 50-74",
    "text": "Moderate"
   },
   "elevated": {
    "when": "score 25-49",
    "text": "Elevated"
   },
   "high": {
    "when": "score 0-24",
    "text": "High"
   }
  }
 },
 "score.band_short": {
  "note": "Short band label in filters.",
  "variants": {
   "very_low": {
    "when": "score 90-100",
    "text": "Very low"
   },
   "low": {
    "when": "score 75-89",
    "text": "Low"
   },
   "moderate": {
    "when": "score 50-74",
    "text": "Moderate"
   },
   "elevated": {
    "when": "score 25-49",
    "text": "Elevated"
   },
   "high": {
    "when": "score 0-24",
    "text": "High"
   }
  }
 },
 "auth.heading": {
  "note": "Auth/gate modal heading, one per modal mode (HTML).",
  "variants": {
   "gate": {
    "when": "anon hit the free report limit",
    "text": "Two funds in.<br>Don't <span class=\"mark\">regret the third</span>."
   },
   "page": {
    "when": "/login/ page",
    "text": "Check first.<br><span class=\"mark\">Sign second</span>."
   },
   "list": {
    "when": "anon opened the full fund list",
    "text": "Log in to see<br><span class=\"mark\">all <span id=\"listN\"></span> funds</span>."
   },
   "pay": {
    "when": "free account hit its report limit",
    "text": "You've checked 7 funds.<br>The 8th could be the one you <span class=\"mark\">regret</span>."
   },
   "plans": {
    "when": "plans placeholder",
    "text": "Plans"
   },
   "confirm": {
    "when": "signed up, email not confirmed",
    "text": "Confirm your email."
   },
   "forgot": {
    "when": "forgot password",
    "text": "Reset your password."
   },
   "reset": {
    "when": "recovery link opened",
    "text": "Choose a new password."
   }
  }
 },
 "auth.sub": {
  "note": "Auth/gate modal subline per mode.",
  "variants": {
   "list": {
    "when": "anon opened the full fund list",
    "text": "Free account. No card."
   },
   "gate": {
    "when": "anon hit the free report limit",
    "text": "A free account unlocks 5 more reports. No card."
   },
   "pay": {
    "when": "free account hit its report limit",
    "text": "Unlimited reports and alerts when a fund you're talking to gets sued."
   },
   "plans": {
    "when": "plans placeholder",
    "text": "Unlimited reports, when pricing is ready. Nothing to pay today."
   },
   "confirm": {
    "when": "signed up, email not confirmed",
    "text": "The extra 5 reports open after you confirm. We sent the link to your inbox."
   },
   "forgot": {
    "when": "forgot password",
    "text": "We'll email you a link to set a new password."
   },
   "reset": {
    "when": "recovery link opened",
    "text": "Use at least 6 characters."
   }
  }
 },
 "auth.submit": {
  "note": "Auth form submit button per mode.",
  "variants": {
   "signup": {
    "when": "mode signup",
    "text": "Create account"
   },
   "login": {
    "when": "mode login",
    "text": "Log in"
   },
   "forgot": {
    "when": "mode forgot",
    "text": "Send reset link"
   },
   "reset": {
    "when": "mode reset",
    "text": "Update password"
   }
  }
 },
 "plans.start_cta": {
  "note": "Plans page checkout button per plan.",
  "variants": {
   "monthly": {
    "when": "monthly plan",
    "text": "Start monthly"
   },
   "annual": {
    "when": "annual plan",
    "text": "Start annual"
   },
   "test": {
    "when": "test purchase (admin)",
    "text": "$1 test purchase"
   }
  }
 },
 "verdict.headline": {
  "status": "planned",
  "note": "Trust-check verdict pill/headline (new flow, not wired yet). Never say 'safe'.",
  "variants": {
   "clear": {
    "when": "all sources clear",
    "text": "No red flags found in these sources"
   },
   "review": {
    "when": ">=1 review, 0 flags",
    "text": "Mostly clear · {n} to review"
   },
   "flag": {
    "when": ">=1 flag",
    "text": "{n} red flags found"
   },
   "no_data": {
    "when": "no source returned data",
    "text": "No data yet"
   }
  }
 },
 "check.status": {
  "status": "planned",
  "note": "Databases checklist row status.",
  "variants": {
   "clear": {
    "when": "source returned no match",
    "text": "✓ Clear"
   },
   "review": {
    "when": "match needs review",
    "text": "! Review"
   },
   "flag": {
    "when": "confirmed adverse record",
    "text": "✕ Flag"
   },
   "no_data": {
    "when": "source not checked or failed",
    "text": "No data yet"
   },
   "queued": {
    "when": "firm not researched, worker queued",
    "text": "… Queued"
   }
  }
 },
 "unlock.cta": {
  "status": "planned",
  "note": "Full dossier button.",
  "variants": {
   "logged_out": {
    "when": "no session",
    "text": "Unlock full report"
   },
   "free": {
    "when": "free account",
    "text": "$49/mo · Unlock all dossiers"
   },
   "paid": {
    "when": "active subscription",
    "text": "Open full report"
   }
  }
 }
}/*END_STRINGS*/;
(function () {
  var S = window.RS_STRINGS;
  function t(key, variant, vars) {
    var k = S[key]; if (!k) return key;
    var v = k.variants[variant || 'default'] || k.variants.default || k.variants[Object.keys(k.variants)[0]];
    var s = v ? v.text : key;
    if (vars) s = s.replace(/\{(\w+)\}/g, function (m, n) { return n in vars ? vars[n] : m; });
    return s;
  }
  async function load(client, locale) {
    try {
      if (!client) return false;
      var res = await client.from('ui_strings').select('key,variant,text').eq('locale', locale || 'en');
      if (res.error || !res.data) return false;
      res.data.forEach(function (r) {
        var k = S[r.key] || (S[r.key] = { variants: {} });
        var v = k.variants[r.variant] || (k.variants[r.variant] = {});
        v.text = r.text;
      });
      return true;
    } catch (e) { return false; }
  }
  window.RS = { t: t, load: load, all: S };
})();
