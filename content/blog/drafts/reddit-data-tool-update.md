---
title: "Ein kleines Update fürs Reddit Data Tool"
description: "Kurze Notiz zum Reddit Data Tool: ein browserbasiertes Werkzeug für einzelne Reddit-Threads, mit neuen Export- und Überblicksfunktionen."
kicker: Blog
date: 2026-05-05
lastmod: 2026-05-05
draft: true
url: "/blog/reddit-data-tool-update/"
---

Ich habe vor einiger Zeit ein kleines Werkzeug gebaut, das mir beim Arbeiten mit Reddit-Threads hilft: das [Reddit Data Tool](https://dpfu.github.io/reddit-data-tool/). Es ist kein großes Forschungsinfrastrukturprojekt, sondern eher ein nützliches Arbeitsding für den Moment, in dem man einen konkreten Thread vor sich hat und ihn etwas besser ansehen, exportieren oder archivieren möchte.

Jetzt habe ich ein Update hochgeladen. Der Code liegt weiterhin auf [GitHub](https://github.com/dpfu/reddit-data-tool), die aktuelle Version ist auch auf [Zenodo](https://doi.org/10.5281/zenodo.15024197) zitierbar.

Die Grundidee ist weiterhin ziemlich schlicht: Man fügt die URL eines öffentlichen Reddit-Posts ein, das Tool lädt die dazugehörigen öffentlichen JSON-Daten im Browser und macht daraus eine besser nutzbare Ansicht. Es gibt Metadaten zum Post, eine Kommentar-Tabelle, CSV-Export, HTML-Kopie und eine kleine Thread Map, mit der man die Struktur eines Kommentarbaums überblicken kann. Gerade diese Thread Map war mir beim Update wichtig: weniger als schöne Visualisierung für Präsentationsfolien, mehr als schnelle Orientierung in verschachtelten Diskussionen.

Technisch ist das Ganze bewusst einfach gehalten. Es läuft komplett clientseitig als statische Website auf GitHub Pages. Es braucht keinen Server, keine Datenbank, keine Anmeldung, keine OAuth-App und keinen persönlichen API-Key. Die Daten bleiben im Browser und werden nicht an einen Backend-Dienst von mir geschickt. Das macht das Tool niedrigschwellig und transparent, setzt ihm aber natürlich auch klare Grenzen.

Der konkrete Zugriff ist dieser: Aus einer öffentlichen Reddit-Kommentar-URL macht das Tool eine JSON-Adresse, also grob gesagt `.../comments/... .json?raw_json=1`. `raw_json=1` ist ein kleiner, aber wichtiger Zusatz, weil Reddit in der API-Dokumentation darauf hinweist, dass bestimmte Zeichen in JSON-Antworten sonst aus Legacy-Gründen HTML-escaped werden. Das Tool nutzt also einen öffentlichen JSON-Blick auf eine einzelne Thread-Ansicht, nicht die vollständige OAuth-API mit registriertem Client.

Und diese Grenzen sind inzwischen wichtiger als früher. Reddit ist zwar weiterhin in weiten Teilen öffentlich sichtbar; in der [Public Content Policy](https://support.reddithelp.com/hc/en-us/articles/26410290525844-Public-Content-Policy) beschreibt Reddit öffentliche Posts, Kommentare, Nutzernamen, Profile, Karma-Werte und Metadaten ausdrücklich als öffentlich zugängliche Inhalte. Gleichzeitig ist öffentlich sichtbar nicht dasselbe wie beliebig massenhaft sammelbar. Reddit zieht seit den API-Änderungen und der neuen Datenpolitik deutlichere Linien zwischen normalem Zugriff, Forschung, kommerzieller Nutzung, Scraping und großskaliger Datenauswertung.

Das merkt man an mehreren Stellen: Die [Data API](https://support.reddithelp.com/hc/en-us/articles/16160319875092-Reddit-Data-API-Wiki) hat Limits, die [Developer Terms](https://redditinc.com/policies/developer-terms) unterscheiden sehr klar zwischen erlaubten und zustimmungspflichtigen Nutzungen, und mit dem [robots.txt-Update von 2024](https://redditinc.com/news/robot-txt-update) hat Reddit noch einmal betont, dass unbekannte Bots und Crawler eingeschränkt oder blockiert werden können. Das ist auch Teil eines größeren Plattformtrends: Offene, bequeme Zugänge werden seltener, weil Plattformen ihre Daten stärker kontrollieren, lizenzieren und gegen automatisiertes Einsammeln absichern.

Für mein Tool heißt das: Es ist ein kleines Werkzeug für einzelne öffentliche Threads, nicht für das heimliche Absaugen großer Datenmengen. Es ersetzt keine offizielle API-Nutzung, keine saubere Forschungsdatenstrategie und auch kein langfristig stabiles Korpus-Setup. Es löst auch nicht alle technischen Details, die Reddit selbst offen lässt: Wenn ein Thread sehr groß ist, liefert Reddit in der Kommentarstruktur oft `kind: "more"`-Objekte. Das sind Platzhalter für weitere Kommentare, die man mit zusätzlichen API-Mechanismen wie `/api/morechildren` nachladen müsste. Genau das macht dieses Tool bewusst nicht. Es zeigt stattdessen an, wenn solche Platzhalter übersprungen wurden.

Auch sonst gilt: Gelöschte, private, quarantined, altersbeschränkte oder anderweitig nicht öffentlich erreichbare Inhalte sind nicht Teil des Exports. Und wenn Reddit direkte Browser-Zugriffe drosselt, blockiert oder die JSON-Ausgabe verändert, kann ein clientseitiges Tool wie dieses daran wenig ändern. In den offiziellen Hinweisen zur Data API schreibt Reddit inzwischen ausdrücklich, dass unbekannte oder nicht per OAuth authentifizierte Zugriffe gedrosselt oder blockiert werden können.

Gerade deshalb mag ich diesen Ansatz aber weiterhin. Für explorative Arbeit, Seminare, kleine Fallstudien oder methodische Notizen ist es hilfreich, ein einzelnes Beispiel schnell in eine Form zu bringen, mit der man arbeiten kann. Man sieht Kommentarhierarchien, Scores, Zeitstempel und Antwortbezüge nicht nur als endlosen Scroll-Verlauf, sondern als Material, das man sortieren, filtern, exportieren und beschreiben kann.

Wer größer, systematischer oder projektförmig mit Reddit-Daten arbeiten will, sollte die offiziellen Wege und Bedingungen genau prüfen. Reddit hat dafür inzwischen auch einen eigenen Anlaufpunkt für Forschung angekündigt: [r/reddit4researchers](https://www.reddit.com/r/reddit4researchers/). Einen guten Überblick über die Konflikte rund um die API-Änderungen 2023 bietet außerdem dieser [Ars-Technica-Text](https://arstechnica.com/gadgets/2023/06/reddit-api-changes-are-imminent-heres-whats-happening-to-your-favorite-apps/).

Für alles darunter, also für den kleinen, konkreten Blick auf einen Thread: [reddit-data-tool](https://dpfu.github.io/reddit-data-tool/).
