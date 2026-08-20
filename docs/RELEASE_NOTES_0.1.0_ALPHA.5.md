# Scrib 0.1.0-alpha.5

Build de diagnostic expérimentale destinée aux essais sur Apple Silicon.

## Diagnostic d’enregistrement audio

- les diagnostics de démarrage audio utilisent désormais le journal unifié
  macOS via `os.Logger`, au niveau `notice` ou `error`, donc visibles dans
  Console pour une build Release distribuée ;
- chaque ligne porte le préfixe `[Scrib][AudioRecording]` et expose uniquement
  les informations techniques nécessaires : destination, droit d’écriture,
  paramètres d’enregistrement, périphérique d’entrée et résultats
  d’AVAudioRecorder ;
- aucun contenu audio, transcription ou donnée utilisateur n’est journalisé.

## Important

- cette version est toujours expérimentale / alpha ;
- l’archive est signée ad hoc et non notarée.
