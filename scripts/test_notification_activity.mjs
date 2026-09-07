import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const swift = fs.readFileSync(new URL('../Sources/XFlow/Services/NotificationActivity.swift', import.meta.url), 'utf8');
const source = swift.split('static let source = #"""')[1].split('"""#')[0];
const events = [];
let tick, now = 0, rows = [];
const context = {
  window: {webkit: {messageHandlers: {xflowUnreadCount: {postMessage: event => events.push(event)}}}},
  location: {pathname: '/notifications'},
  document: {title: '(3) X', querySelectorAll: () => rows, addEventListener() {}},
  setInterval: fn => { tick = fn; }, Date: {now: () => now}
};
function row(title, body = '') {
  return {innerText: `${title}\n${body}`, querySelector: selector => selector.includes('tweetText') && body ? {innerText: body} : null,
    cloneNode: () => ({innerText: title, querySelectorAll: () => []})};
}
rows = [row('Jane Doe liked your post', 'Hello, Swift!')];
vm.runInNewContext(source, context);
assert.equal(events.length, 1);
assert.equal(events[0].baseline, true);
tick();
assert.equal(events.length, 1, 'Startup must not replay existing activity');
context.document.title = '(4) X'; tick();
assert.equal(events.length, 1, 'Do not attach the old row to a new count');
rows.unshift(row('Chris followed you')); tick();
assert.equal(events.at(-1).activity.title, 'Chris followed you');
tick(); assert.equal(events.length, 2, 'Repeated polling must not duplicate alerts');
context.document.title = 'X'; tick();
assert.equal(events.at(-1).count, 0, 'Reading notifications must reset native count');
context.document.title = '(1) X'; tick();
rows.unshift(row('Ada liked your post', 'Case Preserved 👋')); tick();
assert.equal(events.at(-1).activity.body, 'Case Preserved 👋');
context.document.title = '(2) X'; tick(); now += 8000; tick();
assert.equal(events.at(-1).activity, null, 'Missing details use an honest fallback');
rows.unshift(row('Grace reposted your post', 'A preview before the badge updates')); tick();
context.document.title = '(3) X'; tick();
assert.equal(events.at(-1).activity.title, 'Grace reposted your post', 'Rows may arrive before the badge');
rows.unshift({innerText: 'Alex liked your post', querySelector: () => null,
  cloneNode: () => ({querySelectorAll: () => [], childNodes: [
    {nodeType: 3, nodeValue: 'Alex'}, {nodeType: 3, nodeValue: 'liked your post'}
  ]})});
context.document.title = '(4) X'; tick();
assert.equal(events.at(-1).activity.title, 'Alex liked your post', 'Detached spans retain word boundaries');
context.location.pathname = '/home'; tick();
context.location.pathname = '/notifications'; tick();
assert.equal(events.at(-1).baseline, true, 'SPA route re-entry establishes a fresh baseline');
console.log('Notification extraction lifecycle checks passed.');
