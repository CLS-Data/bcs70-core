/* Two selectors, used everywhere. The assistant's half of the site has its
   own copy in chat/dom.js; they are two lines each, and importing across the
   two halves would couple them for no gain. */

export const $ = (sel, root = document) => root.querySelector(sel);
export const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
