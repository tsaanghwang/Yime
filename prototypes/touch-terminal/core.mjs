// Offline protocol/state model. This module has no host, filesystem or network API.
export const PROTOCOL_VERSION = 1;
export const PAGE_SIZE = 9;
export const SESSION_LIMITS = Object.freeze({ composition: 128, events: 4096, commits: 128 });

const EVENT_FIELDS = ["version", "sessionId", "eventId", "seq", "layoutId", "baseRevision", "type", "payload"];
const PAYLOAD_FIELDS = Object.freeze({
  input: ["yinyuanId"], backspace: [], clear: [], select: ["candidateId"], page: ["delta"], confirm: [],
});

function record(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    && [Object.prototype, null].includes(Object.getPrototypeOf(value));
}

function exactFields(value, fields) {
  return record(value) && Reflect.ownKeys(value).length === fields.length
    && fields.every((field) => Object.hasOwn(value, field));
}

function identifier(value) {
  return typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/.test(value);
}

function copy(value) {
  return JSON.parse(JSON.stringify(value));
}

function invariant(condition, message) {
  if (!condition) throw new TypeError(message);
}

function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (record(value)) return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}`;
  return JSON.stringify(value);
}

function envelopeError(event) {
  if (!exactFields(event, EVENT_FIELDS)) return "事件必须包含且仅包含协议规定的八个字段。";
  if (event.version !== PROTOCOL_VERSION) return "不支持的协议版本。";
  if (![event.sessionId, event.eventId, event.layoutId].every(identifier)) return "会话、事件与布局标识格式无效。";
  if (!Number.isSafeInteger(event.seq) || event.seq < 1) return "seq 必须是正安全整数。";
  if (!Number.isSafeInteger(event.baseRevision) || event.baseRevision < 0) return "baseRevision 必须是非负安全整数。";
  if (typeof event.type !== "string" || !Object.hasOwn(PAYLOAD_FIELDS, event.type)
    || !exactFields(event.payload, PAYLOAD_FIELDS[event.type])) return "事件类型或 payload 字段无效。";
  if (event.type === "input" && !identifier(event.payload.yinyuanId)) return "yinyuanId 格式无效。";
  if (event.type === "select" && !identifier(event.payload.candidateId)) return "candidateId 格式无效。";
  if (event.type === "page" && ![-1, 1].includes(event.payload.delta)) return "翻页 delta 只能为 -1 或 1。";
  return null;
}

/**
 * The only decoder is a traceable, exact-ID fixture lookup. Matching projected
 * code alone would collapse distinct Yinyuan IDs sharing a physical key.
 */
export function createSession(layout, demo, sessionId) {
  invariant(identifier(sessionId), "Invalid sessionId");
  invariant(record(layout) && layout.formatVersion === 1 && identifier(layout.layoutId), "Invalid layout identity");
  invariant(Array.isArray(layout.keys) && layout.keys.length > 0 && layout.keys.length <= 256, "Invalid layout keys");
  const keys = new Map();
  for (const key of layout.keys) {
    invariant(record(key) && identifier(key.id) && typeof key.key === "string" && key.key.length > 0 && key.key.length <= 8, "Invalid layout key");
    invariant(!keys.has(key.id), `Duplicate Yinyuan ID: ${key.id}`);
    keys.set(key.id, key.key);
  }
  invariant(record(demo) && demo.formatVersion === PROTOCOL_VERSION && demo.layoutId === layout.layoutId,
    "Demo layout identity does not match layout");
  invariant(Array.isArray(demo.examples) && demo.examples.length <= 512, "Invalid demo examples");
  const fixtures = new Map();
  const exampleIds = new Set();
  for (const example of demo.examples) {
    invariant(record(example) && identifier(example.id) && !exampleIds.has(example.id), "Invalid or duplicate example ID");
    exampleIds.add(example.id);
    invariant(Array.isArray(example.ids) && example.ids.length > 0 && example.ids.length <= SESSION_LIMITS.composition
      && example.ids.every((id) => keys.has(id)), "Invalid example Yinyuan IDs");
    invariant(example.code === example.ids.map((id) => keys.get(id)).join(""), `Fixture code does not match source projection: ${example.id}`);
    invariant(Array.isArray(example.candidates) && example.candidates.length > 0 && example.candidates.length <= 256, "Invalid fixture candidates");
    const signature = JSON.stringify(example.ids);
    const candidates = fixtures.get(signature) ?? [];
    for (const candidate of example.candidates) {
      invariant(record(candidate) && identifier(candidate.id) && typeof candidate.text === "string"
        && candidate.text.length > 0 && candidate.text.length <= 128, "Invalid candidate");
      const existing = candidates.find((item) => item.id === candidate.id);
      invariant(!existing || existing.text === candidate.text, "Conflicting candidate ID within composition");
      if (!existing) candidates.push({ id: candidate.id, text: candidate.text });
    }
    invariant(candidates.length <= 256, "Too many candidates for composition");
    fixtures.set(signature, candidates);
  }

  const layoutId = layout.layoutId;
  const responses = new Map();
  let state = {
    sessionId, layoutId, revision: 0, nextSeq: 1, ids: [], code: "", candidates: [],
    page: 0, pageCount: 0, selectedId: null, committed: [],
  };

  function composition(ids, page = 0) {
    const all = fixtures.get(JSON.stringify(ids)) ?? [];
    const candidates = all.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE);
    return {
      ids, code: ids.map((id) => keys.get(id)).join(""), candidates, page,
      pageCount: Math.ceil(all.length / PAGE_SIZE), selectedId: candidates[0]?.id ?? null,
    };
  }

  function rejected(code, message) {
    return { ok: false, state, error: { code, message } };
  }

  function process(event) {
    if (event.sessionId !== sessionId) return rejected("SESSION_MISMATCH", "事件属于其他会话。");
    if (event.layoutId !== layoutId) return rejected("LAYOUT_MISMATCH", "布局版本不匹配，请重新建立会话。");
    if (event.seq !== state.nextSeq) return rejected("SEQUENCE_MISMATCH", "事件顺序不匹配；请读取当前状态后使用新的事件 ID。");
    if (event.baseRevision !== state.revision) return rejected("STALE_REVISION", "状态版本已变化，不能对旧候选执行操作。");

    let patch = {};
    let commit;
    switch (event.type) {
      case "input":
        if (!keys.has(event.payload.yinyuanId)) return rejected("UNKNOWN_YINYUAN", "音元 ID 不属于当前布局。");
        if (state.ids.length >= SESSION_LIMITS.composition) return rejected("COMPOSITION_LIMIT", "组合达到长度上限，请清空或确认。");
        patch = composition([...state.ids, event.payload.yinyuanId]);
        break;
      case "backspace":
        patch = composition(state.ids.slice(0, -1));
        break;
      case "clear":
        patch = composition([]);
        break;
      case "select":
        if (!state.candidates.some((candidate) => candidate.id === event.payload.candidateId)) {
          return rejected("CANDIDATE_UNAVAILABLE", "候选不在当前组合的当前页。");
        }
        patch = { selectedId: event.payload.candidateId };
        break;
      case "page": {
        const page = state.page + event.payload.delta;
        if (page < 0 || page >= state.pageCount) return rejected("PAGE_BOUNDARY", "已到候选页边界。");
        patch = composition(state.ids, page);
        break;
      }
      case "confirm": {
        const selected = state.candidates.find((candidate) => candidate.id === state.selectedId);
        if (!selected) return rejected("NO_CANDIDATE", "当前组合没有可确认的示例候选。");
        if (state.committed.length >= SESSION_LIMITS.commits) return rejected("COMMIT_LIMIT", "预览记录达到上限，请重新建立会话。");
        commit = {
          eventId: event.eventId, candidateId: selected.id, text: selected.text,
          ids: state.ids, code: state.code, revision: state.revision + 1,
        };
        patch = { ...composition([]), committed: [...state.committed, commit] };
        break;
      }
    }
    state = { ...state, ...patch, revision: state.revision + 1, nextSeq: state.nextSeq + 1 };
    return { ok: true, state, ...(commit ? { commit } : {}) };
  }

  return Object.freeze({
    get state() { return copy(state); },
    dispatch(event) {
      const malformed = envelopeError(event);
      if (malformed) return copy(rejected("INVALID_EVENT", malformed));
      const fingerprint = canonical(event);
      const cached = responses.get(event.eventId);
      if (cached) {
        return copy(cached.fingerprint === fingerprint ? cached.result
          : rejected("EVENT_ID_CONFLICT", "同一事件 ID 的完整内容发生变化；事件未执行。"));
      }
      // Never evict successful IDs and accidentally execute a retry twice.
      if (responses.size >= SESSION_LIMITS.events) return copy(rejected("SESSION_LIMIT", "会话事件达到上限，请重新建立会话。"));
      const result = process(event);
      responses.set(event.eventId, { fingerprint, result });
      return copy(result);
    },
  });
}
