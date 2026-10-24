# Nexus TV for Samsung Frame (Tizen)

The same app as the Apple TV and Mac versions, as a Tizen web app for Samsung TVs (written for the old WebKit browser those TVs run: plain ES5, absolute layout).

- `index.html`, `js/`, `css/`, `img/`: the app.
- `config.xml`: the Tizen widget (app id, name "Nexus TV", icon).
- `tools/build_data.py`: builds the channel, film and series data files into `data/` from your own source (not in the repo).
- `tools/bundle_logos.py <cc>`: copies a country's channel logos into `img/logos/<cc>/` so they show when a logo server does not answer.
- `tools/package.sh`: packages with your Samsung certificate profile and installs on the TV (`TV=<your-frame-ip> tools/package.sh`).

Not in the repo: `data/` (your sources and lists), signing files, and the copied logos.
