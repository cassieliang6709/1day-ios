import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker, { parseStory } from '../src/index.js';

test('optional title is backward compatible and malformed title is ignored', () => {
  for (const title of [undefined, null, 42, '', '  ']) {
    assert.deepEqual(parseStory(JSON.stringify({ title, prompts: [' a ', 'b', 'c'] }), 7), { prompts: ['a', 'b', 'c'] });
  }
  assert.deepEqual(parseStory('["a","b","c"]', 7), { prompts: ['a', 'b', 'c'] });
  assert.equal(parseStory('{"title":"title","prompts":["a"]}', 7), null);
});

test('title is trimmed and bounded without rewriting language', () => {
  assert.deepEqual(parseStory('```json\n{"title":" My 搬家日 ","prompts":["a","b","c"]}\n```', 7), { title: 'My 搬家日', prompts: ['a', 'b', 'c'] });
  assert.equal([...parseStory(JSON.stringify({title: '日'.repeat(100), prompts: ['a','b','c']}), 7).title].length, 80);
});

for (const language of ['zh', 'en']) {
  test(`mock roundtrip requests title and prompts in ${language}`, async (t) => {
    let sent;
    t.mock.method(globalThis, 'fetch', async (_url, options) => {
      sent = JSON.parse(options.body);
      return new Response(JSON.stringify({ choices: [{ message: { content: '{"title":" My day ","prompts":["a","b","c"]}' } }] }));
    });
    const result = await worker.fetch(new Request('https://example.test/api/suggest-prompts', {
      method: 'POST', body: JSON.stringify({intent: 'my own text', count: 3, language, device: crypto.randomUUID()})
    }), {DEEPSEEK_API_KEY: 'mock-only'});
    assert.equal(result.status, 200);
    assert.deepEqual(await result.json(), {title: 'My day', prompts: ['a','b','c']});
    assert.equal(sent.messages[1].content, 'my own text');
    assert.match(sent.messages[0].content, /"title"/);
    assert.match(sent.messages[0].content, language === 'zh' ? /Simplified Chinese/ : /English/);
  });
}
