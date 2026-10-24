import { sitemapPart } from '../../edge/firm.mjs';
export const onRequestGet = (ctx) => sitemapPart({ name: ctx.params.name, env: ctx.env });
