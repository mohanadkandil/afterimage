# Litt

Find something you saw on your Mac, and give your agent the context to help you with it.

## Why I built it

I wanted to ask, "How could I improve my workflow this week?" and give my agent something concrete to look at. That context lives across browser tabs and terminals. Reconstructing it all by hand is work in itself.

Litt saves screen moments locally. You can search the text inside them, scroll back through your day, and open the frame you need. A terminal-capable agent can read the same archive when you ask it to.

## What that could look like

These are fictional examples, not real activity or measured outcomes. Litt provides search and a timeline. The conversational answers below would come from an agent using its CLI.

### Review my week

> How could I improve my workflow this week? Use my Litt history.

An agent could look through the week's saved frames and answer:

> The same dependency error appears in your Monday and Wednesday recordings. I'd start by turning that fix into a setup script. You also revisited the same API reference several times. Keeping a short project note with those examples might save some searching.

It should cite the timestamps and frames behind each observation. Screen history gives it evidence to discuss with you; it doesn't tell it why you switched apps or whether that time was wasted.

### Find something I read

> What was that article about robot localization I had open yesterday?

The agent searches the recorded text and returns the matching page title, timestamp and screenshot. You can inspect what was actually on screen, even if you've closed the tab.

### Pick up unfinished work

> Where did I leave off with the build yesterday?

A possible answer:

> Your last saved terminal frame shows a missing-header error. The next frame has the dependency's installation instructions open. I'd check whether that dependency is installed before rerunning the build.

The agent should say when recordings are missing.

## Try it

On a Mac with the build tools installed:

```sh
./scripts/build.sh
./litt
```

Complete setup, grant Screen Recording permission, then press **Start recording**. The app starts paused. Use the gear to exclude apps or choose how long to keep history.

For agent use, install the terminal launcher with `./scripts/install.sh` and give your agent the [archive skill guide](docs/AGENT-SKILL.md). It needs local terminal access; a chat window alone cannot read the archive. If you use a cloud agent, the history it reads becomes part of that agent's conversation.

## Under the hood

SwiftUI handles the Mac interface. C++ manages the archive, change detection, search and storage. Apple Vision reads the visible text, and short HEVC chunks keep recordings smaller.

Our 182-moment archive took **13.4 MB**, excluding previews. HEVC is lossy; the original searchable text is retained. [Measurements and tradeoffs](docs/hevc-storage.md).

[Setup, commands and development](GUIDE.md) · [Architecture](docs/ARCHITECTURE.md) · [MIT license](LICENSE)
