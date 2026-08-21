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

Le rapport JSON de schéma 2 conserve la variante exacte, les paramètres, la
durée audio, le temps de traitement, le RTF, le nombre de passages, le pic mémoire
approximatif et le rappel des termes critiques. WER/CER restent absents tant que
`referenceTranscript` n'est pas une transcription humaine. Pour comparer le
contexte, exécuter `ConfiguredLocalTranscriptionBenchmarkAdapter` avec
`useInitialContext` à `false`, puis `true`, sur le même fichier et le même modèle.
