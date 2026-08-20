# Scrib 0.1.0-alpha.2

Alpha expérimentale destinée au premier benchmark de transcription réelle sur
un MacBook Pro Apple Silicon M1 sous macOS 14 ou plus récent.

## Nouveautés

- transcription locale réelle via WhisperKit 1.0.0 et Core ML ;
- modèles Tiny multilingue (smoke tests) et Small multilingue (qualité française)
  téléchargés uniquement sur demande ;
- fonctionnement hors ligne après le téléchargement initial ;
- traitement ordonné des vrais segments M4A de Scrib, avec français forcé,
  horodatages de passages et de mots et déduplication aux frontières ;
- progression, annulation, durée audio, temps de traitement et facteur temps réel ;
- provenance moteur/version/modèle, taille installée, contexte machine et états
  thermiques dans les résultats ;
- persistance locale du résultat brut et des corrections de l’éditeur ;
- adaptateur du même moteur pour les rapports JSON de benchmark.

## Garanties de cette alpha

- aucune clé API, aucun serveur local, Python, Homebrew ou ffmpeg externe ;
- aucun audio ni texte envoyé pour la transcription ;
- aucun appel IA cloud déclenché après l’ASR ;
- aucun modèle lourd téléchargé pendant les tests CI.

## Limites connues

- WhisperKit est un candidat expérimental, pas le choix définitif de Scrib ;
- aucune diarisation ni correction LLM de la transcription brute ;
- l’archive est signée ad hoc et non notarée ;
- la vitesse, le pic mémoire et la compatibilité pratique M1 doivent encore être
  mesurés sur la machine réelle ;
- Medium et Large-v3-Turbo sont préparés dans le catalogue mais désactivés pour
  cette alpha.
