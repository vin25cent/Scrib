# Données locales du benchmark

Ce dossier ne contient aucun média. `corpus.json` versionne seulement les
métadonnées, licences et règles d'éligibilité.

Sur le MacBook, les fichiers seront placés dans `Local/`, ignoré par Git :

```text
Local/
├── audio/          extraits WAV mono 16 kHz
├── references/     transcriptions humaines UTF-8
├── hypotheses/     sorties brutes par moteur et modèle
└── reports/        métriques JSON et observations système
```

Avant chaque téléchargement, vérifier de nouveau la licence sur la page source.
Une ressource `blocked-until-permission` ne doit jamais être téléchargée par un
script Scrib. Les données Common Voice ne doivent pas être réhébergées.

Les références humaines représenteront 20 à 30 minutes au total, avec au moins
un extrait contrôlé pour chacune des UE 2.1, 2.2, 2.4 et 2.11. Les passages
inaudibles sont exclus du calcul et documentés séparément ; ils ne sont pas
devinés.
