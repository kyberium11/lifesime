import test from 'node:test';
import assert from 'node:assert/strict';
import { parseDecision, parseDialogue, parseAdvice } from '../bridge/decision.mjs';

test('accepts JSON and removes unsupported fields', () => {
  const out = parseDecision('{"action":"work","thought":"t","say":"s","note":"n","extra":"x"}');
  assert.deepEqual(Object.keys(out).sort(), ['action', 'note', 'say', 'thought']);
});

test('accepts fenced JSON', () => {
  assert.equal(parseDecision('```json\n{"action":"eat"}\n```').action, 'eat');
});

test('rejects unknown actions and malformed JSON', () => {
  assert.throws(() => parseDecision('{"action":"teleport"}'));
  assert.throws(() => parseDecision('not json'));
});

test('bounds model supplied text', () => {
  assert.equal(parseDecision(JSON.stringify({ action: 'rest', say: 'x'.repeat(2000) })).say.length, 500);
});

test('parses a two-person dialogue and drops bad lines', () => {
  const out = parseDialogue(JSON.stringify({
    lines: [
      { speaker: 0, text: 'Morning, Mira! The market smells amazing.' },
      { speaker: 1, text: 'Fresh bread, just for you.' },
      { speaker: 2, text: 'ghost speaker' },
      { speaker: 0, text: '' },
      { speaker: 0, text: 'Save me a loaf!' },
    ],
    summary: 'Pip and Mira talk about bread.',
  }));
  assert.equal(out.lines.length, 3);
  assert.ok(out.lines.every(l => l.speaker === 0 || l.speaker === 1));
  assert.equal(out.summary, 'Pip and Mira talk about bread.');
});

test('rejects dialogue that is too short or malformed', () => {
  assert.throws(() => parseDialogue('{"lines":[{"speaker":0,"text":"hi"}]}'));
  assert.throws(() => parseDialogue('{"lines":"nope"}'));
  assert.throws(() => parseDialogue('garbage'));
});

test('bounds dialogue length', () => {
  const lines = Array.from({ length: 20 }, (_, i) => ({ speaker: i % 2, text: 'y'.repeat(900) }));
  const out = parseDialogue(JSON.stringify({ lines }));
  assert.equal(out.lines.length, 8);
  assert.equal(out.lines[0].text.length, 240);
});

test('parses advice requests', () => {
  const out = parseAdvice('```json\n{"question":"Chief, the homes are full.","options":[{"id":0,"text":"Build a house"},{"id":2,"text":"Claim land"},{"id":"x","text":"bad"}]}\n```');
  assert.equal(out.options.length, 2);
  assert.equal(out.options[1].id, 2);
});

test('rejects advice without real options', () => {
  assert.throws(() => parseAdvice('{"question":"q","options":[{"id":0,"text":"only one"}]}'));
  assert.throws(() => parseAdvice('{"options":[]}'));
});
