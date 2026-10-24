// www.regretamin.com -> https://regretamin.com/ (path and query kept).
export async function onRequest(ctx) {
  const u = new URL(ctx.request.url);
  if (u.hostname === 'www.regretamin.com') {
    u.hostname = 'regretamin.com'; u.protocol = 'https:'; u.port = '';
    return Response.redirect(u.toString(), 301);
  }
  return ctx.next();
}
