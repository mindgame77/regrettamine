// Templates are internal: never serve them directly.
export const onRequest = () => new Response('Not found', { status: 404 });
