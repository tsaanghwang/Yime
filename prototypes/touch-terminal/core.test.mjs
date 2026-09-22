import test from "node:test";
import assert from "node:assert/strict";
import { createSession, PAGE_SIZE, SESSION_LIMITS } from "./core.mjs";

const layout = {
  formatVersion: 1, layoutId: "source-layout-v1",
  keys: [{ id: "M01", key: "1" }, { id: "N12", key: "x" }, { id: "N26", key: "x" }],
};
const demo = {
  formatVersion: 1, layoutId: layout.layoutId,
  examples: [
    { id: "fixture-one", ids: ["M01", "N12"], code: "1x", candidates: Array.from({ length: 11 }, (_, n) => ({ id: `c${n}`, text: `示例${n}` })) },
    { id: "fixture-two", ids: ["M01", "N26"], code: "1x", candidates: [{ id: "other", text: "另一音元" }] },
  ],
};

function harness() {
  const session = createSession(layout, demo, "test-session");
  let eventCounter = 0;
  function envelope(type, payload = {}, overrides = {}) {
    return {
      version: 1, sessionId: "test-session", layoutId: layout.layoutId,
      eventId: `event-${++eventCounter}`, seq: session.state.nextSeq,
      baseRevision: session.state.revision, type, payload, ...overrides,
    };
  }
  const send = (type, payload, overrides) => session.dispatch(envelope(type, payload, overrides));
  const compose = () => { send("input", { yinyuanId: "M01" }); send("input", { yinyuanId: "N12" }); };
  return { session, envelope, send, compose };
}

test("sound IDs sharing a physical key remain separate semantic inputs", () => {
  const { session, send, compose } = harness();
  compose();
  assert.deepEqual(session.state.ids, ["M01", "N12"]);
  assert.equal(session.state.code, "1x");
  assert.equal(session.state.candidates[0].id, "c0");
  send("backspace");
  send("input", { yinyuanId: "N26" });
  assert.equal(session.state.code, "1x");
  assert.equal(session.state.candidates[0].id, "other");
});

test("candidate matches require the complete ordered fixture ID sequence", () => {
  const { session, send, compose } = harness();
  send("input", { yinyuanId: "N12" });
  send("input", { yinyuanId: "M01" });
  assert.deepEqual(session.state.candidates, []);
  assert.equal(send("confirm").error.code, "NO_CANDIDATE");
  send("clear");
  compose();
  send("input", { yinyuanId: "M01" });
  assert.deepEqual(session.state.candidates, []);
});

test("candidate selection and paging never commit until explicit confirm", () => {
  const { session, send, compose } = harness();
  compose();
  assert.equal(session.state.candidates.length, PAGE_SIZE);
  assert.equal(session.state.pageCount, 2);
  assert.equal(send("select", { candidateId: "c9" }).error.code, "CANDIDATE_UNAVAILABLE");
  send("select", { candidateId: "c2" });
  assert.deepEqual(session.state.committed, []);
  send("page", { delta: 1 });
  assert.equal(session.state.page, 1);
  assert.equal(session.state.selectedId, "c9");
  assert.equal(send("page", { delta: 1 }).error.code, "PAGE_BOUNDARY");
  const result = send("confirm");
  assert.equal(result.commit.text, "示例9");
  assert.equal(result.commit.code, "1x");
  assert.deepEqual(result.commit.ids, ["M01", "N12"]);
  assert.equal(session.state.committed.length, 1);
  assert.deepEqual(session.state.ids, []);
  assert.deepEqual(session.state.candidates, []);
});

test("backspace or clear on an empty composition never deletes committed preview text", () => {
  const { session, send, compose } = harness();
  compose();
  send("confirm");
  const committed = session.state.committed;
  send("backspace");
  send("clear");
  assert.deepEqual(session.state.committed, committed);
  assert.equal(session.state.code, "");
});

test("exact retry returns the historical response without repeating commit", () => {
  const { session, envelope, send, compose } = harness();
  compose();
  const event = envelope("confirm");
  const first = session.dispatch(event);
  send("input", { yinyuanId: "N26" });
  const after = session.state;
  const retry = session.dispatch({ ...event, payload: {} });
  assert.deepEqual(retry, first);
  assert.deepEqual(session.state, after);
  assert.equal(session.state.committed.length, 1);
});

test("changed duplicate envelope is a conflict even after state advances", () => {
  const { session, envelope, send } = harness();
  const event = envelope("input", { yinyuanId: "N12" });
  session.dispatch(event);
  for (const changed of [
    { ...event, payload: { yinyuanId: "N26" } }, { ...event, baseRevision: 1 },
    { ...event, seq: 2 }, { ...event, layoutId: "other" }, { ...event, sessionId: "other" },
  ]) assert.equal(session.dispatch(changed).error.code, "EVENT_ID_CONFLICT");
  send("input", { yinyuanId: "M01" });
  assert.deepEqual(session.state.ids, ["N12", "M01"]);
});

test("stale candidate click and out-of-order messages do not mutate state", () => {
  const { session, send, compose } = harness();
  compose();
  const oldRevision = session.state.revision;
  send("backspace");
  const before = session.state;
  assert.equal(send("select", { candidateId: "c0" }, { baseRevision: oldRevision }).error.code, "STALE_REVISION");
  assert.equal(send("input", { yinyuanId: "N12" }, { seq: 99 }).error.code, "SEQUENCE_MISMATCH");
  assert.deepEqual(session.state, before);
});

