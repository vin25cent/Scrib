# Scrib 0.1.0-alpha.4

Build expérimentale destinée aux essais sur Apple Silicon.

## Enregistrement audio

- création et contrôle explicites du dossier de destination avant la création
  de `AVAudioRecorder` ;
- journalisation technique non sensible du chemin de destination, des droits
  d’écriture, du périphérique d’entrée, du format demandé et des résultats de
  `prepareToRecord()` et `record()` ;
- conservation du détail NSError d’AVFoundation lorsqu’il est fourni, ainsi que
  des erreurs d’encodage signalées après le démarrage ;
- AAC/MPEG-4 mono 16 kHz à 96 kbit/s conservé : ce format est compatible avec
  `AVAudioRecorder` et adapté à la transcription locale.

## Important

- cette version est toujours expérimentale / alpha ;
- l’archive est signée ad hoc et non notarée.
