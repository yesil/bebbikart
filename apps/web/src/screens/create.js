import { html } from "htm/preact";
import { useEffect, useState } from "preact/hooks";
import { api, uploadDrawings } from "../api.js";
import { COPY } from "../copy.js";
import { downscale } from "../image.js";

// Photos survive a retake of just one image (rejected → retake the failing one).
const photos = { character: null, vehicle: null };
// Design pipeline steps, in order (JOB_STAGES in the shared package).
const STAGES = ["looking", "designing", "critiquing", "refining"];

function PhotoButton({ kind, label, file, onFile }) {
  const [url, setUrl] = useState(null);
  useEffect(() => {
    if (!file) return setUrl(null);
    const u = URL.createObjectURL(file);
    setUrl(u);
    return () => URL.revokeObjectURL(u);
  }, [file]);
  return html`
    <label class=${`photo ${file ? "has" : ""}`}>
      ${url ? html`<img src=${url} alt="" />` : html`<span class="big">${kind === "character" ? "🧒" : "🚗"}</span>`}
      <span class="label">${file ? COPY.create.retake : label}</span>
      <input
        type="file"
        accept="image/*"
        capture="environment"
        onChange=${async (e) => {
          const input = e.currentTarget;
          const f = input.files?.[0];
          input.value = "";
          if (f) onFile(await downscale(f));
        }}
      />
    </label>
  `;
}

export function Create({ ctx, only }) {
  const { s, dispatch } = ctx;
  const me = s.me;
  const [name, setName] = useState(me?.nickname ?? "");
  const [files, setFiles] = useState({ ...photos });
  const [progress, setProgress] = useState(null);
  const failed = me?.job?.status === "failed";

  const setFile = (kind) => (f) => {
    photos[kind] = f;
    setFiles({ ...photos });
  };
  const ready = name.trim().length > 0 && files.character && files.vehicle;

  async function submit(e) {
    e.preventDefault();
    if (!ready) return dispatch({ type: "toast", text: COPY.create.needBoth });
    try {
      setProgress(0);
      if (!me)
        dispatch({ type: "me", me: await api("POST", "/api/players", { nickname: name.trim() }) });
      else if (name.trim() !== me.nickname)
        dispatch({
          type: "me",
          me: await api("PATCH", "/api/players/me", { nickname: name.trim() }),
        });
      await uploadDrawings(files.character, files.vehicle, setProgress);
      // player.updated (processing) arrives over WS; refresh in case the socket is down.
      const st = await api("GET", "/api/state");
      if (st.me) dispatch({ type: "me", me: st.me });
      dispatch({ type: "redo", on: false });
    } catch (err) {
      dispatch({ type: "toast", text: COPY.errors[err.code] ?? err.message });
    } finally {
      setProgress(null);
    }
  }

  const kinds = only ? [only] : ["character", "vehicle"];
  return html`
    <form class="card create" onSubmit=${submit}>
      <h1>${COPY.create.title}</h1>
      ${
        failed
          ? html`<div class="error-box">
              <b>${COPY.making.failed}</b>
              <div>${COPY.making.failedHint}</div>
              <code>${me.job.error ?? "unknown error"}</code>
            </div>`
          : null
      }
      <label class="field">
        <span>${COPY.create.nameLabel}</span>
        <input
          value=${name}
          maxlength="16"
          placeholder=${COPY.create.namePlaceholder}
          autocomplete="off"
          onInput=${(e) => setName(e.currentTarget.value)}
        />
      </label>
      <div class="photos">
        ${kinds.map(
          (k) => html`<${PhotoButton}
            key=${k}
            kind=${k}
            label=${k === "character" ? COPY.create.driver : COPY.create.ride}
            file=${files[k]}
            onFile=${setFile(k)}
          />`,
        )}
      </div>
      <p class="muted small">${COPY.create.tip}</p>
      ${
        progress !== null
          ? html`<div class="progress"><div style=${{ width: `${Math.round(progress * 100)}%` }}></div></div>
              <p class="muted small">${COPY.create.uploading}</p>`
          : html`<button class="primary" disabled=${!ready}>${COPY.create.submit}</button>`
      }
      ${
        s.redo && me?.status === "ready"
          ? html`<button type="button" class="ghost" onClick=${() => dispatch({ type: "redo", on: false })}>
              ${COPY.create.cancel}
            </button>`
          : null
      }
    </form>
  `;
}

export function Making({ ctx, review }) {
  const job = ctx.s.me?.job;
  const [tick, setTick] = useState(0);
  useEffect(() => {
    const t = setInterval(() => setTick((n) => n + 1), 2500);
    return () => clearInterval(t);
  }, []);
  const stage = job?.status === "designing" ? job.stage : undefined;
  const text = review
    ? COPY.making.review
    : job?.status === "queued"
      ? COPY.making.queued
      : stage
        ? COPY.making.stages[stage]
        : tick % 2 === 0
          ? COPY.making.designing
          : COPY.making.building;
  const step = stage ? STAGES.indexOf(stage) : -1;
  const drawing = ctx.s.me?.asset?.drawings?.character;
  return html`
    <div class="card center making">
      ${drawing ? html`<img class="drawing" src=${drawing} alt="" />` : null}
      <div class="spinner"></div>
      <h2>${text}</h2>
      ${
        step >= 0
          ? html`<div class="stages">${STAGES.map((st, i) => html`<i class=${i < step ? "done" : i === step ? "on" : ""}></i>`)}</div>`
          : null
      }
      ${step >= 0 ? html`<p class="hint">${COPY.making.slow}</p>` : null}
    </div>
  `;
}

export function Rejected({ ctx }) {
  const job = ctx.s.me?.job ?? {};
  const kind = job.rejectedImage ?? "character";
  // Without the other photo in memory (e.g. after a reload) the kid retakes both.
  const other = kind === "character" ? "vehicle" : "character";
  const only = photos[other] ? kind : undefined;
  if (only) photos[kind] = null;
  return html`
    <div class="card center">
      <div class="big">🙈</div>
      <p class="lead">${COPY.reject[job.rejectReason] ?? COPY.reject.unreadable}</p>
    </div>
    <${Create} ctx=${ctx} only=${only} />
  `;
}

export function Reveal({ ctx }) {
  const { s, dispatch } = ctx;
  const me = s.me;
  const spec = me.asset.spec;
  const hero = me.asset.renders?.hero;
  const [busy, setBusy] = useState(false);
  async function reroll() {
    setBusy(true);
    try {
      await api("POST", "/api/players/me/reroll");
    } catch (err) {
      dispatch({ type: "toast", text: COPY.errors[err.code] ?? err.message });
    }
    setBusy(false);
  }
  return html`
    <div class="card center reveal">
      <div class="reveal-art">
        <img class="drawing small" src=${me.asset.drawings.character} alt="" />
        ${hero ? html`<img class="hero" src=${hero} alt="" />` : html`<img class="drawing" src=${me.asset.drawings.vehicle} alt="" />`}
      </div>
      <h1>${spec.title}!</h1>
      ${spec.tagline ? html`<p class="tagline">“${spec.tagline}”</p>` : null}
      <p class="words">${spec.personality.join(" · ")}</p>
      <p class="lead">👀 ${COPY.reveal.lookUp}</p>
      <button class="primary" onClick=${() => dispatch({ type: "revealSeen", id: me.asset.packageId })}>
        ${COPY.reveal.go}
      </button>
      <button class="ghost" disabled=${busy} onClick=${reroll}>${COPY.reveal.another}</button>
    </div>
  `;
}
