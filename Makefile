# Standard-Target, das den Inhalt von src nach dist kopiert
all: dist

# Erstellt (falls nötig) den dist-Ordner und kopiert alle Dateien
dist:
	mkdir -p dist
	cp -r src/* dist/

# Optionales Target zum Aufräumen, wenn man z. B. den dist-Ordner löschen möchte
clean:
	rm -rf dist
