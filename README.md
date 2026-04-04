# InvenTree Home Assistant Add-on

Dieses Repository stellt ein Home-Assistant-Add-on fuer einen kompletten InvenTree-Server bereit.

Der Add-on-Container kapselt:

- InvenTree
- PostgreSQL
- Redis
- Nginx
- den InvenTree Background Worker

Das Add-on ist bewusst konservativ auf Home-Assistant-Hardware ausgelegt:

- Standardmaessig `1` Web-Worker
- Standardmaessig `1` Background-Worker
- `background_workers: 0` schaltet den Worker komplett ab, falls minimale Last wichtiger ist als Hintergrundjobs

## Warum kein Ingress?

InvenTree erzeugt aktuell absolute `/static/`- und `/media/`-Pfade. Das passt nicht sauber zu Home-Assistant-Ingress mit Pfad-Prefix, ohne den Web-Client oder das Templating gezielt zu patchen. Deshalb ist dieses erste Add-on bewusst stabil ueber einen normalen Web-Port gebaut.

## Struktur

- `inventree/` enthaelt das eigentliche Add-on
- `.github/workflows/build.yml` baut und veroeffentlicht Multi-Arch-Images nach GHCR

## Vor dem Veroeffentlichen anpassen

Diese Werte sind absichtlich als Platzhalter angelegt:

- `repository.yaml` `url` und `maintainer`
- `inventree/config.yaml` `image`

Wenn du das Repository unter deinem GitHub-Account hostest, ersetze `your-github-user` durch deinen Namen.

## Installation

### Variante A: Als GitHub-Repository

1. Repository nach GitHub pushen
2. Platzhalter fuer Repository-URL und GHCR-Image ersetzen
3. GitHub Actions das Docker-Image bauen lassen
4. Repository als Custom Repository in Home Assistant hinzufuegen

### Variante B: Lokal auf Home Assistant

1. Den Ordner `inventree/` in deinen lokalen Add-on-Ordner kopieren
2. Falls du lokal bauen willst, das `image:`-Feld in `inventree/config.yaml` entfernen oder auf ein lokal vorhandenes Image anpassen
3. Add-on in Home Assistant neu laden

## Quellen und Vorbilder

Beim Aufbau wurden die offiziellen Home-Assistant-App/Add-on-Strukturen und das offizielle InvenTree-Container-Setup als Vorlage verwendet:

- Home Assistant Developer Docs: https://developers.home-assistant.io/docs/apps/configuration
- Offizielles Beispiel-Add-on: https://github.com/home-assistant/addons-example
- InvenTree Docker-Setup: https://github.com/inventree/InvenTree/tree/master/contrib/container
