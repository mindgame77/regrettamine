"""Create the 3 Regretamin products in the Stripe SANDBOX (Know Your Group INC). Refuses live keys.
Usage: STRIPE_SECRET_KEY=sk_test_... python3 scripts/stripe_sandbox_products.py
Prints the price ids to set as STRIPE_PRICE_SINGLE / _M10 / _M30. Idempotent via lookup_key."""
import os, sys, json, urllib.request, urllib.parse, base64
KEY = os.environ.get('STRIPE_SECRET_KEY', '')
if not KEY.startswith(('sk_test_', 'rk_test_')): sys.exit('Refusing: STRIPE_SECRET_KEY must be a sandbox/test key.')
def call(method, path, data=None):
    req = urllib.request.Request('https://api.stripe.com/v1/' + path, data=urllib.parse.urlencode(data or {}, doseq=True).encode() if data else None, method=method)
    req.add_header('Authorization', 'Basic ' + base64.b64encode((KEY + ':').encode()).decode())
    return json.load(urllib.request.urlopen(req))
P = [('single', 'Regretamin single check', 1000, None, 'One VC check.'), ('m10', 'Regretamin Starter (10 checks/mo)', 1900, 'month', '10 checks a month.'), ('m30', 'Regretamin Pro (30 checks/mo)', 4900, 'month', '30 checks a month.')]
acct = call('GET', 'account'); print('Account:', acct.get('settings', {}).get('dashboard', {}).get('display_name') or acct.get('business_profile', {}).get('name'))
for lk, name, cents, interval, desc in P:
    lookup = 'regretamin_' + lk
    ex = call('GET', 'prices?' + urllib.parse.urlencode({'lookup_keys[]': lookup}))['data']
    if ex: print(lk, ex[0]['id'], '(exists)'); continue
    prod = call('POST', 'products', {'name': name, 'description': desc, 'metadata[kind]': lk})
    d = {'product': prod['id'], 'unit_amount': cents, 'currency': 'usd', 'lookup_key': lookup, 'metadata[kind]': lk}
    if interval: d['recurring[interval]'] = interval
    print(lk, call('POST', 'prices', d)['id'])
