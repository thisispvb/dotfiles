#!/usr/bin/env node
/*
  pvb's standing delivery authorization, enforced: a request to change a repo is the go-ahead to
  commit, push and open the PR ready (~/.claude/CLAUDE.md §Delivery). This hook stops the three ways a
  session asks anyway:

  - Stop: the last assistant message offers or asks to commit/push/open a PR ("say go", "ready to
    commit", "shall I push") → block once; `stop_hook_active` set → allow, so it cannot loop.
  - PreToolUse AskUserQuestion: a question or option about committing, pushing or opening a PR → deny.
  - PreToolUse ExitPlanMode: a plan line that gates commit/push/PR on pvb ("wait for pvb's go",
    "confirm before push") → deny.

  Merge, force-push, rebase, protected files, installs, auth and secrets stay real questions: a text
  that names one is allowed. Quoted spans ("…", `…`) are examples, not asks, and are ignored. Fails
  open on any error; PVB_DELIVERY_GATE=off disables it. `node delivery-gate.mjs --test` runs the cases.
*/
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const DELIVERY =
  /\b(commit(s|ting)?|push(es|ing)?|(open|opening|create|raise|ship)(s)? (it|them|this|the|a|its|each|PRs?|pull requests?)|PRs?\b|pull requests?)\b/i;
const EXCLUDED =
  /\b(merg(e|es|ed|ing)|--auto|merge queue|force[- ]?push(ed|ing)?|rebas(e|ing)|reset --hard|protected|package\.json|tsconfig|oxlintrc|eslint\.config|settings\.json|workflow ya?ml|install(s|ing)?|upgrad(e|ing)|auth|CORS|permissions?|secrets?|credentials?|prod(uction)?|deploy(s|ed|ing)?|public|dotfiles|workspaces?|slack|e-?mail|post(s|ed|ing)?)\b/i;
