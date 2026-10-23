"""Privacy Policy (/privacy/) and Terms of Service (/terms/) for the launch site. Plain HTML, styled by .lg in style.css.
Plan names and prices are read from copy.json so the Terms always match the pricing popup."""
import json, os
P = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'copy.json')))['plans']
CO, EMAIL, DATE = 'Know Your Group INC.', 'malytskyyo@gmail.com', 'October 23, 2026'
MAIL = f'<a href="mailto:{EMAIL}">{EMAIL}</a>'

def _doc(kicker, title, lead, sections, other):
    toc = ''.join(f'<a href="#{i}">{h}</a>' for i, h, _ in sections)
    body = ''.join(f'<section id="{i}"><h2>{h}</h2>{b}</section>' for i, h, b in sections)
    return (f'<main class="hp lg"><span class="ey">{kicker}</span><h1>{title}</h1><p class="lead">{lead}</p>'
            f'<p class="eff">Effective {DATE} · See also {other}</p><nav class="toc">{toc}</nav>{body}</main>')

def privacy():
    S = [
     ('who', 'Who we are', f'<p>Regretamin (regretamin.com) shows founders public-record information about venture capital firms. It is operated by <b>{CO}</b>, a Delaware corporation ("we", "us"), which is responsible for your personal data. Questions or requests: {MAIL}.</p>'),
     ('collect', 'What we collect', '<ul>'
      '<li><b>Account.</b> Your email address, or, if you sign in with Google, the name, email address and profile picture Google shares with us. Used to create and secure your account.</li>'
      '<li><b>Saved firms.</b> The list of firms you save and the firms you have unlocked, so you can find them again under My checks.</li>'
      '<li><b>Credits.</b> Your credit balance and a record of each credit used or added (which firm, when). Used to run free credits and paid plans.</li>'
      '<li><b>Firm requests.</b> If you search for a firm we don\'t have yet, the name you typed and, if you give it, your email so we can tell you when the check is ready.</li>'
      '<li><b>Payment records.</b> Stripe handles payments; we never see or store card numbers. We keep your Stripe customer and subscription IDs, your plan and its renewal date.</li>'
      '<li><b>Abuse prevention.</b> When a free credit is used, we store a one-way hash of your IP address (not the address itself) to limit free credits per network.</li></ul>'),
     ('device', 'Free searches and your device', '<p>Without an account you get 2 free searches. To count them, your browser stores a random ID in its local storage (<code>regretamin.anon</code>), and our database keeps the count against that ID. It does not contain your name or email. If you sign in, those searches are moved to your account. Signing in also stores a session token in your browser, and starting a purchase stores a short-lived note of the plan you picked. Clearing your browser storage removes all of these.</p>'
      '<p>We don\'t use advertising cookies, ad trackers or analytics tools.</p>'),
     ('use', 'How we use it', '<ul><li>To run the service: sign-in, credits, unlocking firms, your saved firms and purchases.</li><li>To send sign-in links and, if you asked, an email when a firm you requested is ready.</li><li>To keep the service secure and prevent abuse of free credits.</li><li>To answer your messages and correction requests.</li></ul>'
      '<p>We <b>don\'t sell</b> your personal data, don\'t share it for advertising, and don\'t show ads.</p>'),
     ('share', 'Services we use', '<ul>'
      '<li><b>Supabase</b>: our database and sign-in (accounts, credits, saved firms).</li>'
      '<li><b>Stripe</b>: payments, subscriptions and promo codes.</li>'
      '<li><b>Google</b>: only if you choose Google sign-in. Our pages also load fonts from Google Fonts, which receives your IP address.</li>'
      '<li><b>Resend</b>: sends the email telling you a firm you requested is ready. Sign-in link emails are sent by our sign-in provider, Supabase.</li>'
      '<li><b>GitHub Pages</b>: hosts the website. The page code also loads from the jsDelivr content network.</li>'
      '<li><b>Authorities</b>: only when the law requires it.</li></ul>'
      '<p>These providers process data on our behalf under their own terms. Most are in the United States, so your data may be processed outside your country.</p>'),
     ('funds', 'People named in firm pages', f'<p>Firm pages show information about firms and people at them taken from public records, such as court records, regulatory filings and press coverage. If you are named and think something is wrong, email {MAIL} with the page and a source and we will review it.</p>'),
     ('retention', 'How long we keep it', '<p>We keep account data, saved firms and credit records while your account exists. Payment records may be kept longer where tax or accounting law requires. Hosting providers keep their own logs for their own periods.</p>'),
     ('rights', 'Your rights', f'<p>You can ask us to access, correct, export or delete your data, or to stop using it, by emailing {MAIL}. We may need to confirm it\'s you. Depending on where you live (for example the EU, UK or California) you may have further rights, including complaining to your local data protection authority.</p>'),
     ('children', 'Children', '<p>Regretamin is not for anyone under 18, and we don\'t knowingly collect data from children. If you believe a child has an account, contact us and we\'ll delete it.</p>'),
     ('security', 'Security', '<p>Data is encrypted in transit and access to our database is restricted. No system is perfectly secure.</p>'),
     ('changes', 'Changes', '<p>If we change this policy, we\'ll update the date above. For significant changes we\'ll also tell people on the site.</p>'),
     ('contact', 'Contact', f'<p>{CO} · {MAIL}</p><p>This policy is governed by the laws of the State of Delaware.</p>'),
    ]
    return _doc('Legal', 'Privacy Policy', 'What we collect, why, and what you can do about it.', S, '<a href="../terms/">Terms of Service</a>')

