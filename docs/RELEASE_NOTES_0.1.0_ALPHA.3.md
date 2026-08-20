# Scrib 0.1.0-alpha.3

Build expérimentale destinée aux essais sur Apple Silicon.

## Correction principale

- correction du crash lors de la première demande d’autorisation microphone ;
- correction de l’isolation Swift Concurrency/MainActor dans
  `AVFoundationAudioRecorder.requestPermission()` : le callback TCC peut
  désormais répondre depuis une file de fond sans exécuter de closure isolée au
  MainActor ;
- l’enregistrement ne démarre qu’après autorisation explicite du microphone.

## Important

- cette version est toujours expérimentale / alpha ;
- l’archive est signée ad hoc et non notarée ;
- installer et ouvrir l’application en suivant le guide macOS associé.
