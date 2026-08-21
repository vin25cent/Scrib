# Scrib 0.1.0-alpha.16

Build de développement destiné aux essais sur Apple Silicon.

## Évolutions

- navigation améliorée entre **Suivi des cours** et **Transcription locale** ;
- le cours choisi dans le suivi reste le cours actif lorsque l’utilisateur change d’écran ;
- nouvelle action **Ouvrir dans Transcription locale** pour reprendre directement un ancien cours ;
- restauration automatique des métadonnées, segments audio, transcription existante, modèle et métriques du cours sélectionné ;
- accès à **Retranscrire l’audio** lorsque les enregistrements persistés du cours sont disponibles ;
- message explicite et retranscription désactivée lorsque le cours ne possède aucun audio exploitable ;
- isolation stricte des données entre `CourseID` et blocage des changements de cours pendant un traitement actif.

## Important

- cette version reste en développement / alpha ;
- l’archive est signée ad hoc et non notarée.
