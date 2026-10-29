/* app.js —— ravel breve 网页前端（无框架，原生 DOM）
 *
 * 一条设计原则：**前端不解析、不求值**（REQ-24）。它只做三件事：
 *   ① 把用户摆出来的东西编译成方言源（纯文本拼接）；
 *   ② 把源发给桥（POST /api/eval），把 `result.stack` 当成不透明文本渲染；
 *   ③ 记住"栈上现在摆着什么"，这样拖动改序 / 编辑 / 分割都是本地的编辑动作。
 *
 * 所以这里的两套栈是不同的东西：
 *   - **本地栈（state.stack）**：用户摆的字面量，尚未发送。可随便改。
 *   - **后端栈（state.last.stack）**：上一次运行后后端的真实栈（已渲染文本）。
 *     只能"拖回"（作为文本复制一项），不能改序——那是后端的事。
 */
(() => {
  "use strict";

  /* ── 小工具 ─────────────────────────────────────────────────────────── */
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
  const uid = (() => { let n = 0; return () => `i${++n}`; })();

  function h(tag, props, ...kids) {
    const node = document.createElement(tag);
    for (const [k, v] of Object.entries(props || {})) {
      if (v == null || v === false) continue;
      if (k === "class") node.className = v;
      else if (k === "dataset") Object.assign(node.dataset, v);
      else if (k === "style") Object.assign(node.style, v);
      else if (k.startsWith("on")) node.addEventListener(k.slice(2), v);
      else if (k === "html") node.innerHTML = v;
      else if (k in node) node[k] = v;
      else node.setAttribute(k, v);
    }
    for (const kid of kids.flat()) {
      if (kid == null || kid === false) continue;
      node.append(kid.nodeType ? kid : document.createTextNode(String(kid)));
    }
    return node;
  }

  /* ── 状态 ───────────────────────────────────────────────────────────── */
  const S = {
    catalog: { groups: [], version: "?", spec: "" },
    words: [],                 // 扁平词表
    filter: { q: "", layer: "" },
    stack: [],                 // [{id, src, note}]  index 0 = 栈顶
    frames: [],                // [{id, word, args:[item], result, busy}]
    sel: new Set(),
    activeFrame: null,
    armedFrame: false,         // "开帧…" 已按下，等下一个词
    last: null,                // 上次 result
    manual: false,
    conn: { state: "wait", text: "连接中…" },
    streams: [],               // [{tag, kind, text}]
  };

  const status = (text, kind = "") => {
    const node = $("#status");
    node.textContent = text;
    node.dataset.kind = kind;
  };

  /* ── 桥 ─────────────────────────────────────────────────────────────── */
  async function api(path, body) {
    const res = await fetch(path, {
      method: body === undefined ? "GET" : "POST",
      headers: body === undefined ? undefined : { "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    let data;
    try { data = await res.json(); } catch { throw new Error(`${res.status} ${res.statusText}`); }
    return data;
  }

  async function evalSource(src, { quiet = false } = {}) {
    if (!quiet) status("运行中…", "busy");
    const t0 = performance.now();
    const msg = await api("/api/eval", { src });
    msg.ms = Math.round(performance.now() - t0);
    return msg;
  }

  /* ── 词表 ───────────────────────────────────────────────────────────── */
  function flatten(catalog) {
    const out = [];
    for (const g of catalog.groups) {
      for (const w of g.words) out.push({ ...w, layer: g.layer, title: g.title });
    }
    return out;
  }

  function renderLayers() {
    const box = $("#layers");
    box.textContent = "";
    const all = h("button", {
      class: "chip", type: "button", "aria-pressed": String(S.filter.layer === ""),
      onclick: () => { S.filter.layer = ""; renderLayers(); renderWords(); },
    }, "全部");
    all.classList.add("chip");
    box.append(all);
    for (const g of S.catalog.groups) {
      const b = h("button", {
        class: "chip", type: "button",
        "aria-pressed": String(S.filter.layer === g.layer),
        title: g.title,
        onclick: () => {
          S.filter.layer = S.filter.layer === g.layer ? "" : g.layer;
          renderLayers(); renderWords();
        },
      }, g.layer);
      box.append(b);
    }
  }

  function renderWords() {
    const list = $("#wordlist");
    list.textContent = "";
    const q = S.filter.q.trim().toLowerCase();
    const exact = q ? S.words.filter(w => w.name.toLowerCase() === q) : [];
    const exactNames = new Set(exact.map(w => w.name));
    let shown = 0;
    for (const g of S.catalog.groups) {
      if (S.filter.layer && g.layer !== S.filter.layer) continue;
      const words = g.words.filter(w => {
        if (!q) return true;
        if (exactNames.size) return exactNames.has(w.name);
        return w.name.toLowerCase().includes(q) ||
          (w.effect || "").toLowerCase().includes(q) ||
          (w.desc || "").toLowerCase().includes(q);
      });
      if (!words.length) continue;
      const group = h("section", { class: "palette__group" },
        h("div", { class: "palette__glabel", title: g.title }, `${g.layer} · ${g.title}`),
      );
      for (const w of words) {
        shown++;
        group.append(h("button", {
          class: "word", type: "button", draggable: "true",
          title: `${w.name} ${w.effect || ""}${w.desc ? "\n" + w.desc : ""}\n（点 = 开帧 / 拖 = 放到栈或帧里）`,
          onclick: (ev) => onWordClick(w, ev),
          ondragstart: (ev) => {
            dragPayload(ev, { kind: "word", name: w.name });
          },
        },
          h("span", { class: "word__name" }, w.name),
          h("span", { class: "word__effect" }, w.effect || ""),
          h("span", { class: "word__desc" }, w.desc || ""),
        ));
      }
      list.append(group);
    }
    if (!shown) list.append(h("p", { class: "streams__empty" }, "没有匹配的词。"));
    $("#chip-count").textContent = `${S.words.length} 词`;
  }

  /* ── 栈：增删改查 ───────────────────────────────────────────────────── */
  const topIndex = 0;

  function addItem(src, note = "") {
    const item = { id: uid(), src: String(src).trim(), note };
    S.stack.splice(topIndex, 0, item);
    return item;
  }

  function removeItems(ids) {
    const set = new Set(ids);
    S.stack = S.stack.filter(i => !set.has(i.id));
    for (const id of set) S.sel.delete(id);
  }

  function itemsByIds(ids) {
    const set = new Set(ids);
    return S.stack.filter(i => set.has(i.id));
  }

  function selectedItems() {
    const order = new Map(S.stack.map((it, idx) => [it.id, idx]));
    return itemsByIds([...S.sel]).sort((a, b) => order.get(a.id) - order.get(b.id));
  }

  function moveItemsTo(ids, index) {
    const moving = itemsByIds(ids);
    if (!moving.length) return;
    const rest = S.stack.filter(i => !ids.includes(i.id));
    const movingSet = new Set(moving.map(i => i.id));
    // index 是按"原列表"算的落点：先去掉移动项，再把落点换算到新列表
    let target = 0;
    for (let k = 0; k < index && k < S.stack.length; k++) {
      if (!movingSet.has(S.stack[k].id)) target++;
    }
    rest.splice(Math.max(0, Math.min(target, rest.length)), 0, ...moving);
    S.stack = rest;
  }

  function toggleSel(id, { exclusive = false } = {}) {
    if (exclusive) {
      const had = S.sel.has(id) && S.sel.size === 1;
      S.sel.clear();
      if (!had) S.sel.add(id);
    } else if (S.sel.has(id)) S.sel.delete(id);
    else S.sel.add(id);
  }

  /* ── 栈：渲染 ───────────────────────────────────────────────────────── */
  function renderStack() {
    const box = $("#stack");
    box.textContent = "";
    $("#stack-depth").textContent = String(S.stack.length);
    if (!S.stack.length) {
      box.append(h("div", { class: "stack-empty", id: "stack-empty" },
        h("p", { class: "stack-empty__t" }, "栈是空的"),
        h("p", { class: "stack-empty__d" }, "上面压入字面量，或把左边的词拖到这儿开一帧。"),
      ));
    }
    S.stack.forEach((item, idx) => box.append(stackItemNode(item, idx)));
    renderSelectionBar();
    if (!S.manual) syncProgram();
  }

  function stackItemNode(item, idx) {
    const node = h("div", {
      class: "stack-item" + (S.sel.has(item.id) ? " is-sel" : "") + (idx === 0 ? " is-top" : ""),
      draggable: "true",
      dataset: { id: item.id, idx: String(idx) },
      ondragstart: (ev) => {
        if (!S.sel.has(item.id)) { S.sel.clear(); S.sel.add(item.id); paintSelection(); }
        const ids = [...S.sel];
        dragPayload(ev, { kind: "stack", ids });
        node.classList.add("is-drag");
      },
      ondragend: () => { node.classList.remove("is-drag"); renderStack(); },
      onclick: (ev) => {
        if (ev.target.closest("button") || ev.target.closest(".stack-item__edit")) return;
        if (dragJustHappened()) return;
        const additive = ev.shiftKey || ev.metaKey || ev.ctrlKey ||
          ev.target.closest(".stack-item__handle");
        toggleSel(item.id, { exclusive: !additive });
        renderStack();
      },
      ondblclick: (ev) => { if (!ev.target.closest("button")) beginEdit(item, node); },
    },
      h("span", { class: "stack-item__handle", title: "拖动改序" }, idx === 0 ? "▸" : "⋮"),
      h("div", { class: "stack-item__body" },
        h("div", { class: "stack-item__src" }, item.src),
        item.note ? h("div", { class: "stack-item__note" }, item.note) : null,
      ),
      h("div", { class: "stack-item__acts" },
        h("button", { class: "icon-btn", title: "编辑（双击也行）", onclick: () => beginEdit(item, node) }, "✎"),
        h("button", { class: "icon-btn", title: "分割…", onclick: (ev) => openSplitMenu(ev.currentTarget, item) }, "✂"),
        h("button", { class: "icon-btn", title: "复制", onclick: () => duplicateItem(item) }, "⧉"),
        h("button", { class: "icon-btn icon-btn--danger", title: "删除", onclick: () => { removeItems([item.id]); renderStack(); } }, "✕"),
      ),
    );
    return node;
  }

  function beginEdit(item, node) {
    const body = $(".stack-item__body", node);
    const ta = h("textarea", { class: "stack-item__edit", rows: Math.min(6, Math.max(1, item.src.split("\n").length)) });
    ta.value = item.src;
    body.textContent = "";
    body.append(ta);
    ta.focus();
    ta.select();
    let done = false;
    const commit = () => {
      if (done) return;
      done = true;
      const v = ta.value.trim();
      if (v) { item.src = v; item.note = ""; }
      renderStack();
    };
    ta.addEventListener("keydown", (ev) => {
      if (ev.key === "Enter" && !ev.shiftKey) { ev.preventDefault(); commit(); }
      if (ev.key === "Escape") { ev.preventDefault(); renderStack(); }
      ev.stopPropagation();
    });
    ta.addEventListener("blur", commit, { once: true });
  }

  function duplicateItem(item) {
    const idx = S.stack.findIndex(i => i.id === item.id);
    const copy = { id: uid(), src: item.src, note: item.note };
    S.stack.splice(idx, 0, copy);
    renderStack();
  }

  function openSplitMenu(anchor, item) {
    const parts = splitTokens(item.src);
    const items = [
      ["按 token 拆（尊重 {} [] 嵌套）", () => parts.length > 1 ? expandItem(item, parts) : status("这一项只有一个 token。", "bad")],
      ["按空白粗暴拆", () => {
        const bits = item.src.split(/\s+/).filter(Boolean);
        bits.length > 1 ? expandItem(item, bits) : status("这一项只有一个词。", "bad");
      }],
      ["拆出引号 [ … ] 内部", () => {
        const m = item.src.match(/^\[([\s\S]*)\]$/);
        if (!m) return status("这一项不是 [ … ] 引号。", "bad");
        const inner = splitTokens(m[1]);
        inner.length ? expandItem(item, inner, "来自引号") : status("引号里是空的。", "bad");
      }],
    ];
    openMenu(anchor, items);
  }

  function expandItem(item, bits, note = "") {
    const idx = S.stack.findIndex(i => i.id === item.id);
    const made = bits.map(b => ({ id: uid(), src: b, note }));
    S.stack.splice(idx, 1, ...made);
    S.sel.clear();
    made.forEach(m => S.sel.add(m.id));
    renderStack();
    status(`分割成 ${made.length} 项`, "ok");
  }

  /* ── 栈：选中栏 ─────────────────────────────────────────────────────── */
  /* 只改 class，不重建 DOM：拖动过程中重建会让 drop 目标（旧节点）脱离文档 */
  function paintSelection() {
    for (const node of $$(".stack-item", $("#stack"))) {
      node.classList.toggle("is-sel", S.sel.has(node.dataset.id));
    }
    renderSelectionBar();
  }

  function renderSelectionBar() {
    const bar = $("#selection-bar");
    bar.hidden = S.sel.size === 0;
    $("#sel-count").textContent = `已选 ${S.sel.size}`;
  }

  $$("[data-sel]").forEach(btn => {
    btn.addEventListener("click", () => {
      const act = btn.dataset.sel;
      if (act === "none") { S.sel.clear(); renderStack(); return; }
      if (act === "drop") { removeItems([...S.sel]); renderStack(); return; }
      if (act === "dup") {
        const picked = selectedItems();
        S.sel.clear();
        for (const it of picked) {
          const idx = S.stack.findIndex(x => x.id === it.id);
          const copy = { id: uid(), src: it.src, note: it.note };
          S.stack.splice(idx, 0, copy);
          S.sel.add(copy.id);
        }
        renderStack();
        return;
      }
      if (act === "quote") {
        const picked = selectedItems();
        if (!picked.length) return;
        const inner = picked.slice().reverse().map(i => i.src).join(" ");
        removeItems(picked.map(i => i.id));
        const made = addItem(`[ ${inner} ]`, "引号块");
        S.sel.clear(); S.sel.add(made.id);
        renderStack();
        status("包成了一个引号块", "ok");
        return;
      }
      if (act === "frame") {
        S.armedFrame = true;
        status("点一个词，用选中的项开帧", "busy");
        $("#search").focus();
      }
    });
  });

  /* ── 帧 ─────────────────────────────────────────────────────────────── */
  function createFrame(word, args) {
    const frame = { id: uid(), word, args: args.map(a => ({ ...a })), result: null, busy: false };
    if (args.length) removeItems(args.map(a => a.id));
    S.frames.unshift(frame);
    S.activeFrame = frame.id;
    S.armedFrame = false;
    renderStack(); renderFrames();
    status(`开了帧：${word.name}（${args.length} 个参数）`, "ok");
    return frame;
  }

  const isNarrow = () => window.matchMedia("(max-width: 860px)").matches;

  function togglePalette(open) {
    const p = $("#palette");
    const on = open === undefined ? !p.classList.contains("is-open") : open;
    p.classList.toggle("is-open", on);
    $("#btn-palette-toggle").setAttribute("aria-expanded", String(on));
  }

  function onWordClick(word, ev) {
    if (S.sel.size) createFrame(word, selectedItems());
    else createFrame(word, []);
    // 窄屏时面板是浮层，选完词就收起来，别挡住栈
    if (isNarrow()) togglePalette(false);
  }

  function frameSource(f) {
    const args = f.args.map(a => a.src.trim()).filter(Boolean).join(" ");
    return args ? `${f.word.name} ${args}` : f.word.name;
  }

  function frameById(id) { return S.frames.find(f => f.id === id); }

  async function computeFrame(f) {
    if (f.closed) return { ok: false, error: "帧已关闭" };
    if (f.busy) return { ok: false, error: "正在算" };
    // 连点保护：同一次操作常常被浏览器/测试工具重放两次，120ms 内只算一次
    const now = performance.now();
    if (now - (f.lastCompute || 0) < 120) return f.result || { ok: false, error: "刚算过" };
    f.lastCompute = now;
    f.busy = true; renderFrames();
    try {
      const msg = await evalSource(frameSource(f), { quiet: true });
      f.result = msg.ok
        ? { ok: true, stack: msg.stack || [], ms: msg.ms }
        : { ok: false, error: msg.error || "失败", code: msg.code };
    } catch (e) {
      f.result = { ok: false, error: String(e), code: 0 };
    } finally {
      f.busy = false;
      renderFrames();
    }
    status(f.result.ok ? "帧算完了：拖结果回栈，或点返回" : `帧失败：${f.result.error}`, f.result.ok ? "ok" : "bad");
    return f.result;
  }

  async function returnFrame(f, valueIndex = null) {
    if (f.closed) return;
    if (!f.result || !f.result.ok) {
      const r = await computeFrame(f);
      if (!r.ok) return;
    }
    const st = f.result.stack;
    if (!st.length) { status("这一帧没留下值（栈是空的）", "bad"); return; }
    const picks = valueIndex == null ? st.map((_, k) => k) : [valueIndex];
    closeFrame(f);
    const made = [];
    for (const k of picks) {
      // 栈序是从底到顶：底先入，最后一项成为新栈顶
      made.push(addItem(st[k], reenterable(st[k]) ? "帧返回" : "帧返回 · 可能不可回读"));
    }
    S.sel.clear();
    S.sel.add(made[made.length - 1].id);
    renderStack();
    status(picks.length > 1 ? `返回：整帧 ${picks.length} 项压回主栈` : "返回：把栈顶压回主栈", "ok");
  }

  function giveBackFrame(f) {
    if (f.closed) return;
    const back = f.args.slice();
    closeFrame(f);
    for (let k = back.length - 1; k >= 0; k--) addItem(back[k].src, back[k].note);
    renderStack();
    status("参数已归还到栈", "ok");
  }

  function closeFrame(f) {
    if (f.closed) return;
    f.closed = true;
    S.frames = S.frames.filter(x => x.id !== f.id);
    if (S.activeFrame === f.id) S.activeFrame = null;
    renderFrames();
  }

  function appendToFrame(f, items) {
    if (!items.length) return;
    for (const it of items) f.args.push({ ...it });
    removeItems(items.map(i => i.id));
    S.activeFrame = f.id;
    renderStack(); renderFrames();
  }

  function renderFrames() {
    const list = $("#frames-list");
    $("#frame-count").textContent = String(S.frames.length);
    list.textContent = "";
    if (!S.frames.length) {
      list.append(h("div", { class: "frames__empty" },
        h("p", {}, "把栈项拖到一个", h("strong", {}, "词"), "上，就开一帧。"),
        h("p", { class: "muted" }, "帧里的参数按「书写序」排列；", h("br"), "算完可以 ", h("em", {}, "返回"), " 或把结果", h("em", {}, "拖回"), "栈。"),
      ));
      return;
    }
    for (const f of S.frames) list.append(frameNode(f));
  }

  function frameNode(f) {
    const argsBox = h("div", {
      class: "frame__args", dataset: { drop: "frame-args", frame: f.id },
    });
    if (!f.args.length) argsBox.append(h("div", { class: "frame__args-empty" }, "参数：把栈项拖进来（或选中后点这个帧）"));
    f.args.forEach((a, i) => argsBox.append(h("div", {
      class: "frame-arg", draggable: "true",
      dataset: { frame: f.id, arg: a.id },
      ondragstart: (ev) => dragPayload(ev, { kind: "arg", frame: f.id, id: a.id }),
      title: "拖回栈 = 归还这一项",
    },
      h("span", { class: "frame-arg__pos" }, String(i + 1)),
      h("span", { class: "frame-arg__src" }, a.src),
      h("button", {
        class: "icon-btn icon-btn--danger", title: "移出（回栈）",
        onclick: () => {
          f.args = f.args.filter(x => x.id !== a.id);
          addItem(a.src, a.note); renderStack(); renderFrames();
        },
      }, "✕"),
    )));

    const resBox = h("div", { class: "frame__res" });
    if (f.busy) resBox.append(h("div", { class: "frame__res-head" }, "计算中…"));
    else if (!f.result) {
      resBox.append(h("div", { class: "frame__res-head" },
        h("span", {}, "还没算"),
        h("button", { class: "btn btn--tiny", onclick: () => computeFrame(f) }, "ƒ 计算"),
      ));
    } else if (!f.result.ok) {
      resBox.append(h("div", { class: "frame__res-head" }, `失败（code ${f.result.code}）`,
        h("button", { class: "btn btn--tiny", onclick: () => computeFrame(f) }, "重算")));
      resBox.append(h("p", { class: "frame__err" }, f.result.error));
    } else if (!f.result.stack.length) {
      resBox.append(h("div", { class: "frame__res-head" }, "算出空栈（没有可返回的值）",
        h("button", { class: "btn btn--tiny", onclick: () => computeFrame(f) }, "重算")));
    } else {
      resBox.append(h("div", { class: "frame__res-head" },
        h("span", {}, `结果 ${f.result.stack.length} 项 · ${f.result.ms ?? 0}ms`),
        h("button", { class: "btn btn--tiny", onclick: () => computeFrame(f) }, "重算"),
      ));
      const rev = f.result.stack.slice().reverse();
      rev.forEach((text, i) => {
        const realIndex = f.result.stack.length - 1 - i;
        resBox.append(h("div", {
          class: "frame-result", draggable: "true",
          title: "拖回栈 = 返回这一项并关帧",
          ondragstart: (ev) => dragPayload(ev, { kind: "result", frame: f.id, index: realIndex }),
          onclick: () => returnFrame(f, realIndex),
        },
          h("span", { style: { flex: "1" } }, text),
          h("span", { class: "frame-result__hint" }, i === 0 ? "栈顶 ↵" : "拖回"),
        ));
      });
    }

    return h("article", {
      class: "frame" + (S.activeFrame === f.id ? " is-active" : ""),
      dataset: { frame: f.id, drop: "frame" },
      onclick: (ev) => {
        if (ev.target.closest("button")) return;
        S.activeFrame = f.id; renderFrames();
      },
      ondragover: (ev) => { if (dragKind() === "stack") { ev.preventDefault(); argsBox.classList.add("is-over"); } },
      ondragleave: () => argsBox.classList.remove("is-over"),
      ondrop: (ev) => {
        const p = dropPayload(ev);
        if (!p) return;
        if (p.kind === "stack") appendToFrame(f, itemsByIds(p.ids));
        else if (p.kind === "arg") {
          const a = f.args.find(x => x.id === p.id);
          if (a) { f.args = f.args.filter(x => x.id !== p.id).concat([a]); renderFrames(); }
        } else if (p.kind === "result") {
          const g = frameById(p.frame);
          if (g) returnFrame(g, p.index);
        }
        ev.stopPropagation();
      },
    },
      h("header", { class: "frame__head" },
        h("span", { class: "frame__name" }, f.word.name),
        h("span", { class: "frame__effect" }, f.word.effect || ""),
        h("button", {
          class: "icon-btn icon-btn--danger", title: "丢弃这一帧（参数一并丢弃）",
          onclick: () => { closeFrame(f); status("帧已丢弃（参数没回栈）"); },
        }, "✕"),
      ),
      argsBox,
      h("div", { class: "frame__src" }, "源： " + frameSource(f)),
      resBox,
      h("div", { class: "frame__acts" },
        h("button", { class: "btn btn--tiny btn--accent", onclick: () => returnFrame(f), title: "算完把栈顶压回主栈并关帧" }, "⟵ 返回"),
        h("button", { class: "btn btn--tiny", onclick: () => computeFrame(f) }, "ƒ 计算"),
        h("button", { class: "btn btn--tiny btn--quiet", onclick: () => giveBackFrame(f), title: "参数原样回栈" }, "↩ 归还"),
      ),
    );
  }

  /* ── 程序 / 结果 ────────────────────────────────────────────────────── */
  function deriveSource() {
    return S.stack.slice().reverse().map(i => i.src).filter(s => s.trim()).join("\n");
  }

  function syncProgram() {
    const ta = $("#program");
    ta.value = deriveSource();
  }

  function renderResult() {
    const box = $("#result");
    const list = $("#result-list");
    const err = $("#result-err");
    const raw = $("#result-raw");
    if (!S.last) { box.hidden = true; return; }
    box.hidden = false;
    list.textContent = "";
    raw.textContent = JSON.stringify(S.last, null, 1);
    err.hidden = true;
    if (!S.last.ok) {
      $("#result-meta").textContent = `code ${S.last.code ?? "?"}`;
      err.hidden = false;
      err.textContent = S.last.error || "失败";
      return;
    }
    const st = S.last.stack || [];
    $("#result-meta").textContent = `${st.length} 项 · ${S.last.ms ?? 0}ms`;
    const rev = st.slice().reverse();
    rev.forEach((text, i) => {
      const realIndex = st.length - 1 - i;
      list.append(h("div", {
        class: "res-item", draggable: "true",
        title: "拖到栈上 = 以文本复制这一项",
        ondragstart: (ev) => dragPayload(ev, { kind: "value", text }),
        onclick: () => { navigator.clipboard?.writeText(text); status("已复制到剪贴板", "ok"); },
      },
        h("span", { class: "res-item__text" }, text),
        h("span", { class: "res-item__hint" }, i === 0 ? "栈顶" : "拖回"),
      ));
    });
    if (!rev.length) list.append(h("p", { class: "streams__empty" }, "后端栈是空的。"));
  }

  async function run() {
    const src = S.manual ? $("#program").value : deriveSource();
    if (!src.trim()) { status("没有可运行的源", "bad"); return; }
    const pending = S.frames.length;
    try {
      if ($("#clean").checked) await api("/api/reset", {});
      S.last = await evalSource(src);
      renderResult();
      const tail = pending ? `（还有 ${pending} 帧没返回，没进这次程序）` : "";
      if (S.last.ok) status(`运行完成 · ${(S.last.stack || []).length} 项 · ${S.last.ms}ms${tail}`, "ok");
      else status(`失败（code ${S.last.code}）：${S.last.error}`, "bad");
    } catch (e) {
      S.last = { ok: false, code: 0, error: String(e), stack: [] };
      renderResult();
      status(`桥不通：${e}`, "bad");
    }
  }

  /* ── 拖拽 ───────────────────────────────────────────────────────────── */
  let dragData = null;
  let lastDragEnd = 0;
  const dragJustHappened = () => performance.now() - lastDragEnd < 120;
  const dragKind = () => dragData?.kind;

  function dragPayload(ev, payload) {
    dragData = payload;
    ev.dataTransfer.effectAllowed = "move";
    try { ev.dataTransfer.setData("text/plain", JSON.stringify(payload)); } catch { /* Safari */ }
  }

  function dropPayload(ev) {
    ev.preventDefault();
    let p = dragData;
    if (!p) {
      try { p = JSON.parse(ev.dataTransfer.getData("text/plain") || "null"); } catch { p = null; }
    }
    return p;
  }

  document.addEventListener("dragend", () => {
    dragData = null;
    lastDragEnd = performance.now();
    $$(".is-over").forEach(n => n.classList.remove("is-over"));
  });

  function stackDropIndex(ev, box) {
    const cards = $$(".stack-item", box);
    for (let k = 0; k < cards.length; k++) {
      const r = cards[k].getBoundingClientRect();
      if (ev.clientY < r.top + r.height / 2) return Number(cards[k].dataset.idx);
    }
    return S.stack.length;
  }

  function wireStackDrop() {
    const box = $("#stack");
    box.addEventListener("click", (ev) => {
      if (ev.target !== box && !ev.target.closest(".stack-empty")) return;
      if (!S.sel.size) return;
      S.sel.clear(); paintSelection();
    });
    box.addEventListener("dragover", (ev) => {
      if (!dragKind()) return;
      ev.preventDefault();
      box.classList.add("is-over");
      // 插入位置指示
      $$(".stack-insert", box).forEach(n => n.remove());
      const idx = stackDropIndex(ev, box);
      const mark = h("div", { class: "stack-insert" });
      const cards = $$(".stack-item", box);
      if (idx >= cards.length) box.append(mark);
      else box.insertBefore(mark, cards[idx]);
    });
    box.addEventListener("dragleave", (ev) => {
      if (ev.target === box) { box.classList.remove("is-over"); $$(".stack-insert", box).forEach(n => n.remove()); }
    });
    box.addEventListener("drop", (ev) => {
      const p = dropPayload(ev);
      box.classList.remove("is-over");
      $$(".stack-insert", box).forEach(n => n.remove());
      if (!p) return;
      if (p.kind === "stack") {
        moveItemsTo(p.ids, stackDropIndex(ev, box));
        renderStack();
      } else if (p.kind === "word") {
        addItem(p.name, "词（作为 token）");
        renderStack();
        status(`“${p.name}” 作为 token 入栈`, "ok");
      } else if (p.kind === "value") {
        const made = addItem(p.text, reenterable(p.text) ? "从后端栈拖回" : "从后端栈拖回 · 可能不可回读");
        S.sel.clear(); S.sel.add(made.id);
        renderStack();
        status("已拖回主栈", "ok");
      } else if (p.kind === "arg") {
        const f = frameById(p.frame);
        const a = f?.args.find(x => x.id === p.id);
        if (f && a) {
          f.args = f.args.filter(x => x.id !== a.id);
          addItem(a.src, a.note);
          renderStack(); renderFrames();
        }
      } else if (p.kind === "result") {
        const f = frameById(p.frame);
        if (f) returnFrame(f, p.index);
      }
    });
  }

  function wireFramesDrop() {
    const tray = $("#frames");
    tray.addEventListener("dragover", (ev) => {
      if (dragKind() === "word" || dragKind() === "stack") {
        ev.preventDefault();
        $("#frames-list").classList.add("is-over");
      }
    });
    tray.addEventListener("dragleave", () => $("#frames-list").classList.remove("is-over"));
    tray.addEventListener("drop", (ev) => {
      const p = dropPayload(ev);
      $("#frames-list").classList.remove("is-over");
      if (!p) return;
      if (p.kind === "word") {
        const w = S.words.find(x => x.name === p.name);
        if (w) createFrame(w, selectedItems());
      } else if (p.kind === "stack") {
        status("先把词拖到这儿（或用选中项点一个词）", "bad");
      }
      ev.stopPropagation();
    });
  }

  /* ── 菜单 ───────────────────────────────────────────────────────────── */
  function openMenu(anchor, entries) {
    $$(".popmenu").forEach(n => n.remove());
    const r = anchor.getBoundingClientRect();
    const menu = h("div", { class: "popmenu" });
    for (const [label, fn] of entries) {
      menu.append(h("button", {
        class: "popmenu__item", type: "button",
        onclick: () => { menu.remove(); fn(); },
      }, label));
    }
    Object.assign(menu.style, {
      position: "fixed", top: `${r.bottom + 4}px`, left: `${Math.min(r.left, window.innerWidth - 280)}px`,
      zIndex: "50", background: "var(--paper-2)", border: "1px solid var(--line-strong)",
      borderRadius: "var(--radius-m)", boxShadow: "var(--shadow-2)", padding: "4px", display: "grid",
    });
    document.body.append(menu);
    setTimeout(() => document.addEventListener("pointerdown", function off(e) {
      if (!menu.contains(e.target)) { menu.remove(); document.removeEventListener("pointerdown", off); }
    }), 0);
  }

  /* ── 素材：token 切分 / 可回读判定 ──────────────────────────────────── */
  function splitTokens(src) {
    const out = [];
    let buf = "";
    let depth = 0;
    let inStr = false;
    for (let i = 0; i < src.length; i++) {
      const c = src[i];
      if (inStr) {
        buf += c;
        if (c === "\\") { buf += src[++i] ?? ""; continue; }
        if (c === '"') inStr = false;
        continue;
      }
      if (c === '"') { inStr = true; buf += c; continue; }
      if (c === "{" || c === "[" || c === "(") depth++;
      if (c === "}" || c === "]" || c === ")") depth--;
      if (/\s/.test(c) && depth === 0) {
        if (buf) { out.push(buf); buf = ""; }
        continue;
      }
      buf += c;
    }
    if (buf) out.push(buf);
    return out;
  }

  function reenterable(src) {
    const s = String(src).trim();
    if (/^-?\d+(\.\d+)?$/.test(s)) return true;
    if (/^"([^"\\]|\\.)*"$/.test(s)) return true;
    if (/^\{[\s\S]*\}$/.test(s)) return true;
    return false;
  }

  /* ── 流 / 事件 ──────────────────────────────────────────────────────── */
  function pushStream(tag, kind, text) {
    const last = S.streams[S.streams.length - 1];
    if (last && last.tag === tag && last.kind === kind && (kind === "chunk" || kind === "stderr")) {
      last.text += (kind === "stderr" ? "\n" : "") + text;
    }
    else S.streams.push({ tag, kind, text });
    if (S.streams.length > 400) S.streams.splice(0, S.streams.length - 400);
    renderStreams();
  }

  function renderStreams() {
    const box = $("#streams-body");
    box.textContent = "";
    if (!S.streams.length) {
      box.append(h("p", { class: "streams__empty" }, "这里显示 chunk / event / close 与诊断输出（stderr）。"));
      return;
    }
    for (const line of S.streams) {
      box.append(h("div", { class: `stream-line stream-line--${line.kind}` },
        h("span", { class: "stream-line__tag" }, line.kind === "stderr" ? "stderr" : line.tag),
        h("span", { class: "stream-line__text" }, line.text),
      ));
    }
    box.scrollTop = box.scrollHeight;
  }

  function wireEvents() {
    const es = new EventSource("/api/events");
    es.onmessage = (ev) => {
      let m;
      try { m = JSON.parse(ev.data); } catch { return; }
      switch (m.type) {
        case "chunk": pushStream(m.stream || "?", "chunk", m.text || ""); break;
        case "event": pushStream(m.stream || "@?", "event", `工具调用：${m.text ?? JSON.stringify(m)}`); break;
        case "close": pushStream(m.stream || "?", "close", m.ok ? "本轮结束" : `失败（code ${m.code}）：${m.error}`, ); break;
        case "stderr": pushStream("stderr", "stderr", m.text); break;
        case "backend-exit":
          setConn("bad", `后端退出（code ${m.code}）`);
          status("后端已退出，刷新页面或重启桥", "bad");
          break;
        default: break; // result / hello / pong 走 fetch，这里不重复显示
      }
    };
    es.onerror = () => setConn("wait", "事件流断开，重连中…");
  }

  /* ── 顶栏 ───────────────────────────────────────────────────────────── */
  function setConn(stateName, text) {
    const chip = $("#chip-conn");
    chip.dataset.state = stateName;
    chip.textContent = text;
  }

  $("#btn-reset").addEventListener("click", async () => {
    if (!confirm("重置会丢弃整个工作区（字典 + 栈 + agent）。继续？")) return;
    try {
      const msg = await api("/api/reset", {});
      S.stack = []; S.frames = []; S.sel.clear(); S.last = msg; S.activeFrame = null;
      renderStack(); renderFrames(); renderResult();
      status("工作区已重置", "ok");
    } catch (e) { status(String(e), "bad"); }
  });

  $("#btn-cancel").addEventListener("click", async () => {
    try {
      const msg = await api("/api/cancel", {});
      status(`已停 ${msg.stopped ?? 0} 条流（工作区没动）`, "ok");
    } catch (e) { status(String(e), "bad"); }
  });

  const THEMES = ["dusk", "paper", "neon"];
  $("#btn-theme").addEventListener("click", () => {
    const cur = document.documentElement.dataset.theme || "dusk";
    const next = THEMES[(THEMES.indexOf(cur) + 1) % THEMES.length];
    document.documentElement.dataset.theme = next;
    try { localStorage.setItem("rb-theme", next); } catch { /* 隐私模式 */ }
    status(`主题：${next}`, "ok");
  });

  $("#btn-palette-toggle").addEventListener("click", () => togglePalette());
  $("#btn-palette-toggle").setAttribute("aria-expanded", "false");
  $("#btn-clear-streams").addEventListener("click", () => { S.streams = []; renderStreams(); });

  $("#search").addEventListener("input", (ev) => { S.filter.q = ev.target.value; renderWords(); });

  /* 字面量条 */
  function addFromInput() {
    const input = $("#new-literal");
    const v = input.value.trim();
    if (!v) return;
    addItem(v);
    input.value = "";
    renderStack();
    status(`压入：${v}`, "ok");
  }
  $("#btn-add").addEventListener("click", addFromInput);
  $("#new-literal").addEventListener("keydown", (ev) => { if (ev.key === "Enter") { ev.preventDefault(); addFromInput(); } });

  /* 程序区 */
  $("#manual").addEventListener("change", (ev) => {
    S.manual = ev.target.checked;
    $("#program").readOnly = !S.manual;
    if (!S.manual) syncProgram();
  });
  $("#btn-sync").addEventListener("click", () => { S.manual = false; $("#manual").checked = false; $("#program").readOnly = true; syncProgram(); });
  $("#btn-run").addEventListener("click", run);
  $("#btn-raw").addEventListener("click", () => { const r = $("#result-raw"); r.hidden = !r.hidden; });

  /* 键盘 */
  document.addEventListener("keydown", (ev) => {
    const typing = /^(INPUT|TEXTAREA)$/.test(document.activeElement?.tagName || "");
    if ((ev.metaKey || ev.ctrlKey) && ev.key === "Enter") { ev.preventDefault(); run(); return; }
    if (typing) return;
    if (ev.key === "Escape") {
      if ($("#palette").classList.contains("is-open")) togglePalette(false);
      if (S.sel.size) { S.sel.clear(); renderStack(); }
      S.armedFrame = false;
      return;
    }
    if (ev.key === "Delete" || ev.key === "Backspace") {
      if (S.sel.size) { ev.preventDefault(); removeItems([...S.sel]); renderStack(); }
      return;
    }
    if ((ev.metaKey || ev.ctrlKey) && ev.key.toLowerCase() === "d") {
      ev.preventDefault();
      $$("[data-sel='dup']").forEach(b => b.click());
    }
  });

  /* ── 启动 ───────────────────────────────────────────────────────────── */
  async function boot() {
    try {
      const theme = localStorage.getItem("rb-theme");
      if (theme) document.documentElement.dataset.theme = theme;
    } catch { /* 忽略 */ }

    $("#program").readOnly = true;
    wireStackDrop();
    wireFramesDrop();
    renderStack();
    renderFrames();
    renderStreams();

    try {
      const [hello, words] = await Promise.all([api("/api/hello"), api("/api/words")]);
      if (hello.type === "hello" && hello.protocol === 1) {
        setConn("ok", "已连接");
        $("#chip-version").textContent = hello.version;
        status(`后端就绪 · ${hello.version}`, "ok");
      } else {
        setConn("bad", "协议不匹配");
      }
      S.catalog = words;
      S.words = flatten(words);
      renderLayers();
      renderWords();
      $("#chip-count").textContent = `${S.words.length} 词 · ${words.groups.length} 层`;
    } catch (e) {
      setConn("bad", "桥不通");
      status(`接不上桥：${e}（先跑 python3 web/bridge.py）`, "bad");
    }
    wireEvents();
  }

  document.addEventListener("DOMContentLoaded", boot);
})();
