/* Regretamin UI strings. Single source of copy.
   Shape: key -> { note, status?, variants: { variant: { when, text } } }.
   Build time: build.py replaces s-tokens (HTML) and sjs-tokens (inside JS string literals)
   with variants[variant || 'default'] text. Runtime: RS.t(key, variant, vars).
   RS.load(supabase) overrides from the ui_strings table (migration 20261014120000) and
   falls back to this bundled copy on any error. Change wording only with Alex's approval. */
window.RS_STRINGS = /*BEGIN_STRINGS*/{
 "brand.name": {
  "note": "Product name shown to users (logo alt text, titles, copy). The logo itself is assets/logo/lockup-*.svg. Domain stays regretamine.com.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Regretamin"
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
 },
 "common.vcs": {
  "note": "Shared page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "VCs"
   }
  }
 },
 "common.scoring": {
  "note": "Shared page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Scoring"
   }
  }
 },
 "common.pricing": {
  "note": "Shared page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Pricing"
   }
  }
 },
 "common.log_in": {
  "note": "Shared page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Log in"
   }
  }
 },
 "common.get_alerts": {
  "note": "Shared page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Get alerts"
   }
  }
 },
 "page.404.page_not_found": {
  "note": "404 page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Page not found"
   }
  }
 },
 "common.privacy": {
  "note": "Shared page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Privacy"
   }
  }
 },
 "common.terms": {
  "note": "Shared page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Terms"
   }
  }
 },
 "page.404.search_a_fund": {
  "note": "404 attribute text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Search a fund"
   }
  }
 },
 "common.watchlist": {
  "note": "Shared page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Watchlist"
   }
  }
 },
 "page.account.share_your_experience": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Share your experience"
   }
  }
 },
 "common.fund": {
  "note": "Shared page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Fund"
   }
  }
 },
 "page.account.how_are_you_connected": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "How are you connected?"
   }
  }
 },
 "page.account.founder_ceo": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Founder / CEO"
   }
  }
 },
 "page.account.co_founder": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Co-founder"
   }
  }
 },
 "page.account.executive": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Executive"
   }
  }
 },
 "page.account.employee": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Employee"
   }
  }
 },
 "page.account.pitched_but_no_deal": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Pitched but no deal"
   }
  }
 },
 "page.account.co_investor": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Co-investor"
   }
  }
 },
 "page.account.stage_when_they_invested": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Stage when they invested"
   }
  }
 },
 "page.account.pre_seed": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Pre-seed"
   }
  }
 },
 "page.account.seed": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Seed"
   }
  }
 },
 "page.account.series_a": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Series A"
   }
  }
 },
 "page.account.series_b": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Series B"
   }
  }
 },
 "page.account.series_c": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Series C+"
   }
  }
 },
 "page.account.growth": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Growth"
   }
  }
 },
 "page.account.rate_the_vc": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Rate the VC"
   }
  }
 },
 "page.account.honesty": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Honesty"
   }
  }
 },
 "page.account.support_after_the_check": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Support after the check"
   }
  }
 },
 "page.account.founder_friendly_terms": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Founder-friendly terms"
   }
  }
 },
 "page.account.responsiveness": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Responsiveness"
   }
  }
 },
 "page.account.in_hard_times": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "In hard times"
   }
  }
 },
 "page.account.would_you_take_their_money": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Would you take their money again?"
   }
  }
 },
 "page.account.yes": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Yes"
   }
  }
 },
 "page.account.no": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "No"
   }
  }
 },
 "page.account.what_should_the_next_founder": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "What should the next founder know?"
   }
  }
 },
 "page.account.verify_with_linkedin": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Verify with LinkedIn"
   }
  }
 },
 "page.account.used_only_to_confirm_you": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Used only to confirm you worked with this fund. Never shown."
   }
  }
 },
 "page.account.post_anonymously": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Post anonymously"
   }
  }
 },
 "page.account.your_name_is_hidden": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Your name is hidden"
   }
  }
 },
 "page.account.submit_review": {
  "note": "account page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Submit review"
   }
  }
 },
 "page.account.add_a_fund": {
  "note": "account attribute text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Add a fund"
   }
  }
 },
 "common.search_fund_name": {
  "note": "account attribute text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Search fund name"
   }
  }
 },
 "page.account.optional": {
  "note": "account attribute text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Optional"
   }
  }
 },
 "page.account.linkedin_com_in_your_name": {
  "note": "account attribute text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "linkedin.com/in/your-name"
   }
  }
 },
 "page.account.linkedin_profile": {
  "note": "account attribute text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "LinkedIn profile"
   }
  }
 },
 "page.admin.review": {
  "note": "admin page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Review"
   }
  }
 },
 "common.founder_reviews": {
  "note": "Shared page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Founder reviews"
   }
  }
 },
 "common.corrections": {
  "note": "Shared page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Corrections"
   }
  }
 },
 "page.deleted.your_account_was_deleted": {
  "note": "deleted page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Your account was deleted"
   }
  }
 },
 "page.deleted.your_profile_watchlist_and_saved": {
  "note": "deleted page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Your profile, watchlist, and saved reports are gone. You can look up a fund any time."
   }
  }
 },
 "page.deleted.back_to_vcs": {
  "note": "deleted page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Back to VCs"
   }
  }
 },
 "page.home.new": {
  "note": "home page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "New"
   }
  }
 },
 "page.home.lawsuits_regulators_and_conflicts_every": {
  "note": "home page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Lawsuits, regulators and conflicts, every source linked"
   }
  }
 },
 "page.home.take_the_money": {
  "note": "home page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Take the money"
   }
  }
 },
 "page.home.you": {
  "note": "home page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "you"
   }
  }
 },
 "page.home.won_t_regret": {
  "note": "home page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "won't regret"
   }
  }
 },
 "page.home.a_bad_investor_costs_you": {
  "note": "home page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "A bad investor costs you years. Check a fund's record before you sign the term sheet."
   }
  }
 },
 "page.home.check_fund": {
  "note": "home page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Check fund"
   }
  }
 },
 "page.home.filters": {
  "note": "home page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Filters"
   }
  }
 },
 "page.home.reset_all": {
  "note": "home page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Reset all"
   }
  }
 },
 "common.name": {
  "note": "Shared page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Name"
   }
  }
 },
 "page.home.risk_band": {
  "note": "home page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Risk band"
   }
  }
 },
 "page.home.score_range": {
  "note": "home page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Score range"
   }
  }
 },
 "page.home.firm_aum": {
  "note": "home page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Firm AUM"
   }
  }
 },
 "page.home.has_active_legal_matters": {
  "note": "home page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Has active legal matters"
   }
  }
 },
 "page.home.updated_in_the_last_30": {
  "note": "home page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Updated in the last 30 days"
   }
  }
 },
 "page.home.sort": {
  "note": "home page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Sort"
   }
  }
 },
 "page.home.score_high_to_low": {
  "note": "home page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Score: high to low"
   }
  }
 },
 "page.home.name_a_z": {
  "note": "home page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Name: A–Z"
   }
  }
 },
 "page.home.aum_largest_first": {
  "note": "home page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "AUM: largest first"
   }
  }
 },
 "page.home.last_updated": {
  "note": "home page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Last updated"
   }
  }
 },
 "page.home.latest_updates": {
  "note": "home page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Latest updates"
   }
  }
 },
 "common.regretamine_com_know_your_vc": {
  "note": "Shared page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "regretamine.com · Know your VC before you raise."
   }
  }
 },
 "common.andreessen_horowitz": {
  "note": "home attribute text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Andreessen Horowitz"
   }
  }
 },
 "page.home.fund_name": {
  "note": "home attribute text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Fund name"
   }
  }
 },
 "common.all_vcs": {
  "note": "Shared page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "← All VCs"
   }
  }
 },
 "page.plans.check_first": {
  "note": "plans page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Check first."
   }
  }
 },
 "page.plans.sign_second": {
  "note": "plans page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Sign second"
   }
  }
 },
 "page.plans.one_plan_with_everything_pay": {
  "note": "plans page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "One plan with everything. Pay monthly or yearly."
   }
  }
 },
 "page.plans.monthly": {
  "note": "plans page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Monthly"
   }
  }
 },
 "page.plans.month": {
  "note": "plans page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "/month"
   }
  }
 },
 "page.plans.billed_monthly": {
  "note": "plans page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Billed monthly"
   }
  }
 },
 "page.plans.start_monthly": {
  "note": "plans page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Start monthly"
   }
  }
 },
 "page.plans.every_fund_report_no_limit": {
  "note": "plans page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Every fund report, no limit"
   }
  }
 },
 "page.plans.full_reports_score_legal_fund": {
  "note": "plans page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Full reports: Score, Legal, Fund &amp; people, Public, Portfolio, Ask the fund"
   }
  }
 },
 "page.plans.watchlist_up_to_100_funds": {
  "note": "plans page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Watchlist up to 100 funds"
   }
  }
 },
 "page.plans.alerts_on_the_funds_you": {
  "note": "plans page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Alerts on the funds you watch"
   }
  }
 },
 "page.plans.recommended": {
  "note": "plans page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Recommended"
   }
  }
 },
 "page.plans.annual": {
  "note": "plans page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Annual"
   }
  }
 },
 "page.plans.save_40": {
  "note": "plans page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Save 40%"
   }
  }
 },
 "page.plans.billed_352_80_a_year": {
  "note": "plans page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Billed $352.80 a year"
   }
  }
 },
 "page.plans.start_annual": {
  "note": "plans page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Start annual"
   }
  }
 },
 "page.plans.not_ready_read_2_reports": {
  "note": "plans page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Not ready? Read 2 reports free, and 5 more with a free account."
   }
  }
 },
 "page.plans.1_test_purchase": {
  "note": "plans page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "$1 test purchase"
   }
  }
 },
 "common.legal": {
  "note": "Shared page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Legal"
   }
  }
 },
 "common.privacy_policy": {
  "note": "Shared page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Privacy Policy"
   }
  }
 },
 "legal.privacy.what_we_collect_why_and": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "What we collect, why, and what you can do about it."
   }
  }
 },
 "common.effective_oct_4_2026_see": {
  "note": "Shared page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Effective Oct 4, 2026 · See also"
   }
  }
 },
 "common.terms_of_service": {
  "note": "Shared page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Terms of Service"
   }
  }
 },
 "common.on_this_page": {
  "note": "Shared page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "On this page"
   }
  }
 },
 "legal.privacy.who_we_are": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Who we are"
   }
  }
 },
 "legal.privacy.what_we_collect": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "What we collect"
   }
  }
 },
 "legal.privacy.storage_on_your_device": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Storage on your device"
   }
  }
 },
 "legal.privacy.how_we_use_it": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "How we use it"
   }
  }
 },
 "legal.privacy.information_about_people_at_funds": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Information about people at funds"
   }
  }
 },
 "legal.privacy.who_we_share_it_with": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Who we share it with"
   }
  }
 },
 "legal.privacy.how_long_we_keep_it": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "How long we keep it"
   }
  }
 },
 "legal.privacy.your_rights": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Your rights"
   }
  }
 },
 "legal.privacy.children": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Children"
   }
  }
 },
 "legal.privacy.security": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Security"
   }
  }
 },
 "common.changes": {
  "note": "Shared page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Changes"
   }
  }
 },
 "common.contact": {
  "note": "Shared page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Contact"
   }
  }
 },
 "common.the_short_version": {
  "note": "Shared page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "The short version"
   }
  }
 },
 "legal.privacy.we_store_your_account_watchlist": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "We store your account, watchlist, alert settings, report views and reviews. That's it."
   }
  }
 },
 "legal.privacy.no_ads_and_we_never": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "No ads, and we never sell your data."
   }
  }
 },
 "legal.privacy.reviews_are_anonymous_by_default": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Reviews are anonymous by default, and verification proof is never shown."
   }
  }
 },
 "legal.privacy.you_can_export_or_delete": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "You can export or delete your data any time."
   }
  }
 },
 "legal.privacy.we_us_who_is_the": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "(\"we\", \"us\"), who is the controller of your personal data."
   }
  }
 },
 "legal.privacy.data": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Data"
   }
  }
 },
 "legal.privacy.what_and_why": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "What and why"
   }
  }
 },
 "common.account": {
  "note": "Shared page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Account"
   }
  }
 },
 "legal.privacy.email_address_and_a_hashed": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Email address and a hashed password, or, if you use Google sign-in, the name, email address and profile picture Google shares with us. Used to create and secure your account. We also keep the name and website you save on your profile."
   }
  }
 },
 "legal.privacy.the_funds_you_save_up": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "The funds you save (up to 100). Used to show your list and send alerts."
   }
  }
 },
 "legal.privacy.alert_preferences": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Alert preferences"
   }
  }
 },
 "legal.privacy.which_alert_types_you_want": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Which alert types you want by email. Used to send only those emails."
   }
  }
 },
 "legal.privacy.report_views": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Report views"
   }
  }
 },
 "legal.privacy.which_fund_reports_you_opened": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Which fund reports you opened and when. Used to apply the free limit (2 reports, then 5 more with an account) and to show your history."
   }
  }
 },
 "legal.privacy.reviews": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Reviews"
   }
  }
 },
 "legal.privacy.your_ratings_and_comments_about": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Your ratings and comments about a fund, your role and stage when it invested, and any verification details you provide (work email, LinkedIn profile or cap table)."
   }
  }
 },
 "legal.privacy.payment_records": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Payment records"
   }
  }
 },
 "legal.privacy.stripe_processes_payments_we_never": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Stripe processes payments. We never store card numbers. We store your Stripe customer id, subscription id, plan, payment amounts, dates, and receipt links."
   }
  }
 },
 "legal.privacy.technical_data": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Technical data"
   }
  }
 },
 "legal.privacy.ip_address_and_browser_details": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "IP address and browser details that our hosting providers log automatically for security and reliability."
   }
  }
 },
 "legal.privacy.if_you_are_not_logged": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "If you are not logged in, we keep a count of the fund reports you have opened in your browser's localStorage so the free limit works without an account. Logging in stores a session token in your browser so you stay signed in. Clearing your browser storage removes both."
   }
  }
 },
 "legal.privacy.we_don_t_use_advertising": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "We don't use advertising cookies or ad trackers."
   }
  }
 },
 "legal.privacy.provide_the_service_your_account": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Provide the service: your account, watchlist, alerts, report history and reviews."
   }
  }
 },
 "legal.privacy.enforce_free_view_limits_and": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Enforce free view limits and paid plans."
   }
  }
 },
 "legal.privacy.keep_the_service_secure_and": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Keep the service secure and prevent abuse such as scraping or fake reviews."
   }
  }
 },
 "legal.privacy.answer_your_messages_and_correction": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Answer your messages and correction requests."
   }
  }
 },
 "legal.privacy.we": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "We"
   }
  }
 },
 "legal.privacy.don_t_sell": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "don't sell"
   }
  }
 },
 "legal.privacy.your_personal_data_don_t": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "your personal data, don't share it for advertising, and don't show ads."
   }
  }
 },
 "legal.privacy.legal_bases_eu_uk": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Legal bases (EU/UK):"
   }
  }
 },
 "legal.privacy.performance_of_our_contract_with": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "performance of our contract with you (account features), legitimate interests (security, abuse prevention, publishing fund information), consent (alert emails, which you can switch off any time), and legal obligations."
   }
  }
 },
 "legal.privacy.reviews_are": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Reviews are"
   }
  }
 },
 "legal.privacy.anonymous_by_default": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "anonymous by default"
   }
  }
 },
 "legal.privacy.others_see_only_a_label": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": ". Others see only a label such as \"Founder, Seed\", unless you choose to show your name."
   }
  }
 },
 "legal.privacy.every_review_is_checked_by": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Every review is checked by us before it is published."
   }
  }
 },
 "legal.privacy.verification_details_are_used": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Verification details are used"
   }
  }
 },
 "legal.privacy.only_to_confirm": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "only to confirm"
   }
  }
 },
 "legal.privacy.that_you_took_money_from": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "that you took money from the fund. They are never shown publicly or to the fund."
   }
  }
 },
 "legal.privacy.we_keep_the_link_between": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "We keep the link between your account and your review internally. We disclose it only if the law requires us to."
   }
  }
 },
 "legal.privacy.fund_reports_include_professional_information": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Fund reports include professional information about investors and fund staff (for example names, roles and court or regulatory records) taken from public sources such as court records, SEC filings and the press. We publish it because founders have a legitimate interest in knowing who they take money from. If you are named and believe something is wrong, you can ask us to correct it or object; see"
   }
  }
 },
 "legal.privacy.supabase": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Supabase"
   }
  }
 },
 "legal.privacy.hosts_our_database_and_handles": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": ": hosts our database and handles sign-in, in the United States."
   }
  }
 },
 "legal.privacy.github_pages": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "GitHub Pages"
   }
  }
 },
 "legal.privacy.hosts_the_website": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": ": hosts the website."
   }
  }
 },
 "legal.privacy.google": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Google"
   }
  }
 },
 "legal.privacy.if_you_choose_google_sign": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": ": if you choose Google sign-in. Our pages also load fonts from Google Fonts, which receives your IP address."
   }
  }
 },
 "legal.privacy.an_email_delivery_provider": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "An email delivery provider"
   }
  }
 },
 "legal.privacy.to_send_sign_in_and": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": ": to send sign-in and alert emails."
   }
  }
 },
 "legal.privacy.stripe": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Stripe"
   }
  }
 },
 "legal.privacy.processes_payments_we_never_store": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": ": processes payments. We never store card numbers. We store your Stripe customer id, subscription id, plan, payment amounts, dates, and receipt links."
   }
  }
 },
 "legal.privacy.authorities": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Authorities"
   }
  }
 },
 "legal.privacy.only_when_the_law_requires": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": ": only when the law requires it."
   }
  }
 },
 "legal.privacy.these_providers_process_data_on": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "These providers process data on our behalf under their own terms and security measures. Because they are in the US, your data may be transferred outside your country; where required, we rely on standard contractual clauses or similar safeguards."
   }
  }
 },
 "legal.privacy.account_watchlist_preferences_and_report": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Account, watchlist, preferences and report history: while your account exists. Deleted within 30 days of account deletion, and from backups within 90 days."
   }
  }
 },
 "legal.privacy.verification_details_deleted_once_verification": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Verification details: deleted once verification is done, at most 30 days after you submit them."
   }
  }
 },
 "legal.privacy.published_reviews_until_you_delete": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Published reviews: until you delete them or your account. Scores they already contributed to may keep using them in anonymised, aggregated form."
   }
  }
 },
 "legal.privacy.hosting_logs_as_long_as": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Hosting logs: as long as our providers keep them for security."
   }
  }
 },
 "legal.privacy.you_can_ask_to": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "You can ask to"
   }
  }
 },
 "legal.privacy.access": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "access"
   }
  }
 },
 "legal.privacy.correct": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "correct"
   }
  }
 },
 "legal.privacy.delete": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "delete"
   }
  }
 },
 "legal.privacy.or": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "or"
   }
  }
 },
 "legal.privacy.export": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "export"
   }
  }
 },
 "legal.privacy.eu_uk": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "EU/UK:"
   }
  }
 },
 "legal.privacy.you_can_also_complain_to": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "you can also complain to your local data protection authority."
   }
  }
 },
 "legal.privacy.california": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "California:"
   }
  }
 },
 "legal.privacy.you_have_the_right_to": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "you have the right to know, delete and correct your personal information and not to be discriminated against for using these rights. We don't sell or share personal information as the CCPA defines those terms."
   }
  }
 },
 "legal.privacy.data_is_encrypted_in_transit": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Data is encrypted in transit, passwords are stored hashed, and access to our database is restricted. No system is perfectly secure, so please use a strong, unique password."
   }
  }
 },
 "legal.privacy.if_we_change_this_policy": {
  "note": "privacy page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "If we change this policy, we'll update the date above. For significant changes we'll tell account holders by email or on the site before they take effect."
   }
  }
 },
 "page.reset_redirect.reset_password": {
  "note": "reset_redirect page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Reset password"
   }
  }
 },
 "page.scoring.how_it_works": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "How it works"
   }
  }
 },
 "page.scoring.from_public_record_to_score": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "From public record to score."
   }
  }
 },
 "page.scoring.we_check_how_a_vc": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "We check how a VC fund treats founders, using sources you can open yourself."
   }
  }
 },
 "page.scoring.we_pull_the_public_record": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "We pull the public record."
   }
  }
 },
 "page.scoring.we_verify_every_source": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "We verify every source."
   }
  }
 },
 "page.scoring.it_counts_only_if_it": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "It counts only if it links, names the fund and shows its role."
   }
  }
 },
 "page.scoring.we_score_the_fund": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "We score the fund."
   }
  }
 },
 "page.scoring.how_scoring_works": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "How scoring works →"
   }
  }
 },
 "page.scoring.you_check_before_you_sign": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "You check before you sign."
   }
  }
 },
 "page.scoring.read_the_report_save_the": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Read the report, save the fund, get alerts when it changes."
   }
  }
 },
 "page.scoring.what_we_check": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "What we check"
   }
  }
 },
 "page.scoring.area": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Area"
   }
  }
 },
 "page.scoring.sources": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Sources"
   }
  }
 },
 "page.scoring.legal_records": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Legal records"
   }
  }
 },
 "page.scoring.federal_dockets_pacer_courtlistener_and": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Federal dockets (PACER, CourtListener) and state courts: suits by or against the fund, its partners as directors, and its own companies."
   }
  }
 },
 "page.scoring.regulators_and_sanctions": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Regulators and sanctions"
   }
  }
 },
 "page.scoring.sec_form_adv_and_form": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "SEC Form ADV and Form D, SEC and DOJ actions, OFAC, EU, UK and UN sanctions lists (exact identity matches only)."
   }
  }
 },
 "page.scoring.press": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Press"
   }
  }
 },
 "page.scoring.named_dated_reporting_from_outlets": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Named, dated reporting from outlets such as TechCrunch, Bloomberg and Reuters. Anonymous-only claims don't count."
   }
  }
 },
 "page.scoring.founder_experiences": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Founder experiences"
   }
  }
 },
 "page.scoring.first_hand_reviews_from_founders": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "First-hand reviews from founders and executives, verified via LinkedIn and anonymous by default."
   }
  }
 },
 "page.scoring.reports": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Reports"
   }
  }
 },
 "page.scoring.free_2": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Free · 2"
   }
  }
 },
 "page.scoring.free_account_5_more": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Free account · 5 more"
   }
  }
 },
 "page.scoring.plans": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Plans"
   }
  }
 },
 "page.scoring.reopening_a_fund_you_ve": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Reopening a fund you've seen is free."
   }
  }
 },
 "page.scoring.create_account": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Create account"
   }
  }
 },
 "page.scoring.spotted_a_wrong_fact_send": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Spotted a wrong fact? Send the page, what's wrong and a source. We review every request."
   }
  }
 },
 "page.scoring.request_a_correction": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Request a correction"
   }
  }
 },
 "page.scoring.what_s_wrong": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "What's wrong"
   }
  }
 },
 "page.scoring.source": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Source"
   }
  }
 },
 "page.scoring.send_correction": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Send correction"
   }
  }
 },
 "page.scoring.how_the_score_works": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "How the score works."
   }
  }
 },
 "page.scoring.it_measures_how_a_fund": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "It measures how a fund treats its own founders, not its portfolio's luck."
   }
  }
 },
 "page.scoring.version_2_agreed_oct_2": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Version 2 · agreed Oct 2, 2026"
   }
  }
 },
 "page.scoring.fund_vs_founders": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Fund vs. founders"
   }
  }
 },
 "page.scoring.its_own_startups_founders_and": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Its own startups, founders and executives"
   }
  }
 },
 "page.scoring.ability_to_support_you": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Ability to support you"
   }
  }
 },
 "page.scoring.money_media_reach_help_after": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Money, media reach, help after the check"
   }
  }
 },
 "page.scoring.founder_experience": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Founder experience"
   }
  }
 },
 "page.scoring.first_hand_accounts_only": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "First-hand accounts only"
   }
  }
 },
 "page.scoring.conflicts_of_interest": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Conflicts of interest"
   }
  }
 },
 "page.scoring.competing_boards_and_in_house": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Competing boards and in-house rivals"
   }
  }
 },
 "page.scoring.track_record_bonus": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Track record bonus"
   }
  }
 },
 "page.scoring.years_investing_without_a_pattern": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Years investing without a pattern of harm"
   }
  }
 },
 "page.scoring.0_to_50": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "0 to −50"
   }
  }
 },
 "page.scoring.regulatory_penalty": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Regulatory penalty"
   }
  }
 },
 "page.scoring.probes_charges_fines_sanctions": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Probes, charges, fines, sanctions"
   }
  }
 },
 "page.scoring.score": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Score"
   }
  }
 },
 "page.scoring.sections_1_4_bonus_regulatory": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "= sections 1–4 + bonus − regulatory penalty, capped at 0–100."
   }
  }
 },
 "page.scoring.principles": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Principles"
   }
  }
 },
 "page.scoring.every_fund_starts_with_full": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Every fund starts with full points and loses them only for verified evidence about its own behavior."
   }
  }
 },
 "page.scoring.rates_not_counts_bad_events": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Rates, not counts: bad events are measured as a share of all companies backed."
   }
  }
 },
 "page.scoring.copycat_names_are_excluded": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Copycat names are excluded."
   }
  }
 },
 "page.scoring.a_suit_the_fund_brought": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "A suit the fund brought differs from one brought against it."
   }
  }
 },
 "page.scoring.coverage_is_shown_separately_missing": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Coverage is shown separately. Missing data lowers coverage, not the score."
   }
  }
 },
 "page.scoring.rate_scale": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Rate scale"
   }
  }
 },
 "page.scoring.share_of_portfolio_affected": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Share of portfolio affected"
   }
  }
 },
 "page.scoring.effect": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Effect"
   }
  }
 },
 "page.scoring.under_1": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Under 1%"
   }
  }
 },
 "page.scoring.no_penalty": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "No penalty"
   }
  }
 },
 "page.scoring.about_10_of_the_section": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "About 10% of the section"
   }
  }
 },
 "page.scoring.about_35": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "About 35%"
   }
  }
 },
 "page.scoring.over_10": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Over 10%"
   }
  }
 },
 "page.scoring.about_70_or_more": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "About 70% or more"
   }
  }
 },
 "page.scoring.bands": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Bands"
   }
  }
 },
 "page.scoring.band": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Band"
   }
  }
 },
 "page.scoring.very_low_risk": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Very low risk"
   }
  }
 },
 "page.scoring.low_risk": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Low risk"
   }
  }
 },
 "page.scoring.moderate": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Moderate"
   }
  }
 },
 "page.scoring.elevated": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Elevated"
   }
  }
 },
 "page.scoring.under_25": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Under 25"
   }
  }
 },
 "page.scoring.high": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "High"
   }
  }
 },
 "page.scoring.any_sanctions_finding_shows_a": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Any sanctions finding shows a red banner, whatever the score."
   }
  }
 },
 "page.scoring.the_rules": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "The rules"
   }
  }
 },
 "page.scoring.1_fund_vs_founders": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "1 · Fund vs. founders"
   }
  }
 },
 "page.scoring.sub_part": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Sub-part"
   }
  }
 },
 "page.scoring.points": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Points"
   }
  }
 },
 "page.scoring.lawsuits_with_its_own_startups": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Lawsuits with its own startups or founders"
   }
  }
 },
 "page.scoring.pushing_out_founder_ceos": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Pushing out founder CEOs"
   }
  }
 },
 "page.scoring.down_round_or_pay_to": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Down-round or pay-to-play behavior"
   }
  }
 },
 "page.scoring.blocking_acquisitions_or_rounds": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Blocking acquisitions or rounds"
   }
  }
 },
 "page.scoring.3_per_case_the_fund": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "−3 per case the fund lost or where fraud was found, even under 1%."
   }
  }
 },
 "page.scoring.2_ability_to_support_you": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "2 · Ability to support you"
   }
  }
 },
 "page.scoring.money_fund_size_money_left": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Money: fund size, money left, hit target"
   }
  }
 },
 "page.scoring.media_reach_capped": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Media reach (capped)"
   }
  }
 },
 "page.scoring.help_after_the_check_incl": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Help after the check, incl. partner stability"
   }
  }
 },
 "page.scoring.claims_the_fund_makes_about": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Claims the fund makes about itself count at half until founders confirm them."
   }
  }
 },
 "page.scoring.0_5_for_each_calendar": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "−0.5 for each calendar year with at least one partner departure, up to −2"
   }
  }
 },
 "page.scoring.3_founder_experience": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "3 · Founder experience"
   }
  }
 },
 "page.scoring.only_first_hand_accounts_from": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Only first-hand accounts from a founder or named ex-executive."
   }
  }
 },
 "page.scoring.negatives_under_1_age_default": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Negatives under 1%: age default"
   }
  }
 },
 "page.scoring.10_years_and_over_500": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "10+ years and over 500 companies"
   }
  }
 },
 "page.scoring.10_years": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "10+ years"
   }
  }
 },
 "page.scoring.5_10_years": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "5–10 years"
   }
  }
 },
 "page.scoring.2_5_years": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "2–5 years"
   }
  }
 },
 "page.scoring.under_2_years_or_a": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Under 2 years or a first fund"
   }
  }
 },
 "page.scoring.feedback_1_or_more_tone": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Feedback 1% or more: tone"
   }
  }
 },
 "page.scoring.mostly_positive": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Mostly positive"
   }
  }
 },
 "page.scoring.mixed": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Mixed"
   }
  }
 },
 "page.scoring.mostly_negative": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Mostly negative"
   }
  }
 },
 "page.scoring.pattern_of_serious_harm": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Pattern of serious harm"
   }
  }
 },
 "page.scoring.fewer_than_5_accounts_average": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Fewer than 5 accounts: average of tone score and age default."
   }
  }
 },
 "page.scoring.accounts_older_than_5_years": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Accounts older than 5 years count half."
   }
  }
 },
 "page.scoring.4_conflicts_of_interest": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "4 · Conflicts of interest"
   }
  }
 },
 "page.scoring.partners_on_competing_boards_backing": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Partners on competing boards, backing a founder's direct competitor, in-house companies that compete with portfolio companies. −1 per documented conflict, scaled by partner count. Can't go below 0."
   }
  }
 },
 "page.scoring.5_track_record_bonus": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "5 · Track record bonus"
   }
  }
 },
 "page.scoring.1_per_5_years_of": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "+1 per 5 years of investing with no significant pattern of harm."
   }
  }
 },
 "page.scoring.6_regulatory_penalty": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "6 · Regulatory penalty"
   }
  }
 },
 "page.scoring.event": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Event"
   }
  }
 },
 "page.scoring.open_investigation_no_charges": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Open investigation, no charges"
   }
  }
 },
 "page.scoring.charges_filed": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Charges filed"
   }
  }
 },
 "page.scoring.fine_or_settlement": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Fine or settlement"
   }
  }
 },
 "page.scoring.10_to_20": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "−10 to −20"
   }
  }
 },
 "page.scoring.fraud_finding_or_partner_barred": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Fraud finding, or partner barred"
   }
  }
 },
 "page.scoring.sanctioned_partner_or_sanctioned_money": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Sanctioned partner or sanctioned money"
   }
  }
 },
 "page.scoring.50_red_banner": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "−50 + red banner"
   }
  }
 },
 "page.scoring.shareholder_suit_vs_partner_as": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Shareholder suit vs. partner as public-company director"
   }
  }
 },
 "page.scoring.0_5_to_1": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "−0.5 to −1"
   }
  }
 },
 "page.scoring.sanctions_need_an_exact_identity": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Sanctions need an exact identity match, never name-only. Counter-sanctions cost 0."
   }
  }
 },
 "page.scoring.crypto_token_buyer_class_actions": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Crypto token-buyer class actions are context only and cost 0."
   }
  }
 },
 "page.scoring.worked_example": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Worked example"
   }
  }
 },
 "page.scoring.open_the_report": {
  "note": "scoring page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Open the report →"
   }
  }
 },
 "page.settings.billing": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Billing"
   }
  }
 },
 "page.settings.we_couldn_t_charge_your": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "We couldn't charge your card. Update it within 24 hours or your account moves to the free plan."
   }
  }
 },
 "page.settings.update_card": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Update card"
   }
  }
 },
 "page.settings.profile": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Profile"
   }
  }
 },
 "page.settings.website": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Website"
   }
  }
 },
 "page.settings.save": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Save"
   }
  }
 },
 "page.settings.email": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Email"
   }
  }
 },
 "page.settings.change_email": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Change email"
   }
  }
 },
 "page.settings.new_email": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "New email"
   }
  }
 },
 "page.settings.current_password": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Current password"
   }
  }
 },
 "page.settings.we_ll_send_a_confirmation": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "We'll send a confirmation link to the new email. The change applies once you click it."
   }
  }
 },
 "page.settings.send_confirmation_link": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Send confirmation link"
   }
  }
 },
 "page.settings.cancel": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Cancel"
   }
  }
 },
 "page.settings.password": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Password"
   }
  }
 },
 "page.settings.change_password": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Change password"
   }
  }
 },
 "page.settings.new_password": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "New password"
   }
  }
 },
 "page.settings.confirm_new_password": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Confirm new password"
   }
  }
 },
 "page.settings.update_password": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Update password"
   }
  }
 },
 "page.settings.danger_zone": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Danger zone"
   }
  }
 },
 "page.settings.delete_account": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Delete account"
   }
  }
 },
 "page.settings.permanently_deletes_your_account_and": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Permanently deletes your account and everything in it."
   }
  }
 },
 "page.settings.payment_received_your_plan_will": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Payment received, your plan will update in a few seconds"
   }
  }
 },
 "page.settings.free": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Free"
   }
  }
 },
 "page.settings.next_charge": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Next charge"
   }
  }
 },
 "page.settings.switch_between_monthly_and_annual": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Switch between monthly and annual billing."
   }
  }
 },
 "page.settings.change_plan": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Change plan →"
   }
  }
 },
 "page.settings.payment_method": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Payment method"
   }
  }
 },
 "page.settings.no_card_on_file": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "No card on file"
   }
  }
 },
 "page.settings.manage_card": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Manage card"
   }
  }
 },
 "page.settings.delete_card": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Delete card"
   }
  }
 },
 "page.settings.payments": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Payments"
   }
  }
 },
 "page.settings.date": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Date"
   }
  }
 },
 "page.settings.description": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Description"
   }
  }
 },
 "page.settings.amount": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Amount"
   }
  }
 },
 "page.settings.status": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Status"
   }
  }
 },
 "page.settings.no_payments_yet": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "No payments yet."
   }
  }
 },
 "page.settings.delete_your_account": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Delete your account?"
   }
  }
 },
 "page.settings.everything_about_you_is_deleted": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Everything about you is deleted permanently. This can't be undone."
   }
  }
 },
 "page.settings.profile_and_login": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Profile and login"
   }
  }
 },
 "page.settings.alerts_and_alert_settings": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Alerts and alert settings"
   }
  }
 },
 "page.settings.report_history": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Report history"
   }
  }
 },
 "page.settings.shared_experiences": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Shared experiences"
   }
  }
 },
 "page.settings.billing_info_and_saved_card": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Billing info and saved card"
   }
  }
 },
 "page.settings.your_plan_is_cancelled_with": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Your plan is cancelled with it. No more charges."
   }
  }
 },
 "page.settings.delete_my_account": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Delete my account"
   }
  }
 },
 "page.settings.delete_this_card": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Delete this card?"
   }
  }
 },
 "page.settings.without_a_card_we_can": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Without a card we can't charge you. If your next charge fails, we'll email you. After 24 hours without a card, your account moves to the free plan."
   }
  }
 },
 "page.settings.keep_card": {
  "note": "settings page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Keep card"
   }
  }
 },
 "page.settings.example_com": {
  "note": "settings attribute text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "example.com"
   }
  }
 },
 "page.settings.you_company_com": {
  "note": "settings attribute text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "you@company.com"
   }
  }
 },
 "page.settings.at_least_6_characters": {
  "note": "settings attribute text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "At least 6 characters"
   }
  }
 },
 "page.settings.repeat_it": {
  "note": "settings attribute text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Repeat it"
   }
  }
 },
 "page.settings.close": {
  "note": "settings attribute text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Close"
   }
  }
 },
 "page.settings.type_delete_or_your_email": {
  "note": "settings attribute text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Type DELETE or your email"
   }
  }
 },
 "page.settings.confirm": {
  "note": "settings attribute text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Confirm"
   }
  }
 },
 "legal.terms.agreement": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Agreement"
   }
  }
 },
 "legal.terms.accounts": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Accounts"
   }
  }
 },
 "legal.terms.subscriptions": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Subscriptions"
   }
  }
 },
 "legal.terms.free_reports_and_paid_plans": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Free reports and paid plans"
   }
  }
 },
 "legal.terms.fund_information_is_not_advice": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Fund information is not advice"
   }
  }
 },
 "legal.terms.your_reviews": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Your reviews"
   }
  }
 },
 "legal.terms.acceptable_use": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Acceptable use"
   }
  }
 },
 "legal.terms.our_content": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Our content"
   }
  }
 },
 "legal.terms.suspension_and_termination": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Suspension and termination"
   }
  }
 },
 "legal.terms.disclaimers": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Disclaimers"
   }
  }
 },
 "legal.terms.limitation_of_liability": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Limitation of liability"
   }
  }
 },
 "legal.terms.governing_law": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Governing law"
   }
  }
 },
 "legal.terms.you_must_be_18_one": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "You must be 18+. One account per person."
   }
  }
 },
 "legal.terms.reports_are_information_and_opinion": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Reports are information and opinion from public sources, not investment or legal advice."
   }
  }
 },
 "legal.terms.reviews_must_be_honest_and": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Reviews must be honest and first-hand. We moderate them before publishing."
   }
  }
 },
 "legal.terms.no_scraping_no_gaming_the": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "No scraping, no gaming the free view limits."
   }
  }
 },
 "legal.terms.these_terms_are_an_agreement": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "These terms are an agreement between you and"
   }
  }
 },
 "legal.terms.you_must_be_at_least": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "You must be at least 18."
   }
  }
 },
 "legal.terms.sign_up_with_google_or": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Sign up with Google or with an email and password. Give accurate information and keep your password safe."
   }
  }
 },
 "legal.terms.one_account_per_person_you": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "One account per person. You're responsible for activity on your account."
   }
  }
 },
 "legal.terms.you_can_delete_your_account": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "You can delete your account yourself in Settings. Deleting it cancels a paid plan and removes your profile, watchlist, alerts, and billing record. You don't need to email us."
   }
  }
 },
 "legal.terms.paid_plans_are_monthly_at": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Paid plans are Monthly at $49 or Annual at $352.80. A subscription renews automatically until you cancel. You can cancel any time from Settings &gt; Billing. After you cancel, access continues until the end of the paid period. We don't refund partial periods. If a payment fails, you keep paid access for 24 hours. After that, the account moves to the free plan until the card succeeds. Stripe processes payments."
   }
  }
 },
 "legal.terms.without_an_account_you_can": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Without an account you can open 2 fund reports. A free account unlocks 5 more. Reopening a report you've already seen is free. We may change the free limits, with notice on the site."
   }
  }
 },
 "legal.terms.watchlists_hold_up_to_100": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Watchlists hold up to 100 funds. Alerts are sent on a best-effort basis and may be delayed or miss events."
   }
  }
 },
 "legal.terms.fund_reports_are_compiled_from": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Fund reports are compiled from public sources, including court records, SEC and other regulatory filings, and press coverage. Each scored fact links to its source."
   }
  }
 },
 "legal.terms.scores_are_opinions": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Scores are opinions."
   }
  }
 },
 "legal.terms.they_come_from_our_published": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "They come from our published methodology and are not statements of fact about any person or fund."
   }
  }
 },
 "legal.terms.reports_can_be_incomplete_out": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Reports can be incomplete, out of date or wrong. A lawsuit or probe is not a finding of wrongdoing."
   }
  }
 },
 "legal.terms.funds_people_named_in_reports": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Funds, people named in reports, and anyone else can request a correction, free of charge. Send the page, what's wrong, and a source. We review every request and update or annotate the report where warranted."
   }
  }
 },
 "legal.terms.only_review_a_fund_you": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Only review a fund you took money from, or were in a funded round with, as a founder or executive."
   }
  }
 },
 "legal.terms.be_accurate_and_first_hand": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Be accurate and first-hand. No false, exaggerated or paid reviews, no reviews of your own employer or a competitor, and no confidential information you're not allowed to share."
   }
  }
 },
 "legal.terms.we_moderate_reviews_before_publishing": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "We moderate reviews before publishing and may decline, edit for formatting, or remove any review."
   }
  }
 },
 "legal.terms.license": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "License."
   }
  }
 },
 "legal.terms.don_t": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Don't:"
   }
  }
 },
 "legal.terms.scrape_crawl_or_bulk_download": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Scrape, crawl or bulk-download reports or data, or use bots to access the site."
   }
  }
 },
 "legal.terms.get_around_view_limits_for": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Get around view limits, for example with multiple accounts or by clearing storage to reset counts at scale."
   }
  }
 },
 "legal.terms.post_false_defamatory_harassing_or": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Post false, defamatory, harassing or unlawful content, or impersonate anyone."
   }
  }
 },
 "legal.terms.probe_disrupt_or_reverse_engineer": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Probe, disrupt or reverse-engineer the service, or access other people's accounts."
   }
  }
 },
 "legal.terms.resell_or_republish_our_reports": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Resell or republish our reports without permission."
   }
  }
 },
 "legal.terms.the_site_design_reports_scores": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "The site design, reports, scores and methodology belong to us. You may share links and quote short excerpts with attribution. The underlying public records belong to their sources."
   }
  }
 },
 "legal.terms.to_the_extent_the_law": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "To the extent the law allows, we are not liable for indirect, incidental or consequential losses, or for decisions you make based on the site, including whether to take investment from any fund. Our total liability for any claim is limited to the greater of USD 100 or the amount you paid us in the 12 months before the claim. Some places don't allow these limits, so they may not apply to you."
   }
  }
 },
 "legal.terms.these_terms_are_governed_by": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "These terms are governed by the laws of the State of Delaware, and disputes go to the courts of the State of Delaware, unless consumer law where you live says otherwise."
   }
  }
 },
 "legal.terms.we_may_update_these_terms": {
  "note": "terms page text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "We may update these terms. We'll change the date above and, for material changes, tell account holders before they take effect. If you keep using the site after that, the new terms apply."
   }
  }
 },
 "js.account.new_legal_matter": {
  "note": "account.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "New legal matter"
   }
  }
 },
 "js.account.score_change": {
  "note": "account.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Score change"
   }
  }
 },
 "js.account.your_name_will_be_shown": {
  "note": "account.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Your name will be shown"
   }
  }
 },
 "js.account.pick_a_fund_from_the": {
  "note": "account.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Pick a fund from the list."
   }
  }
 },
 "js.account.say_whether_you_would_take": {
  "note": "account.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Say whether you would take their money again."
   }
  }
 },
 "js.account.log_in_before_you_send": {
  "note": "account.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Log in before you send a review."
   }
  }
 },
 "js.account.that_fund_is_not_in": {
  "note": "account.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "That fund is not in the database yet."
   }
  }
 },
 "js.auth.re_on_the_free_plan": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "re on the free plan now. Update your card to restore access."
   }
  }
 },
 "js.auth.t_charge_your_card_update": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "t charge your card. Update it within 24 hours or your account moves to the free plan."
   }
  }
 },
 "js.auth.share_experience": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Share experience"
   }
  }
 },
 "js.auth.sign_in_is_not_configured": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Sign-in is not configured on this build."
   }
  }
 },
 "js.auth.could_not_save": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Could not save"
   }
  }
 },
 "js.auth.could_not_update_alerts": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Could not update alerts"
   }
  }
 },
 "js.auth.too_many_sign_ups_right": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Too many sign-ups right now, try again in a few minutes"
   }
  }
 },
 "js.auth.reset_link_sent_check_your": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Reset link sent. Check your email."
   }
  }
 },
 "js.auth.use_at_least_6_characters": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Use at least 6 characters."
   }
  }
 },
 "js.auth.password_updated": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Password updated."
   }
  }
 },
 "js.auth.enter_the_email_you_signed": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Enter the email you signed up with."
   }
  }
 },
 "js.auth.sent_again": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Sent again."
   }
  }
 },
 "js.fund_list.open_full_report": {
  "note": "fund_list.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Open full report"
   }
  }
 },
 "js.fund_list.full_report_coming_soon": {
  "note": "fund_list.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Full report coming soon"
   }
  }
 },
 "js.fund_list.none_found": {
  "note": "fund_list.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "None found"
   }
  }
 },
 "js.gate.1_free_report_left_make": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "1 free report left. Make it count."
   }
  }
 },
 "js.gate.lorem_ipsum_dolor_sit_amet": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore."
   }
  }
 },
 "js.gate.a_plan_opens_this_report": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "A plan opens this report."
   }
  }
 },
 "js.gate.a_free_account_opens_this": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "A free account opens this report."
   }
  }
 },
 "js.gate.see_plans": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "See plans"
   }
  }
 },
 "js.gate.this_report_is_not_available": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "This report is not available on this build."
   }
  }
 },
 "js.home.firm_aum": {
  "note": "home.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Firm AUM "
   }
  }
 },
 "js.home.log_in_to_see_all": {
  "note": "home.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Log in to see all "
   }
  }
 },
 "js.home.more_funds_are_on_a": {
  "note": "home.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "More funds are on a paid plan"
   }
  }
 },
 "js.plans.current_plan": {
  "note": "plans.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Current plan"
   }
  }
 },
 "js.plans.switch_plan": {
  "note": "plans.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Switch plan"
   }
  }
 },
 "js.scoring.a_paid_plan_is_required": {
  "note": "scoring.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "A paid plan is required."
   }
  }
 },
 "js.scoring.say_what_is_wrong": {
  "note": "scoring.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Say what is wrong."
   }
  }
 },
 "js.scoring.the_source_has_to_be": {
  "note": "scoring.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "The source has to be an http or https link."
   }
  }
 },
 "js.scoring.that_fund_is_not_on": {
  "note": "scoring.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "That fund is not on the list."
   }
  }
 },
 "js.scoring.could_not_send_that_a": {
  "note": "scoring.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Could not send that. A paid plan is required."
   }
  }
 },
 "js.settings.enter_a_valid_website": {
  "note": "settings.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Enter a valid website."
   }
  }
 },
 "js.settings.type_delete_or": {
  "note": "settings.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Type DELETE or "
   }
  }
 },
 "js.settings.type_delete": {
  "note": "settings.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Type DELETE"
   }
  }
 },
 "js.settings.not_set": {
  "note": "settings.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Not set"
   }
  }
 },
 "js.settings.set_password": {
  "note": "settings.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Set password"
   }
  }
 },
 "js.settings.your_paid_plan_is_active": {
  "note": "settings.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Your paid plan is active."
   }
  }
 },
 "js.settings.charge_failed_on": {
  "note": "settings.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Charge failed on"
   }
  }
 },
 "js.settings.card_on_file": {
  "note": "settings.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Card on file"
   }
  }
 },
 "js.settings.switch_plan": {
  "note": "settings.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Switch plan →"
   }
  }
 },
 "js.settings.enter_your_name": {
  "note": "settings.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Enter your name."
   }
  }
 },
 "js.settings.could_not_save_that_profile": {
  "note": "settings.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Could not save that profile."
   }
  }
 },
 "js.settings.enter_a_valid_email": {
  "note": "settings.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Enter a valid email."
   }
  }
 },
 "js.settings.that_password_does_not_match": {
  "note": "settings.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "That password does not match."
   }
  }
 },
 "js.settings.could_not_change_that_email": {
  "note": "settings.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Could not change that email."
   }
  }
 },
 "js.settings.confirmation_link_sent_the_change": {
  "note": "settings.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Confirmation link sent. The change applies once you click it."
   }
  }
 },
 "js.settings.could_not_update_that_password": {
  "note": "settings.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Could not update that password."
   }
  }
 },
 "js.settings.password_updated": {
  "note": "settings.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Password updated"
   }
  }
 },
 "report.these_can_t_be_checked": {
  "note": "Fund report text identical for every fund (ask.note).",
  "variants": {
   "default": {
    "when": "always",
    "text": "These can't be checked from public records. Bring them to your partner meeting."
   }
  }
 },
 "report.in_your_last_3_down": {
  "note": "Fund report text identical for every fund (ask.questions[0].q).",
  "variants": {
   "default": {
    "when": "always",
    "text": "In your last 3 down or flat rounds, did you lead, follow or walk?"
   }
  }
 },
 "report.down_rounds_bridges_pay_to": {
  "note": "Fund report text identical for every fund (ask.questions[0].title).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Down rounds, bridges, pay-to-play"
   }
  }
 },
 "report.what_share_of_your_seed": {
  "note": "Fund report text identical for every fund (ask.questions[1].q).",
  "variants": {
   "default": {
    "when": "always",
    "text": "What share of your seed/A companies did you reinvest in at the next round, including the strugglers?"
   }
  }
 },
 "report.follow_on_and_pro_rata": {
  "note": "Fund report text identical for every fund (ask.questions[1].title).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Follow-on and pro rata"
   }
  }
 },
 "report.when_did_you_last_back": {
  "note": "Fund report text identical for every fund (ask.questions[2].q).",
  "variants": {
   "default": {
    "when": "always",
    "text": "When did you last back replacing a founder-CEO, and how did it happen?"
   }
  }
 },
 "report.replacing_founder_ceos": {
  "note": "Fund report text identical for every fund (ask.questions[2].title).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Replacing founder-CEOs"
   }
  }
 },
 "report.will_you_take_a_seat": {
  "note": "Fund report text identical for every fund (ask.questions[3].q).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Will you take a seat at my stage? Which consent rights do you require?"
   }
  }
 },
 "report.board_seat_consent_rights": {
  "note": "Fund report text identical for every fund (ask.questions[3].title).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Board seat & consent rights"
   }
  }
 },
 "report.does_any_partner_sit_on": {
  "note": "Fund report text identical for every fund (ask.questions[4].q).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Does any partner sit on the board of a company that competes with me?"
   }
  }
 },
 "report.competitor_overlap": {
  "note": "Fund report text identical for every fund (ask.questions[4].title).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Competitor overlap"
   }
  }
 },
 "report.which_fund_is_this_check": {
  "note": "Fund report text identical for every fund (ask.questions[5].q).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Which fund is this check from, and how much is reserved for follow-ons?"
   }
  }
 },
 "report.reserves_for_this_check": {
  "note": "Fund report text identical for every fund (ask.questions[5].title).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Reserves for this check"
   }
  }
 },
 "report.are_there_sovereign_or_foreign": {
  "note": "Fund report text identical for every fund (ask.questions[6].q).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Are there sovereign or foreign-state LPs in this fund?"
   }
  }
 },
 "report.foreign_or_sovereign_lps": {
  "note": "Fund report text identical for every fund (ask.questions[6].title).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Foreign or sovereign LPs"
   }
  }
 },
 "report.give_me_2_founders_whose": {
  "note": "Fund report text identical for every fund (ask.questions[7].q).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Give me 2 founders whose companies failed with you on the board."
   }
  }
 },
 "report.references_from_failures": {
  "note": "Fund report text identical for every fund (ask.questions[7].title).",
  "variants": {
   "default": {
    "when": "always",
    "text": "References from failures"
   }
  }
 },
 "report.not_public_ask_the_fund": {
  "note": "Fund report text identical for every fund (ask.title).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Not public: ask the fund"
   }
  }
 },
 "report.bonus_3": {
  "note": "Fund report text identical for every fund (evidence.bonus.kicker).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Bonus · +3"
   }
  }
 },
 "report.1a_lawsuits": {
  "note": "Fund report text identical for every fund (evidence.cov.rows[0][0]).",
  "variants": {
   "default": {
    "when": "always",
    "text": "1a Lawsuits"
   }
  }
 },
 "report.1b_founder_removals": {
  "note": "Fund report text identical for every fund (evidence.cov.rows[1][0]).",
  "variants": {
   "default": {
    "when": "always",
    "text": "1b Founder removals"
   }
  }
 },
 "report.1c_down_rounds": {
  "note": "Fund report text identical for every fund (evidence.cov.rows[2][0]).",
  "variants": {
   "default": {
    "when": "always",
    "text": "1c Down rounds"
   }
  }
 },
 "report.1d_blocking": {
  "note": "Fund report text identical for every fund (evidence.cov.rows[3][0]).",
  "variants": {
   "default": {
    "when": "always",
    "text": "1d Blocking"
   }
  }
 },
 "report.how_much_we_could_check": {
  "note": "Fund report text identical for every fund (evidence.cov.title).",
  "variants": {
   "default": {
    "when": "always",
    "text": "How much we could check"
   }
  }
 },
 "report.how_sure_are_we": {
  "note": "Fund report text identical for every fund (evidence.range.kicker).",
  "variants": {
   "default": {
    "when": "always",
    "text": "How sure are we"
   }
  }
 },
 "report.1a_lawsuits_with_own_founders": {
  "note": "Fund report text identical for every fund (evidence.range.rows[0][0]).",
  "variants": {
   "default": {
    "when": "always",
    "text": "1a Lawsuits with own founders"
   }
  }
 },
 "report.1b_pushing_out_founder_ceos": {
  "note": "Fund report text identical for every fund (evidence.range.rows[1][0]).",
  "variants": {
   "default": {
    "when": "always",
    "text": "1b Pushing out founder-CEOs"
   }
  }
 },
 "report.1c_down_round_pay_to": {
  "note": "Fund report text identical for every fund (evidence.range.rows[2][0]).",
  "variants": {
   "default": {
    "when": "always",
    "text": "1c Down-round / pay-to-play"
   }
  }
 },
 "report.1d_blocking_deals_rounds": {
  "note": "Fund report text identical for every fund (evidence.range.rows[3][0]).",
  "variants": {
   "default": {
    "when": "always",
    "text": "1d Blocking deals / rounds"
   }
  }
 },
 "report.2a_money": {
  "note": "Fund report text identical for every fund (evidence.range.rows[4][0]).",
  "variants": {
   "default": {
    "when": "always",
    "text": "2a Money"
   }
  }
 },
 "report.insight_partners": {
  "note": "Fund report text identical for every fund (evidence.rank.rows[10][0]).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Insight Partners"
   }
  }
 },
 "report.bessemer_venture_partners": {
  "note": "Fund report text identical for every fund (evidence.rank.rows[1][0]).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Bessemer Venture Partners"
   }
  }
 },
 "report.battery_ventures": {
  "note": "Fund report text identical for every fund (evidence.rank.rows[2][0]).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Battery Ventures"
   }
  }
 },
 "report.bain_capital_ventures": {
  "note": "Fund report text identical for every fund (evidence.rank.rows[4][0]).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Bain Capital Ventures"
   }
  }
 },
 "report.khosla_ventures": {
  "note": "Fund report text identical for every fund (evidence.rank.rows[5][0]).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Khosla Ventures"
   }
  }
 },
 "report.lux_capital": {
  "note": "Fund report text identical for every fund (evidence.rank.rows[6][0]).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Lux Capital"
   }
  }
 },
 "report.sequoia_capital": {
  "note": "Fund report text identical for every fund (evidence.rank.rows[7][0]).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Sequoia Capital"
   }
  }
 },
 "report.general_catalyst": {
  "note": "Fund report text identical for every fund (evidence.rank.rows[8][0]).",
  "variants": {
   "default": {
    "when": "always",
    "text": "General Catalyst"
   }
  }
 },
 "report.lightspeed_venture_partners": {
  "note": "Fund report text identical for every fund (evidence.rank.rows[9][0]).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Lightspeed Venture Partners"
   }
  }
 },
 "report.how_score_works": {
  "note": "Fund report text identical for every fund (evidence.rules.title).",
  "variants": {
   "default": {
    "when": "always",
    "text": "How {{s:brand.name}} score works"
   }
  }
 },
 "report.score_60_of_60": {
  "note": "Fund report text identical for every fund (evidence.s1.kicker).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Score · 60 of 60"
   }
  }
 },
 "report.first_hand_accounts": {
  "note": "Fund report text identical for every fund (evidence.s3.rows[0][0]).",
  "variants": {
   "default": {
    "when": "always",
    "text": "First-hand accounts"
   }
  }
 },
 "report.people_screened": {
  "note": "Fund report text identical for every fund (evidence.sanc.rows[1][0]).",
  "variants": {
   "default": {
    "when": "always",
    "text": "People screened"
   }
  }
 },
 "report.what_we_could_check": {
  "note": "Fund report text identical for every fund (floats[1].small).",
  "variants": {
   "default": {
    "when": "always",
    "text": "what we could check"
   }
  }
 },
 "report.partner_board_seats": {
  "note": "Fund report text identical for every fund (fundTab.boards.title).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Partner board seats"
   }
  }
 },
 "report.fund_facts": {
  "note": "Fund report text identical for every fund (fundTab.factsTitle).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Fund facts"
   }
  }
 },
 "report.not_public": {
  "note": "Fund report text identical for every fund (fundTab.facts[5].v).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Not public"
   }
  }
 },
 "report.media_reach": {
  "note": "Fund report text identical for every fund (fundTab.media.title).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Media reach"
   }
  }
 },
 "report.partner_moves": {
  "note": "Fund report text identical for every fund (fundTab.moves.title).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Partner moves"
   }
  }
 },
 "report.not_counted": {
  "note": "Fund report text identical for every fund (notCountedTitle).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Not counted"
   }
  }
 },
 "report.fund_vs_founders_60_of": {
  "note": "Fund report text identical for every fund (parts[0].aria).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Fund vs. founders: 60 of 60"
   }
  }
 },
 "report.lost_case_or_fraud_finding": {
  "note": "Fund report text identical for every fund (parts[0].inputs[4].name).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Lost case or fraud finding (−3 each)"
   }
  }
 },
 "report.help_after_the_check": {
  "note": "Fund report text identical for every fund (parts[1].inputs[2].name).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Help after the check"
   }
  }
 },
 "report.negative_share": {
  "note": "Fund report text identical for every fund (parts[2].inputs[1].name).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Negative share"
   }
  }
 },
 "report.age_default": {
  "note": "Fund report text identical for every fund (parts[2].inputs[2].name).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Age default"
   }
  }
 },
 "report.founder_exp": {
  "note": "Fund report text identical for every fund (parts[2].legend).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Founder exp."
   }
  }
 },
 "report.track_record_bonus_3": {
  "note": "Fund report text identical for every fund (parts[4].aria).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Track record bonus +3"
   }
  }
 },
 "report.years_investing": {
  "note": "Fund report text identical for every fund (parts[4].inputs[0].name).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Years investing"
   }
  }
 },
 "report.max_3": {
  "note": "Fund report text identical for every fund (parts[4].maxLabel).",
  "variants": {
   "default": {
    "when": "always",
    "text": "max +3"
   }
  }
 },
 "report.1_for_every_5_years": {
  "note": "Fund report text identical for every fund (parts[4].rule).",
  "variants": {
   "default": {
    "when": "always",
    "text": "+1 for every 5 years of investing with no significant pattern of harm, up to +3."
   }
  }
 },
 "report.range_0_to_50": {
  "note": "Fund report text identical for every fund (parts[5].maxLabel).",
  "variants": {
   "default": {
    "when": "always",
    "text": "range 0 to −50"
   }
  }
 },
 "report.portfolio_litigation_rate": {
  "note": "Fund report text identical for every fund (portfolio.litigation.title).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Portfolio litigation rate"
   }
  }
 },
 "report.portfolio_size": {
  "note": "Fund report text identical for every fund (portfolio.size.title).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Portfolio size"
   }
  }
 },
 "report.public_record": {
  "note": "Fund report text identical for every fund (public.title).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Public record"
   }
  }
 },
 "report.should_i_take_this_money": {
  "note": "Fund report text identical for every fund (question).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Should I take this money?"
   }
  }
 },
 "report.regulatory_records": {
  "note": "Fund report text identical for every fund (regulatory.recordsTitle).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Regulatory records"
   }
  }
 },
 "report.details": {
  "note": "Fund report text identical for every fund (regulatory.sanctions.link).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Details →"
   }
  }
 },
 "report.regulatory_records_sanctions": {
  "note": "Fund report text identical for every fund (regulatory.title).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Regulatory records & sanctions"
   }
  }
 },
 "js.account.watchlist_full_100_100": {
  "note": "account.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Watchlist full (100/100)"
   }
  }
 },
 "js.account.saved_funds_the_bookmark_removes": {
  "note": "account.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Saved funds. The bookmark removes one."
   }
  }
 },
 "js.account.nothing_saved_yet": {
  "note": "account.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Nothing saved yet."
   }
  }
 },
 "js.account.open_a_fund_and_tap": {
  "note": "account.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Open a fund and tap the bookmark."
   }
  }
 },
 "js.account.no_fund_found": {
  "note": "account.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "No fund found"
   }
  }
 },
 "js.account.use_a_linkedin_profile_url": {
  "note": "account.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Use a LinkedIn profile URL like linkedin.com/in/your-name."
   }
  }
 },
 "js.account.submitted": {
  "note": "account.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Submitted."
   }
  }
 },
 "js.account.it_stays_hidden_until_we": {
  "note": "account.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "It stays hidden until we review it. Nothing here is shown on the fund page before that."
   }
  }
 },
 "js.account.add_the_supabase_url_and": {
  "note": "account.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Add the Supabase URL and publishable key, then rebuild."
   }
  }
 },
 "js.admin.approve": {
  "note": "admin.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Approve"
   }
  }
 },
 "js.admin.reject": {
  "note": "admin.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Reject"
   }
  }
 },
 "js.admin.nothing_waiting": {
  "note": "admin.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Nothing waiting."
   }
  }
 },
 "js.admin.new_founder_reviews_show_up": {
  "note": "admin.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "New founder reviews show up here."
   }
  }
 },
 "js.admin.new_corrections_show_up_here": {
  "note": "admin.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "New corrections show up here."
   }
  }
 },
 "js.auth.login_log_in": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "login/\">Log in"
   }
  }
 },
 "js.auth.account_watchlist_get_alerts": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "account/#watchlist\">Get alerts"
   }
  }
 },
 "js.auth.log_out": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Log out"
   }
  }
 },
 "js.auth.founder": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Founder"
   }
  }
 },
 "js.auth.unlimited_reports_and_alerts_price": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Unlimited reports and alerts. Price not set yet."
   }
  }
 },
 "js.auth.team_accelerator": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Team / accelerator"
   }
  }
 },
 "js.auth.shared_seats_seats_and_price": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Shared seats. Seats and price not set yet."
   }
  }
 },
 "js.auth.continue_with_google": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Continue with Google"
   }
  }
 },
 "js.auth.forgot_password": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Forgot password?"
   }
  }
 },
 "js.auth.confirm_password": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Confirm password"
   }
  }
 },
 "js.auth.maybe_later": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Maybe later"
   }
  }
 },
 "js.auth.resend_email": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Resend email"
   }
  }
 },
 "js.auth.have_an_account": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Have an account?"
   }
  }
 },
 "js.auth.new_here": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "New here?"
   }
  }
 },
 "js.auth.back_to_log_in": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Back to log in"
   }
  }
 },
 "js.auth.those_passwords_don_t_match": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Those passwords don't match."
   }
  }
 },
 "js.auth.alerttog_data_alert": {
  "note": "auth.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "#alertTog, [data-alert]"
   }
  }
 },
 "js.fund_list.no_funds_match_these_filters": {
  "note": "fund_list.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "No funds match these filters."
   }
  }
 },
 "js.fund_list.try_widening_the_score_range": {
  "note": "fund_list.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Try widening the score range or clearing a filter."
   }
  }
 },
 "js.fund_list.remove": {
  "note": "fund_list.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Remove"
   }
  }
 },
 "js.fund_list.remove_from_watchlist": {
  "note": "fund_list.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Remove from watchlist"
   }
  }
 },
 "js.fund_list.active_legal": {
  "note": "fund_list.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Active legal"
   }
  }
 },
 "js.fund_list.aum": {
  "note": "fund_list.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "AUM"
   }
  }
 },
 "js.fund_list.last_update": {
  "note": "fund_list.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Last update"
   }
  }
 },
 "js.fund_list.no_filters_applied_showing_every": {
  "note": "fund_list.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "No filters applied · showing every fund we track"
   }
  }
 },
 "js.fund.open_real_risk": {
  "note": "fund.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Open · real risk"
   }
  }
 },
 "js.fund.costs_points": {
  "note": "fund.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Costs points"
   }
  }
 },
 "js.fund.no_public_link_for_this": {
  "note": "fund.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "No public link for this item. It comes from the scoring method."
   }
  }
 },
 "js.fund.questions_copied": {
  "note": "fund.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "questions copied"
   }
  }
 },
 "js.fund.stk_data_ev_sleg_data": {
  "note": "fund.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": ".stk [data-ev],.sleg [data-ev]"
   }
  }
 },
 "js.fund.board_seat": {
  "note": "fund.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "board seat"
   }
  }
 },
 "js.gate.lorem_ipsum_dolor": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Lorem ipsum dolor"
   }
  }
 },
 "js.gate.lorem_source": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Lorem source"
   }
  }
 },
 "js.gate.lorem": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Lorem"
   }
  }
 },
 "js.gate.lorem_ipsum_dolor_sit_amet_2": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Lorem ipsum dolor sit amet"
   }
  }
 },
 "js.gate.ipsum": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Ipsum"
   }
  }
 },
 "js.gate.dolor": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Dolor"
   }
  }
 },
 "js.gate.of_00_funds": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "of 00 funds"
   }
  }
 },
 "js.gate.out_of_100": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "out of 100"
   }
  }
 },
 "js.gate.lorem_band": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Lorem band"
   }
  }
 },
 "js.gate.lorem_00_00": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "lorem 00–00"
   }
  }
 },
 "js.gate.overview": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Overview"
   }
  }
 },
 "js.gate.public": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Public"
   }
  }
 },
 "js.gate.portfolio": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Portfolio"
   }
  }
 },
 "js.gate.ask_the_fund": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Ask the fund"
   }
  }
 },
 "js.gate.summary": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Summary"
   }
  }
 },
 "js.gate.takeaways": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Takeaways"
   }
  }
 },
 "js.gate.top_legal_matters": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Top legal matters"
   }
  }
 },
 "js.gate.of_0": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "of 0"
   }
  }
 },
 "js.gate.lorem_ipsum": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Lorem ipsum"
   }
  }
 },
 "js.gate.lorem_ipsum_dolor_sit_amet_3": {
  "note": "gate.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Lorem ipsum dolor sit amet."
   }
  }
 },
 "js.home.under_100m": {
  "note": "home.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Under $100M"
   }
  }
 },
 "js.home.clear_all": {
  "note": "home.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Clear all"
   }
  }
 },
 "js.home.plans_see_plans": {
  "note": "home.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "plans/\">See plans"
   }
  }
 },
 "js.home.update": {
  "note": "home.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Update #"
   }
  }
 },
 "js.home.records_showing_the_newest": {
  "note": "home.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "records · showing the newest"
   }
  }
 },
 "js.notfound.search_is_not_available_on": {
  "note": "notfound.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Search is not available on this build."
   }
  }
 },
 "js.scoring.choose_a_fund": {
  "note": "scoring.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Choose a fund."
   }
  }
 },
 "js.scoring.we_review_every_request": {
  "note": "scoring.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "We review every request."
   }
  }
 },
 "js.settings.no_charge": {
  "note": "settings.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "No charge."
   }
  }
 },
 "js.settings.your_payment_didn_t_go": {
  "note": "settings.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Your payment didn't go through, so you're on the free plan now. Update your card to restore access."
   }
  }
 },
 "js.settings.could_not_delete_this_account": {
  "note": "settings.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Could not delete this account."
   }
  }
 },
 "js.settings.we_couldn_t_cancel_your": {
  "note": "settings.js text.",
  "variants": {
   "default": {
    "when": "always",
    "text": "We couldn't cancel your plan, contact malytskyyo@gmail.com"
   }
  }
 },
 "build.show_more": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Show more"
   }
  }
 },
 "build.evidence": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Evidence →"
   }
  }
 },
 "build.last_checked": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Last checked"
   }
  }
 },
 "build.click_any_card_to_see": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Click any card to see the evidence"
   }
  }
 },
 "build.no_takeaways_yet": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "No takeaways yet."
   }
  }
 },
 "build.see_all": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "See all"
   }
  }
 },
 "build.no_legal_matters_on_file": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "No legal matters on file."
   }
  }
 },
 "build.no_summary_yet": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "No summary yet."
   }
  }
 },
 "build.rule": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Rule"
   }
  }
 },
 "build.input": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Input"
   }
  }
 },
 "build.why": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Why"
   }
  }
 },
 "build.funds": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Funds"
   }
  }
 },
 "build.showing": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Showing"
   }
  }
 },
 "build.no_fund_facts_yet": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "No fund facts yet."
   }
  }
 },
 "build.no_board_seats_on_file": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "No board seats on file."
   }
  }
 },
 "build.no_partner_moves_on_file": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "No partner moves on file."
   }
  }
 },
 "build.no_media_reach_on_file": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "No media reach on file."
   }
  }
 },
 "build.portfolio_companies": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Portfolio companies"
   }
  }
 },
 "build.all": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "All"
   }
  }
 },
 "build.sources": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "sources ·"
   }
  }
 },
 "build.filter_by_sentiment": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Filter by sentiment"
   }
  }
 },
 "build.copy_questions": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Copy questions"
   }
  }
 },
 "build.download_pdf": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Download PDF"
   }
  }
 },
 "build.coverage_39": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "· coverage 39%"
   }
  }
 },
 "build.how_scoring_works": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "How scoring works"
   }
  }
 },
 "build.save_to_watchlist": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Save to watchlist"
   }
  }
 },
 "build.updated": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Updated"
   }
  }
 },
 "build.details": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Details"
   }
  }
 },
 "build.loading_the_report": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Loading the report…"
   }
  }
 },
 "build.watchlist": {
  "note": "build.py generated markup.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Watchlist ·"
   }
  }
 },
 "report.regulatory.see_matter": {
  "note": "Regulatory record detail when the matter is on the Legal tab.",
  "variants": {
   "default": {
    "when": "always",
    "text": "See the matter on this tab."
   }
  }
 },
 "report.legal.empty": {
  "note": "Legal tab empty state.",
  "variants": {
   "default": {
    "when": "always",
    "text": "No data yet. We found no court cases, regulator actions or sanctions for this fund."
   }
  }
 },
 "report.founders.empty": {
  "note": "Founder reviews empty state.",
  "variants": {
   "default": {
    "when": "always",
    "text": "No data yet. We found no founder accounts for this fund."
   }
  }
 },
 "report.public.empty_all": {
  "note": "Public tab empty state.",
  "variants": {
   "default": {
    "when": "always",
    "text": "No data yet. We found no press for this fund."
   }
  }
 },
 "report.tab.fund": {
  "note": "Fund page tab label.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Fund &amp; people"
   }
  }
 },
 "report.public.open_source": {
  "note": "Public item link title, before the domain.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Open source on"
   }
  }
 },
 "report.public.new_tab": {
  "note": "Public item link title suffix.",
  "variants": {
   "default": {
    "when": "always",
    "text": "(new tab)"
   }
  }
 },
 "js.auth.agree_prefix": {
  "note": "Signup fine print, before the Terms link.",
  "variants": {
   "default": {
    "when": "always",
    "text": "By creating an account you agree to the"
   }
  }
 },
 "js.fund.of": {
  "note": "Public list count connector.",
  "variants": {
   "default": {
    "when": "always",
    "text": "of"
   }
  }
 },
 "page.404.that_address_is_not_a": {
  "note": "404 page text (contains brand token).",
  "variants": {
   "default": {
    "when": "always",
    "text": "That address is not a page on {{s:brand.name}}. Search for a fund, or go back to the list."
   }
  }
 },
 "legal.privacy.regretamine_com_currently_served_at": {
  "note": "privacy page text (contains brand token).",
  "variants": {
   "default": {
    "when": "always",
    "text": "{{s:brand.name}} (regretamine.com, currently served at mindgame77.github.io/regrettamine) helps founders check venture capital funds before taking their money. It is operated by"
   }
  }
 },
 "legal.privacy.is_not_for_anyone_under": {
  "note": "privacy page text (contains brand token).",
  "variants": {
   "default": {
    "when": "always",
    "text": "{{s:brand.name}} is not for anyone under 18. We don't knowingly collect data from children. If you believe a child has an account, contact us and we'll delete it."
   }
  }
 },
 "legal.terms.the_rules_for_using_in": {
  "note": "terms page text (contains brand token).",
  "variants": {
   "default": {
    "when": "always",
    "text": "The rules for using {{s:brand.name}}, in plain English."
   }
  }
 },
 "legal.terms.who_operates_we_us_by": {
  "note": "terms page text (contains brand token).",
  "variants": {
   "default": {
    "when": "always",
    "text": ", who operates {{s:brand.name}} (\"we\", \"us\"). By using the site or creating an account, you accept them and our"
   }
  }
 },
 "legal.terms.nothing_on_is_investment_legal": {
  "note": "terms page text (contains brand token).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Nothing on {{s:brand.name}} is investment, legal or financial advice. Do your own diligence before you take or turn down money."
   }
  }
 },
 "legal.terms.you_keep_ownership_of_your": {
  "note": "terms page text (contains brand token).",
  "variants": {
   "default": {
    "when": "always",
    "text": "You keep ownership of your review. You give us a worldwide, non-exclusive, royalty-free license to host, display, format, translate and use it in aggregated scores for as long as it's on {{s:brand.name}}, and to keep using anonymised, aggregated results after it's removed. You confirm you have the right to grant this."
   }
  }
 },
 "legal.terms.we_may_suspend_or_close": {
  "note": "terms page text (contains brand token).",
  "variants": {
   "default": {
    "when": "always",
    "text": "We may suspend or close accounts that break these terms or put the service or others at risk, and we'll tell you why when we can. You can stop using {{s:brand.name}} at any time. Sections on reviews licensing, disclaimers and liability survive termination."
   }
  }
 },
 "legal.terms.is_provided_as_is_and": {
  "note": "terms page text (contains brand token).",
  "variants": {
   "default": {
    "when": "always",
    "text": "{{s:brand.name}} is provided \"as is\" and \"as available\". To the extent the law allows, we disclaim all warranties, including accuracy, completeness, fitness for a particular purpose and uninterrupted availability."
   }
  }
 },
 "js.account.pitched": {
  "note": "account.js label.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Pitched"
   }
  }
 },
 "js.auth.you": {
  "note": "auth.js label.",
  "variants": {
   "default": {
    "when": "always",
    "text": "You"
   }
  }
 },
 "js.auth.settings": {
  "note": "auth.js label.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Settings"
   }
  }
 },
 "js.auth.saved": {
  "note": "auth.js label.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Saved"
   }
  }
 },
 "js.fund.positive": {
  "note": "fund.js label.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Positive"
   }
  }
 },
 "js.fund.neutral": {
  "note": "fund.js label.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Neutral"
   }
  }
 },
 "js.fund.negative": {
  "note": "fund.js label.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Negative"
   }
  }
 },
 "js.gate.one": {
  "note": "gate.js label.",
  "variants": {
   "default": {
    "when": "always",
    "text": "One"
   }
  }
 },
 "js.gate.two": {
  "note": "gate.js label.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Two"
   }
  }
 },
 "js.gate.three": {
  "note": "gate.js label.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Three"
   }
  }
 },
 "js.gate.four": {
  "note": "gate.js label.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Four"
   }
  }
 },
 "js.gate.five": {
  "note": "gate.js label.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Five"
   }
  }
 },
 "js.gate.six": {
  "note": "gate.js label.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Six"
   }
  }
 },
 "js.plans.paid": {
  "note": "plans.js label.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Paid"
   }
  }
 },
 "js.settings.failed": {
  "note": "settings.js label.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Failed"
   }
  }
 },
 "js.settings.receipt": {
  "note": "settings.js label.",
  "variants": {
   "default": {
    "when": "always",
    "text": "Receipt"
   }
  }
 },
 "report.since": {
  "note": "Fund header chip prefix: \"Since 2009\".",
  "variants": {
   "default": {
    "when": "always",
    "text": "Since"
   }
  }
 },
 "report.ranking": {
  "note": "Fund report text identical for every fund (evidence.rank.kicker).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Ranking"
   }
  }
 },
 "report.methodology": {
  "note": "Fund report text identical for every fund (evidence.rules.kicker).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Methodology"
   }
  }
 },
 "report.conflicts": {
  "note": "Fund report text identical for every fund (evidence.rules.rows[3][0]).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Conflicts"
   }
  }
 },
 "report.up_to_3": {
  "note": "Fund report text identical for every fund (evidence.rules.rows[4][1]).",
  "variants": {
   "default": {
    "when": "always",
    "text": "up to +3"
   }
  }
 },
 "report.staff": {
  "note": "Fund report text identical for every fund (fundTab.facts[2].k).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Staff"
   }
  }
 },
 "report.performance": {
  "note": "Fund report text identical for every fund (fundTab.facts[5].k).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Performance"
   }
  }
 },
 "report.of_60": {
  "note": "Fund report text identical for every fund (parts[0].maxLabel).",
  "variants": {
   "default": {
    "when": "always",
    "text": "of 60"
   }
  }
 },
 "report.money": {
  "note": "Fund report text identical for every fund (parts[1].inputs[0].name).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Money"
   }
  }
 },
 "report.support": {
  "note": "Fund report text identical for every fund (parts[1].legend).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Support"
   }
  }
 },
 "report.of_17_5": {
  "note": "Fund report text identical for every fund (parts[1].maxLabel).",
  "variants": {
   "default": {
    "when": "always",
    "text": "of 17.5"
   }
  }
 },
 "report.of_5": {
  "note": "Fund report text identical for every fund (parts[3].maxLabel).",
  "variants": {
   "default": {
    "when": "always",
    "text": "of 5"
   }
  }
 },
 "report.bonus": {
  "note": "Fund report text identical for every fund (parts[4].legend).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Bonus"
   }
  }
 },
 "report.regulatory": {
  "note": "Fund report text identical for every fund (parts[5].legend).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Regulatory"
   }
  }
 },
 "report.health": {
  "note": "Fund report text identical for every fund (portfolio.healthTitle).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Health"
   }
  }
 },
 "report.sanctions": {
  "note": "Fund report text identical for every fund (regulatory.sanctionsTitle).",
  "variants": {
   "default": {
    "when": "always",
    "text": "Sanctions"
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
