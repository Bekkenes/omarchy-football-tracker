# Third-party notices

## Lucide icons

The files under `icons/` are derived from [Lucide](https://lucide.dev/)
(`goal.svg`, `whistle.svg`, `rectangle-vertical.svg` → `card-*.svg`,
`repeat-2.svg` → `substitution.svg`, `calendar-clock.svg` → `calendar.svg`,
`volleyball.svg` → `ball.svg`, `target.svg` → `penalty-miss.svg`), recolored
per event type. Lucide is distributed under the ISC License:

```
ISC License

Copyright (c) 2026 Lucide Icons and Contributors

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
```

## Data source

Match, fixture, and event data is fetched at runtime from
[API-Football](https://www.api-football.com/) (api-sports.io), a
third-party service requiring the user's own free API key. No API-Football
code is bundled in this repository; this is a runtime data dependency only.
This project is not affiliated with or endorsed by API-Football.
