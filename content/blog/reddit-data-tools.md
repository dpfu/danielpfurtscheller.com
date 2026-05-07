---
title: "Reddit data tools"
description: "Eine technische Notiz zum Reddit Data Tool: öffentliche Threads als JSON lesen, Kommentare flachziehen und die Grenzen des einfachen Zugangs sichtbar machen."
kicker: Blog
date: 2026-05-07
lastmod: 2026-05-07
url: "/blog/reddit-data-tools/"
---

Reddit hat noch etwas von einem älteren Web: Man klickt auf eine Seite, sieht viel Interface, und darunter liegt trotzdem oft ein ziemlich direkt lesbarer Datenkörper.

Wenn man eine öffentliche Kommentar-URL hat, kann man in vielen Fällen einfach `.json` anhängen und bekommt statt der HTML-Seite eine JSON-Antwort zurück. Das ist kein Geheimtrick und auch kein Ersatz für sauber registrierte API-Nutzung. Aber für einzelne Threads reicht es manchmal: für Seminarmaterial, eine schnelle Fallanalyse, eine explorative Notiz.

Dafür habe ich mein [Reddit Data Tool](https://dpfu.github.io/reddit-data-tool/) wieder aktualisiert. Wer nur einen Thread exportieren will, kann dort eigentlich schon aufhören zu lesen. Der Rest hier ist die technische und methodische Randnotiz dazu.

Aus einer normalen Reddit-URL wie dieser:

```
https://www.reddit.com/r/TikTokCringe/comments/gbkmga/godlevel_shitpost/
```

wird eine JSON-URL:

```
https://www.reddit.com/r/TikTokCringe/comments/gbkmga/godlevel_shitpost.json?raw_json=1
```

Der Zusatz `raw_json=1` ist wichtig. In der [Reddit-API-Dokumentation](https://www.reddit.com/dev/api/) steht, dass JSON-Antworten aus Legacy-Gründen bestimmte Zeichen wie `<`, `>` und `&` als HTML-Entities ausgeben können. Mit `raw_json=1` ist der Text näher an dem, was man für Export, Lektüre oder einfache Textanalyse braucht.

Im Browser sieht der Zugriff ungefähr so aus:

```
const postUrl = 'https://www.reddit.com/r/TikTokCringe/comments/gbkmga/godlevel_shitpost/';

const jsonUrl = new URL(postUrl);
jsonUrl.pathname = `${jsonUrl.pathname.replace(/\/+$/g, '')}.json`;
jsonUrl.searchParams.set('raw_json', '1');

const response = await fetch(jsonUrl);

if (!response.ok) {
  throw new Error(`Reddit returned HTTP ${response.status}`);
}

const data = await response.json();
```

Bei Kommentar-Threads bekommt man in der Regel zwei Listings:

```
const [postListing, commentListing] = data;

const post = postListing.data.children[0].data;
const comments = commentListing.data.children;
```

Das erste Listing enthält den Post selbst: Titel, Autor, Subreddit, Score, Zeitstempel, Permalink und die von Reddit gemeldete Kommentarzahl. Das zweite Listing enthält den Kommentarbaum.

Sehr grob sieht diese Struktur so aus:

```
[
  {
    kind: 'Listing',
    data: {
      children: [
        { kind: 't3', data: { title, author, subreddit, score, num_comments } }
      ]
    }
  },
  {
    kind: 'Listing',
    data: {
      children: [
        {
          kind: 't1',
          data: {
            body,
            author,
            score,
            created_utc,
            replies: {
              data: {
                children: [
                  { kind: 't1', data: { body, author, score } }
                ]
              }
            }
          }
        }
      ]
    }
  }
]
```

Die Kürzel sind Reddit-Thing-Typen: `t3` ist ein Link oder Post, `t1` ist ein Kommentar. Für einfache Auswertungen reicht es meistens, durch `commentListing.data.children` zu gehen und rekursiv in `comment.data.replies.data.children` weiterzulaufen.

Ein stark vereinfachter Walker könnte so aussehen:

```
function flattenComments(children, prefix = [], state = { skipped: 0 }) {
  const rows = [];
  let sibling = 0;

  for (const child of children ?? []) {
    if (!child || child.kind === 'more') {
      state.skipped += Number(child?.data?.count ?? 0);
      continue;
    }

    if (child.kind !== 't1') continue;

    sibling += 1;
    const comment = child.data;
    const number = [...prefix, sibling];

    rows.push({
      number: number.join('.'),
      level: number.length,
      id: comment.id,
      parentId: comment.parent_id,
      author: comment.author || '[deleted]',
      body: comment.body || '[deleted]',
      score: comment.score ?? 0,
      createdUtc: comment.created_utc
    });

    const replies = comment.replies?.data?.children ?? [];
    rows.push(...flattenComments(replies, number, state));
  }

  return rows;
}
```

Damit bekommt man eine Tabelle, in der `1`, `1.1`, `1.1.1`, `2` usw. die Position im Kommentarbaum markieren. Das ist keine Reddit-ID. Aber zum Lesen, Sortieren, Zitieren, Exportieren und Visualisieren ist so eine laufende Nummer oft praktischer als die interne ID.

Der Knackpunkt sind große Threads. Reddit liefert nicht immer alle Kommentare direkt aus. Stattdessen tauchen Platzhalter auf:

```
{
  kind: 'more',
  data: {
    count: 37,
    children: ['abc123', 'def456']
  }
}
```

Diese `more`-Objekte stehen für Kommentare, die in der ersten Baumansicht ausgelassen wurden. In der offiziellen API gibt es dafür `/api/morechildren`; laut Dokumentation holt dieser Endpoint zusätzliche Kommentare zu solchen Platzhaltern, bis zu 100 auf einmal. Genau dort endet aber der einfache `.json`-Zugriff. Ab diesem Punkt ist man schnell bei registriertem API-Client, OAuth, Rate Limits und Nutzungsbedingungen.

Man kann Reddit-JSON auch kurz mit `curl` ansehen:

```
curl -L \
  -H 'User-Agent: research-note:reddit-json-demo:0.1 (by /u/YOUR_USERNAME)' \
  'https://www.reddit.com/r/TikTokCringe/comments/gbkmga/godlevel_shitpost.json?raw_json=1'
```

Für Skripte ist ein beschreibender User-Agent wichtig. In den [Reddit Data API notes](https://support.reddithelp.com/hc/en-us/articles/16160319875092-Reddit-Data-API-Wiki) steht außerdem deutlich, dass Clients mit einem registrierten OAuth-Token arbeiten sollen und dass nicht identifizierte Zugriffe gedrosselt oder blockiert werden können. Für browserbasierte Tools ist das ein strukturelles Problem: Der Browser kann den User-Agent nicht frei setzen, und direkter Zugriff kann jederzeit an CORS, Rate Limits, Blocking oder Änderungen bei Reddit selbst scheitern.

Das ist auch methodisch die richtige Grenze. Der `.json`-Weg ist gut für einzelne öffentliche Threads. Er ist nicht gut für Vollerhebungen, historische Massendaten, kontinuierliches Monitoring oder alles, was heimlich große Mengen Plattformdaten einsammelt. Reddit beschreibt in der [Public Content Policy](https://support.reddithelp.com/hc/en-us/articles/26410290525844-Public-Content-Policy), dass öffentliche Posts und Kommentare grundsätzlich ohne Account sichtbar sind. Gleichzeitig macht Reddit dort klar: Öffentlich sichtbar heißt nicht beliebig massenhaft auslesbar. Die [Developer Terms](https://redditinc.com/policies/developer-terms) und [Data API Terms](https://redditinc.com/policies/data-api-terms) sind für systematische Forschung deshalb keine Fußnoten, sondern Teil der Methode.

Für mich ist der brauchbare Mittelweg: kleine, transparente Werkzeuge für einzelne Fälle bauen, aber nicht so tun, als wäre das eine robuste Infrastruktur für Reddit als Gesamtkorpus.

Genau so funktioniert das [Reddit Data Tool](https://dpfu.github.io/reddit-data-tool/). Es nimmt eine öffentliche Reddit-Kommentar-URL, normalisiert sie, hängt `.json?raw_json=1` an, lädt die Antwort im Browser, extrahiert Post-Metadaten und zieht den Kommentarbaum zu einer Tabelle flach. `kind: "more"`-Platzhalter werden nicht heimlich nachgeladen, sondern gezählt und als Warnung angezeigt. Danach kann man die Daten als CSV herunterladen, als HTML kopieren, filtern, sortieren und sich in einer kompakten Thread Map einen Überblick über die Struktur verschaffen.

Der Code liegt auf [GitHub](https://github.com/dpfu/reddit-data-tool), die Software ist über Zenodo zitierbar: [10.5281/zenodo.15024196](https://doi.org/10.5281/zenodo.15024196). Kein großes Scraping-Framework, sondern ein kleines Werkzeug für den Moment, in dem man einen konkreten Reddit-Thread genauer anschauen will.