def terms():
    s, m10, m30 = P['single'], P['m10'], P['m30']
    plan = lambda p: f'{p["name"]}: {p["price"]}/month for {p["checks"]} credits a month, or {p["yearly"]["price"]}/year'
    S = [
     ('agreement', 'Agreement', f'<p>These terms are an agreement between you and <b>{CO}</b>, a Delaware corporation, which operates Regretamin at regretamin.com ("we", "us"). By using the site you accept them and our <a href="../privacy/">Privacy Policy</a>. You must be at least 18.</p>'),
     ('info', 'What the site is, and is not', '<ul>'
      '<li>Regretamin shows <b>public-record information only</b>, such as court records, regulatory filings and press coverage, with links to sources where we have them.</li>'
      '<li>It is <b>not legal, investment or financial advice</b>. Do your own diligence before you take or turn down money.</li>'
      '<li>It gives <b>no verdicts</b>. We don\'t rate firms or people as good or bad, and a lawsuit, filing or article is not a finding of wrongdoing.</li>'
      '<li>Records can be incomplete, out of date or wrong. Anyone, including the firms and people named, can ask for a correction for free by emailing <a href="mailto:malytskyyo@gmail.com">malytskyyo@gmail.com</a>.</li></ul>'),
     ('credits', 'Credits', '<ul>'
      '<li><b>1 firm = 1 credit.</b> Using a credit unlocks one firm\'s full page. Reopening a firm you already unlocked is free.</li>'
      '<li>Without an account you get 2 free credits on your device. Creating a free account adds 4 more. We may change free amounts with notice on the site.</li>'
      f'<li>You can buy a single credit for {s["price"]}. Credits have no cash value and can\'t be transferred.</li></ul>'),
     ('subs', 'Subscriptions and promo codes', '<ul>'
      f'<li>Plans: {plan(m10)}; {plan(m30)}. Prices are shown before you pay.</li>'
      '<li>Payments, subscriptions and promo codes are handled by Stripe. A subscription renews automatically until you cancel.</li>'
      '<li>Plan credits refill each month and unused plan credits don\'t carry over. You can cancel from your Account page at any time; your plan stays active until the end of the paid period.</li>'
      '<li>Promo codes apply only as described when you enter them, can\'t be exchanged for cash, and may expire or be withdrawn.</li>'
      '<li>If you think you were charged in error, email us and we\'ll look at it. This doesn\'t limit any refund rights you have under law.</li></ul>'),
     ('use', 'Acceptable use', '<p>Don\'t scrape or bulk-download the site, use bots, get around credit limits (for example with many accounts or by resetting device storage), interfere with the service, access other people\'s accounts, or resell or republish our pages without permission.</p>'),
     ('accounts', 'Accounts and termination', '<p>Sign in with Google or an email link. You are responsible for activity on your account. You can stop using the site at any time and ask us to delete your account. We may suspend accounts that break these terms.</p>'),
     ('content', 'Our content', '<p>The site design and the way we compile and present information belong to us. You may share links and quote short excerpts with attribution. Underlying public records belong to their sources.</p>'),
     ('disclaimers', 'Disclaimers and liability', '<p>Regretamin is provided "as is" and "as available". To the extent the law allows, we disclaim all warranties, and we are not liable for indirect or consequential losses or for decisions you make based on the site. Our total liability for any claim is limited to the greater of USD 100 or what you paid us in the 12 months before the claim. Some places don\'t allow these limits, so they may not apply to you.</p>'),
     ('law', 'Governing law', '<p>These terms are governed by the laws of the State of Delaware, and disputes go to the courts of the State of Delaware, unless consumer law where you live says otherwise.</p>'),
     ('changes', 'Changes', '<p>We may update these terms. We\'ll change the date above; if you keep using the site after that, the new terms apply.</p>'),
     ('contact', 'Contact', f'<p>{CO} · {MAIL}</p>'),
    ]
    return _doc('Legal', 'Terms of Service', 'The rules for using Regretamin, in plain English.', S, '<a href="../privacy/">Privacy Policy</a>')
