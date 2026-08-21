# Scrib 0.1.0-alpha.15

Build expérimentale destinée aux essais sur Apple Silicon.

## Évolutions

- ajout de l’action **Retranscrire l’audio** pour réutiliser les segments M4A déjà associés à un cours, sans nouvel enregistrement microphone ;
- réutilisation du pipeline WhisperKit courant, du modèle sélectionné et du contexte lexical actuel sur tous les segments, dans leur ordre persistant ;
- conservation de l’ancienne transcription pendant tout le traitement, avec confirmation explicite avant remplacement ;
- détection claire des segments absents, incomplets ou dupliqués, sans retranscription partielle silencieuse ;
- ajout de tests de sécurité couvrant succès, conservation, remplacement, annulation, erreur moteur, ordre des segments et audio manquant.

## Important

- cette version reste en développement / alpha ;
- l’archive est signée ad hoc et non notarée.