test("well-formed rejection retry stays idempotent and requires a new event ID to correct", () => {
  const { session, envelope, send } = harness();
  const event = envelope("confirm");
  const first = session.dispatch(event);
  send("input", { yinyuanId: "M01" });
  assert.deepEqual(session.dispatch(event), first);
  assert.equal(session.dispatch({ ...event, type: "clear" }).error.code, "EVENT_ID_CONFLICT");
});

test("strict schema rejects unknown fields, implicit key selection and malformed payloads", () => {
  const { session, envelope } = harness();
  const valid = envelope("input", { yinyuanId: "M01" });
  const invalid = [
    null, [], { ...valid, extra: true }, { ...valid, version: 2 }, { ...valid, seq: 0 },
    { ...valid, seq: 1.5 }, { ...valid, baseRevision: -1 }, { ...valid, eventId: "" },
    { ...valid, type: "constructor" }, { ...valid, type: ["input"] }, { ...valid, type: "digit", payload: { digit: 1 } },
    { ...valid, payload: { key: "1" } }, { ...valid, payload: { yinyuanId: "M01", select: 1 } },
    { ...valid, type: "page", payload: { delta: 0 } }, { ...valid, type: "confirm", payload: { text: "偷偷提交" } },
  ];
  for (const event of invalid) assert.equal(session.dispatch(event).error.code, "INVALID_EVENT");
  assert.equal(session.state.revision, 0);
  assert.equal(session.state.nextSeq, 1);
});

test("session, layout and unknown sound IDs are rejected without consuming sequence", () => {
  const { session, send } = harness();
  assert.equal(send("clear", {}, { sessionId: "other" }).error.code, "SESSION_MISMATCH");
  assert.equal(send("clear", {}, { layoutId: "other" }).error.code, "LAYOUT_MISMATCH");
  assert.equal(send("input", { yinyuanId: "N99" }).error.code, "UNKNOWN_YINYUAN");
  assert.equal(session.state.nextSeq, 1);
});

test("external mutation of configuration or returned snapshots cannot mutate session", () => {
  const mutableLayout = structuredClone(layout);
  const mutableDemo = structuredClone(demo);
  const session = createSession(mutableLayout, mutableDemo, "test-session");
  mutableLayout.layoutId = "changed";
  mutableLayout.keys[0].key = "bad";
  mutableDemo.examples[0].candidates[0].text = "bad";
  let seq = 0;
  const send = (type, payload = {}) => session.dispatch({ version: 1, sessionId: "test-session", layoutId: layout.layoutId, eventId: `e${++seq}`, seq, baseRevision: session.state.revision, type, payload });
  send("input", { yinyuanId: "M01" });
  const response = send("input", { yinyuanId: "N12" });
  response.state.candidates[0].text = "bad";
  response.state.ids.push("N26");
  session.state.ids.push("N26");
  assert.equal(session.state.code, "1x");
  assert.equal(session.state.candidates[0].text, "示例0");
  assert.deepEqual(session.state.ids, ["M01", "N12"]);
});

test("composition bounds fail closed and can be recovered by clear", () => {
  const { session, send } = harness();
  for (let n = 0; n < SESSION_LIMITS.composition; n++) assert.equal(send("input", { yinyuanId: "M01" }).ok, true);
  assert.equal(send("input", { yinyuanId: "M01" }).error.code, "COMPOSITION_LIMIT");
  assert.equal(session.state.ids.length, SESSION_LIMITS.composition);
  assert.equal(send("clear").ok, true);
  assert.deepEqual(session.state.ids, []);
});

test("event cache has a hard bound and keeps the earliest retry safe", () => {
  const { session, envelope, send } = harness();
  const firstEvent = envelope("clear");
  const firstResult = session.dispatch(firstEvent);
  for (let n = 1; n < SESSION_LIMITS.events; n++) assert.equal(send("clear").ok, true);
  assert.equal(send("clear").error.code, "SESSION_LIMIT");
  assert.deepEqual(session.dispatch(firstEvent), firstResult);
});

test("preview commit limit never silently discards older text", () => {
  const { session, send, compose } = harness();
  for (let n = 0; n < SESSION_LIMITS.commits; n++) {
    compose();
    assert.equal(send("confirm").ok, true);
  }
  compose();
  const before = session.state;
  assert.equal(send("confirm").error.code, "COMMIT_LIMIT");
  assert.deepEqual(session.state, before);
  assert.equal(session.state.committed.length, SESSION_LIMITS.commits);
});

test("fixture data cannot repair or invent an unmatched semantic projection", () => {
  const invalid = structuredClone(demo);
  invalid.examples[0].code = "invented";
  assert.throws(() => createSession(layout, invalid, "test-session"), /source projection/);
  const unknown = structuredClone(demo);
  unknown.examples[0].ids[0] = "N99";
  assert.throws(() => createSession(layout, unknown, "test-session"), /Yinyuan IDs/);
});

test("fixture identity must match the complete loaded layout snapshot", () => {
  for (const changed of [
    { ...demo, layoutId: "other-layout-with-identical-projection" },
    { ...demo, formatVersion: 2 },
    { examples: demo.examples },
  ]) assert.throws(() => createSession(layout, changed, "test-session"), /layout identity/);
});
