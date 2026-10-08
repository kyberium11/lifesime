const actions = new Set(['eat', 'sleep', 'wash', 'socialize', 'play', 'work', 'study', 'farm', 'gather', 'cook', 'exercise', 'rest']);

function stripFences(result) {
  return String(result).trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
}

function clean(value, limit) {
  return String(value ?? '').replace(/[\u0000-\u001f]/g, ' ').trim().slice(0, limit);
}

export function parseDecision(result) {
  const data = JSON.parse(stripFences(result));
  if (!data || !actions.has(data.action)) throw Error('Invalid action');
  for (const key of ['thought', 'say', 'note']) {
    if (data[key] !== undefined && typeof data[key] !== 'string') throw Error('Invalid text field');
  }
  return Object.fromEntries(['action', 'thought', 'say', 'note'].map(k => [k, (data[k] || '').slice(0, 500)]));
}

/** A short spoken exchange between two residents: {lines: [{speaker: 0|1, text}], summary}. */
export function parseDialogue(result) {
  const data = JSON.parse(stripFences(result));
  if (!data || !Array.isArray(data.lines)) throw Error('Invalid dialogue');
  const lines = data.lines
    .filter(line => line && (line.speaker === 0 || line.speaker === 1) && typeof line.text === 'string' && line.text.trim())
    .slice(0, 8)
    .map(line => ({ speaker: line.speaker, text: clean(line.text, 240) }));
  if (lines.length < 2) throw Error('Dialogue too short');
  return { lines, summary: clean(data.summary, 160) };
}

/** A resident asking the chief for advice: {question, options: [{id, text}]}. */
export function parseAdvice(result) {
  const data = JSON.parse(stripFences(result));
  if (!data || typeof data.question !== 'string' || !Array.isArray(data.options)) throw Error('Invalid advice');
  const options = data.options
    .filter(o => o && Number.isInteger(o.id) && typeof o.text === 'string' && o.text.trim())
    .slice(0, 4)
    .map(o => ({ id: o.id, text: clean(o.text, 140) }));
  if (options.length < 2) throw Error('Too few options');
  return { question: clean(data.question, 320), options };
}

/** The year's story, written by the model from the facts: {story}. */
export function parseStory(result) {
  const data = JSON.parse(stripFences(result));
  const story = clean(data?.story, 1400);
  if (story.length < 40) throw Error('Story too short');
  return { story };
}

/** A resident's spoken reply to the chief: {say}. The game ignores any other field for chat. */
export function parseChat(result) {
  const data = JSON.parse(stripFences(result));
  if (!data || typeof data.say !== 'string' || !data.say.trim()) throw Error('Invalid reply');
  return { action: '', thought: clean(data.thought, 200), say: clean(data.say, 400), note: '' };
}
