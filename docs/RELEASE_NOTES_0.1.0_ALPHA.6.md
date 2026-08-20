# Scrib 0.1.0-alpha.6

Build de diagnostic expérimentale destinée aux essais sur Apple Silicon.

## Diagnostic d’enregistrement audio

- journal unifié macOS `os.Logger` visible en build Release, avec le préfixe
  `[Scrib][AudioRecording]` ;
- ligne explicite de réussite ou d’échec de l’initialisation
  d’`AVAudioRecorder`, avec son format et ses réglages effectifs ;
- journalisation publique des seuls éléments techniques nécessaires au
  diagnostic : destination, droit d’écriture, périphérique, format demandé,
  `prepareToRecord()`, `record()` et erreurs d’encodage ;
- aucun contenu audio, transcription ou donnée utilisateur n’est journalisé.

## Important

- cette version est toujours expérimentale / alpha ;
- l’archive est signée ad hoc et non notarée.
