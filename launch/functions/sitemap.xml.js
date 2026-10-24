import { sitemapIndex } from '../edge/firm.mjs';
export const onRequestGet = (ctx) => sitemapIndex({ env: ctx.env });
