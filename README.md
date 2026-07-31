# Coralie Collection

This repository is a collection of small HTML applications built for Coralie. Each app is designed to remain easy to open, inspect, share, and run, with most of its interface and application logic contained in a single HTML file.

Open `index.html` to browse the collection. The catalogue is defined in `pages.json`.

## What is Coralie?

Coralie is a host API for portable HTML applications. A page talks to the public `window.Coralie` interface instead of depending directly on a particular browser or a private native bridge. The same page can therefore run with the browser adapter in `Coralie/v2/host.js` or inside a compatible Coralie Android host.

Coralie API v2 provides capabilities such as:

- **Mesh messaging** — connect peers by public key and exchange application messages over peer-to-peer data channels.
- **Portable storage** — save and retrieve key/value data through the host.
- **HTTPS requests** — make normalized external requests without tying page code to one platform's networking implementation.
- **Timers** — queue, cancel, and inspect host-managed timers.

Pages use only the capabilities they need. Their entries in `pages.json` describe those requirements.

## Further Coralie documentation

For a comprehensive guide to the browser runtime, Runtime API v2, Android compatibility, networking model, security considerations, and development workflow, see the upstream [Coralie Core repository](https://github.com/JaredXwos/Coralie_Core).

This collection includes the built browser adapter needed by its pages. Developers changing Coralie itself should work from the upstream runtime source rather than editing the generated `Coralie/v2/host.js` bundle here.

## Included pages

| Page | Description | Capabilities |
| --- | --- | --- |
| `rbw.html` | Really Boring Website, a multiplayer word game. | Mesh, storage, HTTP |
| `room.html` | A diagnostics room for connecting peers and testing messages. | Mesh, storage |
| `cve-tracker.html` | A CVE feed with locally saved bookmarks. | Storage, HTTP |
| `boggle.html` | Boggle with solo and Coralie mesh multiplayer modes. | Mesh, storage |

## Running the collection

For a quick look, open `index.html` in a modern browser. If the browser restricts networking or storage for local files, serve the directory locally instead:

```sh
python -m http.server 8000
```

Then visit `http://localhost:8000/`.

The browser implementation creates `window.Coralie` when a page loads:

```html
<script src="./Coralie/v2/host.js"></script>
```

Inside the Coralie Android environment, the host serves or intercepts that same adapter path and exposes the compatible public API.

## Adding a page

1. Add the HTML file at the repository root.
2. Load `./Coralie/v2/host.js` before using the Coralie API.
3. Declare only the Coralie capabilities the page requires.
4. Add its title, description, filename, build identifier, capabilities, and category to `pages.json`.

Keep page code on the public `window.Coralie` API so it remains portable between supported hosts.
