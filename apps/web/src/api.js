// REST helpers and the WebSocket client with auto-reconnect.
import { makeMsg } from "@bebbikart/shared";

export class ApiError extends Error {
  constructor(code, message, status) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

export async function api(method, path, body) {
  const res = await fetch(path, {
    method,
    credentials: "same-origin",
    headers: body !== undefined ? { "content-type": "application/json" } : {},
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  if (res.status === 204) return null;
  const data = await res.json().catch(() => ({}));
  if (!res.ok)
    throw new ApiError(
      data.error?.code ?? "generic",
      data.error?.message ?? res.statusText,
      res.status,
    );
  return data;
}

/** Multipart upload with progress (fetch has no upload progress). */
export function uploadDrawings(character, vehicle, onProgress) {
  return new Promise((resolve, reject) => {
    const form = new FormData();
    form.append("character", character, "character.jpg");
    form.append("vehicle", vehicle, "vehicle.jpg");
    const xhr = new XMLHttpRequest();
    xhr.open("POST", "/api/players/me/drawings");
    xhr.upload.onprogress = (e) => e.lengthComputable && onProgress(e.loaded / e.total);
    xhr.onload = () => {
      let data = {};
      try {
        data = JSON.parse(xhr.responseText);
      } catch {}
      if (xhr.status >= 200 && xhr.status < 300) resolve(data);
      else
        reject(
          new ApiError(
            data.error?.code ?? "generic",
            data.error?.message ?? "Upload failed",
            xhr.status,
          ),
        );
    };
    xhr.onerror = () => reject(new ApiError("generic", "Upload failed", 0));
    xhr.send(form);
  });
}

/** Phone WS: sends hello on every (re)connect, calls onMessage(type, payload), onStatus(bool). */
export function connectWs({ onMessage, onStatus }) {
  let ws;
  let delay = 500;
  let closed = false;
  function open() {
    const proto = location.protocol === "https:" ? "wss" : "ws";
    ws = new WebSocket(`${proto}://${location.host}/ws`);
    ws.onopen = () => {
      delay = 500;
      ws.send(JSON.stringify(makeMsg("phoneToServer", "hello", { role: "phone" })));
      onStatus(true);
    };
    ws.onmessage = (e) => {
      try {
        const m = JSON.parse(e.data);
        onMessage(m.type, m.payload);
      } catch (err) {
        console.warn("bad ws message", err);
      }
    };
    ws.onclose = () => {
      onStatus(false);
      if (closed) return;
      setTimeout(open, delay);
      delay = Math.min(delay * 2, 5000);
    };
  }
  open();
  // Phones drop sockets when the screen locks; reconnect right away when they come back.
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible" && ws.readyState > 1) open();
  });
  return {
    send(type, payload) {
      if (ws.readyState === 1) ws.send(JSON.stringify(makeMsg("phoneToServer", type, payload)));
    },
    close() {
      closed = true;
      ws.close();
    },
  };
}
