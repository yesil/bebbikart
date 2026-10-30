// Hello-world phone site (M0). WS4 replaces this with the real screens.
import { ABILITIES, DEFAULT_BUILD, starsLeft } from "@bebbikart/shared";
import { html } from "htm/preact";
import { render } from "preact";
import { useEffect, useState } from "preact/hooks";

function App() {
  const [server, setServer] = useState("checking…");

  useEffect(() => {
    fetch("/api/health")
      .then((res) => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return res.json();
      })
      .then(() => setServer("connected"))
      .catch((err) => setServer(`not reachable (${err.message})`));
  }, []);

  const stars = DEFAULT_BUILD.stars;
  return html`
    <h1>BebbiKart</h1>
    <p>Server: ${server}</p>
    <ul>
      ${ABILITIES.map((a) => html`<li key=${a}>${a}: ${"★".repeat(stars[a])}</li>`)}
    </ul>
    <p>Stars left: ${starsLeft(stars)}</p>
  `;
}

render(html`<${App} />`, document.getElementById("app"));