// Waiting on pvb's word, in a message or a plan.
const WAITS = [
  /\bsay (the word )?go\b/i,
  /\b(your|pvb'?s?)( live)? (go|go[- ]ahead|ok|okay|say-?so|approval|green light|sign[- ]off)\b/i,
  /\bonce you (say|confirm|approve|ok)\b/i,
];
// An offer or a question that waits on pvb before delivering.
const ASKS = [
  ...WAITS,
  /\bready to (commit|push|open|ship|raise|create)\b/i,
  /\b(want|would you like|shall|should|do you want|may|can) (me|i) (to )?(go ahead and )?(commit|push|open|create|raise|ship)\b/i,
  /\b(ok|okay|fine|good) (for me )?to (commit|push|open|ship)\b/i,
  /\bwhen(ever)? you('re| are) ready\b/i,
];
// A plan step that waits on pvb before delivering.
const GATES = [
  ...WAITS,
  /\b(wait|waits|waiting|pause|hold) (for|on|until) (pvb|you|the user|approval|confirmation|a go)\b/i,
  /\b(confirm|ask|approval)\b[^.;\n]{0,30}\bbefore (commit|push|open|ship|creat)/i,
  /\b(ask|confirm with) (pvb|the user|you)\b/i,
  /\bonce you approve\b/i,
];
const NEGATED =
  /\b(no|never|without|don'?t|do not|not)\b[^.;\n]{0,25}\b(ask|asking|wait|waiting|approval|confirm|go)\b|\bgo is given\b/i;

const REASON =
  'Deliver it, do not ask: a request to change the repo is the standing authorization to commit, run the ' +
  'battery, push once and open the PR ready (~/.claude/CLAUDE.md §Delivery). Ask only about merging, ' +
  'force-push/rebase, protected files, installs or auth. PVB_DELIVERY_GATE=off disables this hook.';

const unquote = (text) => String(text ?? '').replace(/"[^"\n]*"|“[^”\n]*”|`[^`\n]*`/g, ' ');

/** True when `text` offers or asks to commit, push or open a PR and asks nothing that stays pvb's. */
export function asksToDeliver(text) {
  return unquote(text)
    .split(/(?<=[.?!])\s+|\n+/)
    .some((line) => DELIVERY.test(line) && ASKS.some((ask) => ask.test(line)) && !EXCLUDED.test(line));
}

/** True when a plan line gates commit, push or opening a PR on pvb. */
export function gatesDelivery(plan) {
  return unquote(plan)
    .split(/(?<=[.?!])\s+|\n+/)
    .some(
      (line) =>
        DELIVERY.test(line) && GATES.some((gate) => gate.test(line)) && !EXCLUDED.test(line) && !NEGATED.test(line),
    );
}

/** True when an AskUserQuestion input asks whether to commit, push or open a PR. */
export function questionAsksToDeliver(input) {
  return (input?.questions ?? []).some((question) => {
    // An option that is itself a merge or another of pvb's calls keeps the question; a description that
    // merely mentions one ("it retargets when #8525 merges") does not.
    const labels = (question.options ?? []).map((option) => option.label).join('\n');
    return !EXCLUDED.test(unquote(labels)) && asksToDeliver(question.question);
  });
}

/** The final assistant text of a transcript: the last assistant entry that carries text. */
export function lastAssistantText(transcriptPath) {
  const lines = readFileSync(transcriptPath, 'utf8').trimEnd().split('\n');
  for (let i = lines.length - 1; i >= 0; i -= 1) {
    let entry;
    try {
      entry = JSON.parse(lines[i]);
    } catch {
      continue;
    }
    if (entry.type !== 'assistant') continue;
    const text = (entry.message?.content ?? [])
      .filter((block) => block.type === 'text')
      .map((block) => block.text)
      .join('\n');
    if (text.trim()) return text;
  }
  return '';
}

/** The hook's output for one input, or null to allow. */
export function decide(input) {
  if (input.hook_event_name === 'Stop' || input.hook_event_name === 'SubagentStop') {
    if (input.stop_hook_active) return null;
    const text = input.last_assistant_message ?? (input.transcript_path ? lastAssistantText(input.transcript_path) : '');
    return asksToDeliver(text) ? { decision: 'block', reason: REASON } : null;
  }
  if (input.hook_event_name === 'PreToolUse') {
    const deny =
      (input.tool_name === 'AskUserQuestion' && questionAsksToDeliver(input.tool_input)) ||
      (input.tool_name === 'ExitPlanMode' && gatesDelivery(input.tool_input?.plan));
    if (!deny) return null;
    const why =
      input.tool_name === 'ExitPlanMode'
        ? `${REASON} Drop the plan's step that waits on pvb before commit/push/PR, then exit plan mode again.`
        : REASON;
    return {
      hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: why },
    };
  }
  return null;
}

function selfTest() {
  const failures = [];
  const expect = (name, got, want) => got !== want && failures.push(`${name}: got ${got}, want ${want}`);
  for (const [text, want] of [
    ['Ready to commit and open the PR on `pvb/x` when you say go. The PR body will list the grids.', true],
    ['Once you say go: one battery, one push, and the PR opened ready.', true],
    ['Committing, pushing and the PR wait for your go-ahead.', true],
    ['Want me to open the PR?', true],
    ['Shall I push it?', true],
    ['PR #8546 is green: every check passed and the review is answered.', false],
    ['Pushed and opened #8550 ready; ci:wait is running in the background.', false],
    ['PR #8550 is green. Merge when you are ready.', false],
    ['Want me to merge it?', false],
    ['Shall I force-push the rebased branch?', false],
    ['The hook blocks "ready to commit — say go" endings.', false],
  ]) {
    expect(`stop: ${text}`, asksToDeliver(text), want);
  }
  const q = (question, ...labels) => ({ questions: [{ question, options: labels.map((label) => ({ label })) }] });
  for (const [name, input, want] of [
    ['commit question', q('PR 1 is ready: checks green. Shall I commit, push and open it as ready for review?', 'Go', 'Hold'), true],
    ['push question', q('Should I push the branch now?', 'Yes', 'No'), true],
    ['layout question', q('Which layout should I build? It does not block PRs 1–3.', 'A', 'B'), false],
    ['protected-file question', q('Registering it means editing web/.oxlintrc.jsonc, a protected file. OK to add the rule?', 'Add', 'Skip'), false],
    ['merge question', q('PR #8550 is green. Shall I merge it?', 'Merge', 'Hold'), false],
    [
      'commit question whose option mentions a merge',
      { questions: [{ question: 'PR 2 is ready. Shall I commit, push and open it as ready?', options: [{ label: 'Go', description: 'It retargets to main when #8525 merges.' }] }] },
      true,
    ],
  ]) {
    expect(`ask: ${name}`, questionAsksToDeliver(input), want);
  }
  for (const [plan, want] of [
    ['5. Open PR 2, then wait for pvb\'s go before pushing PR 3.', true],
    ['- Confirm with pvb before push.', true],
    ['- Commit per slice, battery, push once, open ready. No asking.', false],
    ['Never end a turn with "ready to commit when you say go".', false],
    ['- CI green → pvb merges.', false],
    ['- Confirm the hook output with `jq .hooks`.', false],
    ['**Commit, push and PR each wait for pvb\'s go**.', true],
    ['- Open the PR (on a pvb/ branch, not a draft) once you approve.', true],
    ['- Check before committing: the lockfile is unchanged.', false],
    ['- The reviewer takes over once the PR is ready to ship.', false],
    ['The identity column should open the investor in a workspace.', false],
    ['Then a kubernetes PR (dev, then prod on pvb\'s go).', false],
    ['Ship it as a PR and send pvb the link (pvb\'s go is given).', false],
  ]) {
    expect(`plan: ${plan}`, gatesDelivery(plan), want);
  }
  if (failures.length > 0) {
    process.stderr.write(`${failures.join('\n')}\n`);
    process.exit(1);
  }
  process.stdout.write('delivery-gate: all cases pass\n');
}

async function main() {
  if (process.argv.includes('--test')) return selfTest();
  if (process.env.PVB_DELIVERY_GATE === 'off') return;
  try {
    const chunks = [];
    for await (const chunk of process.stdin) chunks.push(chunk);
    const output = decide(JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}'));
    if (output) process.stdout.write(`${JSON.stringify(output)}\n`);
  } catch {
    // Fail open.
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();
