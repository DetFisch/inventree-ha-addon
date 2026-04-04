# InvenTree Add-on

Dieses Add-on startet einen kompletten InvenTree-Server innerhalb von Home Assistant.

Enthalten sind:

- InvenTree
- PostgreSQL
- Redis
- Nginx als Reverse Proxy
- der InvenTree Background Worker

## Wichtiger Hinweis zu `site_url`

`site_url` ist bei InvenTree keine kosmetische Option, sondern eine Kern-Einstellung.

Setze sie auf die Adresse, unter der du InvenTree spaeter wirklich aufrufst, zum Beispiel:

- `http://192.168.1.50:8000`
- `http://homeassistant.local:8000`
- `https://inventree.example.com`

Wenn du in Home Assistant den externen Port aenderst, musst du `site_url` ebenfalls anpassen.

## Erster Start

1. Add-on installieren
2. `site_url` korrekt setzen
3. Optional Admin-Daten anpassen
4. Add-on starten
5. `OPEN WEB UI` aufrufen

Der erste Start ist deutlich schwerer als spaetere Neustarts, weil Migrationen, statische Assets und Initial-Rebuilds ausgefuehrt werden.
Spaetere Neustarts ueberspringen diese teuren Schritte.

Wenn `admin_password` leer bleibt, erzeugt das Add-on beim ersten Start ein Passwort und schreibt es nach:

- `/config/admin_password.txt` innerhalb des Containers
- auf dem Host typischerweise nach `/addon_configs/inventree/admin_password.txt`

## Konfiguration

### `site_url`

Vollstaendige URL, unter der Benutzer InvenTree aufrufen.

### `timezone`

Zeitzone fuer InvenTree, z. B. `Europe/Berlin`.

### `admin_user`, `admin_email`, `admin_password`

Erstmalige Initial-Anlage eines InvenTree-Superusers.
Wenn der Benutzer bereits existiert, wird er nicht erneut angelegt.

### `log_level`

Log-Level fuer InvenTree.

### `upload_limit_mb`

Maximale Upload-Groesse fuer Nginx und damit fuer Datei-Uploads.

### `web_workers`

Anzahl der Gunicorn-Web-Worker. Fuer Home-Assistant-Hardware ist `1` ein sinnvoller Startwert.

### `background_workers`

Anzahl der InvenTree-Background-Worker. `1` ist fuer kleine Systeme der sinnvolle Standard.
Wenn du Last minimieren willst, kannst du `0` setzen. Dann laufen jedoch keine Hintergrundjobs.

### `plugins_enabled`

Aktiviert InvenTree-Plugins.

### `auto_update`

Erlaubt InvenTree, notwendige Datenbankmigrationen automatisch auszufuehren.

## Bekannte Grenze

Dieses Add-on nutzt bewusst keinen Home-Assistant-Ingress. InvenTree erzeugt absolute `/static/`- und `/media/`-Pfade, wodurch Ingress mit Pfad-Prefix ohne gezielte Frontend-Anpassungen unzuverlaessig ist.
