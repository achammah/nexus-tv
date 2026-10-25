# Design picks (owner-approved)

## Settings (both TVs), 2026-10-25
picked-layout: two panes, 7 sections left with live summaries, grouped rows right (value, pills, toggle, chevron), built from the full settings inventory; owner: "Think of all you should be able to manage (account, choosing channels, updating views, adding lists, etc.)"; card pick on round 3: "Yes, build it"
picked-style: the app's own dark look as rendered in design/settings/s1.html to s4.html (white selection pill, white focus outline, round flags, channel logos); owner on the earlier directions: "Still none are good. This doesn't feel like a setting screen."; card pick on round 3: "Yes, build it"
- Layout pick: two panes. Left column of 7 sections (Account & sources, Channels, Home & views, Lists, Playback & subtitles, Data & storage, About), each with a live summary. Right pane: small-caps section headers, grouped rows with label and help line left, value / pills / toggle / chevron right. Crumb "Settings › section".
- Look pick: the app's own look (dark, rounded groups, white selection pill, white focus outline, round flags, channel logos), as rendered in `/Users/assem/nexus/nexus-organisation/work/frame-tv/design/settings/s1.html` to `s4.html` (renders s1.png to s4.png).
- Owner's words: round 1 (grey wireframes A/B/C) "Expecting something MUCH MUCH Better here"; round 2 (three hi-fi directions) "Still none are good. This doesn't feel like a setting screen. Think of all you should be able to manage (account, choosing channels, updating views, adding lists, etc.)"; round 3 (s1 to s4, built from the full settings inventory) "Yes, build it".
- Applies to: tvOS SettingsView (rebuild on branch tv-settings-2) and the Frame js/settings.js (branch settings-b). The Mac keeps its Settings pane.

## Earlier picks (recorded elsewhere)
- Live page: design A shelves, round circle-flags, pinned banners (owner: "works all").
- Opening: the native vector animation, plays to its end, 0.3 s hold, then Home fades in ("Finish then fade into the home").
- Channel loading: the channel bar itself is the loading state (logo, name, LIVE line stay put; "Tuning in" and the progress line go).

## Player (2026-10-25)
picked-layout: Player bar A "I like player bar"; episodes as E2 "E2 is good"; audio and subtitles stay small popups "keep the small menu popup for audio dub and subtitles and not the drawer"; a long press on a show "long click on a show to go to show or specific episode number"
picked-style: smaller bar and compact end card "make the whole card smaller please"; cue "Goal is to have predicition of next episode per show"; "Next episode" button next to Episodes near the end, "the skip is recorded if it's towards end of episode"; owner: "Ok but also..." (build approved 2026-10-25)
boards: ~/nexus/nexus-organisation/work/frame-tv/design/player/ (player-a, player-e2, player-m1, player-m1b, player-n3, player-n4, player-d)
rules:
- Bar: 10 s back, play/pause, 10 s forward, Audio <language>, Subtitles <language>, right side Episodes "n of m"; near the end (credits cue reached) a "Next episode" button appears left of Episodes. Buttons 56 px, labels 20 px.
- Track labels: language from the tag (or detected for subtitles), then the discriminator (Descriptive, Commentary, Original, SDH, Forced, 5.1 or stereo, codec); never "English 1 / English 2"; no tag: "Track N · unknown language". Flags as circle-flags.
- Episodes: focusing the button slides the strip up (season row, watched marks, progress fill, playing one centred); Left is the previous, Right the next, OK plays, Back closes; last card "Season N+1 ›".
- End card: compact row bottom right: thumb, "NEXT · E4 · 57 MIN", title, 10 s ring; OK plays, Back keeps the credits. Cue order: per-show learned credits start (median of Next presses and watch-to-end, keyed by series id); else subtitles quiet 45 s in the last 6 min; else last 2 % (≥20 s). Ring only when the previous episode reached its card without a seek; no timer on the last episode (offers next season or Home).
- Still watching: small toast at an episode start after 2 autoplayed episodes with no key; skipped if a key in the last 90 min or the Mac window is active; no answer in 60 s pauses, keeps position, releases the stream; after two quick Keep watching, waits 4 episodes.
- Long press / right-click on a show: Resume En (time), Open the show, Go to episode (season + episode chips), Add to My List, Move, Hide row.
