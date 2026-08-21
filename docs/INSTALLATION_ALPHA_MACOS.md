# Installer Scrib 0.1.0-alpha.11 sur macOS

Cette alpha cible un Mac Apple Silicon sous macOS 14 ou plus récent. Pour
l’utiliser, le Mac n’a besoin ni de Xcode, ni de Swift, ni de Homebrew, ni de
Python, ni de Terminal.

## Télécharger

1. Ouvrir la page [Scrib 0.1.0-alpha.11](https://github.com/vin25cent/Scrib/releases/tag/v0.1.0-alpha.11).
2. Dans **Assets**, télécharger `Scrib-0.1.0-alpha.11-macOS.zip`.
3. Le fichier `.sha256` joint permet un contrôle d’intégrité facultatif.

## Installer et ouvrir sans Terminal

1. Double-cliquer sur l’archive ZIP téléchargée.
2. Faire glisser `Scrib.app` dans le dossier **Applications**.
3. Dans Applications, faire un clic droit sur Scrib puis choisir **Ouvrir**.
4. Confirmer une seconde fois avec **Ouvrir**.

Scrib utilise une signature ad hoc et n’est pas encore notarée. Si macOS bloque
l’ouverture, aller dans **Réglages Système → Confidentialité et sécurité**, puis
choisir **Ouvrir quand même** pour Scrib. Aucune commande n’est nécessaire.

## Autorisations au premier lancement

- Autoriser le **microphone** pour enregistrer un cours.
- Autoriser les **notifications** si macOS le propose.
- Les documents enseignant ne sont accessibles que lorsqu’ils sont choisis dans
  l’application.

Aucune clé API n’est nécessaire pour la transcription locale. Les réglages IA
cloud restent séparés et désactivés par défaut.

## Premier essai de transcription réelle

1. Ouvrir **Transcription locale**.
2. Sélectionner **Tiny multilingue** puis cliquer **Télécharger**. Une connexion
   Internet est nécessaire pour ce téléchargement volontaire uniquement.
3. Attendre l’état **Modèle disponible hors ligne**.
4. Ouvrir **Nouveau cours**, remplir les informations puis démarrer.
5. Parler en français pendant environ une minute ; tester une pause et une reprise.
6. Arrêter l’enregistrement. Scrib ouvre l’écran expérimental.
7. Cliquer **Transcrire localement** et observer la progression.
8. À la fin, vérifier le facteur temps réel puis ouvrir le résultat dans l’éditeur.
9. Fermer Scrib, le rouvrir et vérifier que la transcription est toujours présente.
10. Refaire ensuite le test avec 10 à 30 minutes, puis avec Small multilingue.

## Modèles

- **Tiny multilingue**, environ 76,6 Mo : tests techniques et diagnostic rapide.
- **Small multilingue**, environ 486 Mo : premiers essais de qualité en français.

Les tailles peuvent évoluer légèrement dans le dépôt de modèles. Scrib affiche
la taille réellement installée. Un modèle déjà disponible n’est pas téléchargé
à nouveau. Les modèles sont conservés dans
`~/Library/Application Support/Scrib/Models/WhisperKit` et fonctionnent hors ligne.

## Limites connues

- WhisperKit n’est pas encore le choix définitif du moteur de Scrib.
- La diarisation et la correction LLM sont absentes.
- La transcription affichée est volontairement le résultat ASR brut.
- Les métriques M1 ne seront considérées comme validées qu’après le test réel.
- L’application n’est ni notarée ni destinée à une diffusion publique large.

Les cours, segments et transcriptions restent sous
`~/Library/Application Support/Scrib`. Conserver l’archive téléchargée permet de
réinstaller exactement cette version.
