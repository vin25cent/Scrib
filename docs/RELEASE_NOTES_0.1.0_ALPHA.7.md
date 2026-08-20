# Scrib 0.1.0-alpha.7

Build expérimentale destinée aux essais sur Apple Silicon.

## Fiabilité de la capture audio

- remplacement du profil AAC 16 kHz / 96 kbit/s, dont l’initialisation codec
  échouait sur le Micro MacBook Neo ;
- capture désormais en AAC‑LC mono 48 kHz à 64 kbit/s, un profil courant et
  stable pour l’enregistrement vocal sur macOS ;
- suppression de la clé de qualité d’encodeur qui entrait en concurrence avec
  le débit demandé ;
- WhisperKit reçoit toujours directement les fichiers M4A et effectue sa
  préparation audio indépendamment de la fréquence de capture.

## Important

- cette version est toujours expérimentale / alpha ;
- l’archive est signée ad hoc et non notarée.
