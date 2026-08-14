# Installer Scrib 0.1.0-alpha.1 sur macOS

Cette première alpha cible un Mac Apple Silicon sous macOS 14 ou plus récent.
Elle ne nécessite ni Xcode, ni Swift, ni commande de compilation.

## Télécharger

1. Ouvrir la page [Scrib 0.1.0-alpha.1](https://github.com/vin25cent/Scrib/releases/tag/v0.1.0-alpha.1).
2. Dans **Assets**, télécharger `Scrib-0.1.0-alpha.1-macOS.zip`.
3. Télécharger également le fichier portant le même nom suivi de `.sha256`.

Le contrôle d’intégrité est facultatif mais recommandé. Dans Terminal, saisir :

```bash
cd ~/Downloads
shasum -a 256 -c Scrib-0.1.0-alpha.1-macOS.zip.sha256
```

Le résultat attendu se termine par `OK`.

## Installer et ouvrir

1. Double-cliquer sur l’archive ZIP téléchargée.
2. Faire glisser `Scrib.app` dans le dossier **Applications**.
3. Dans Applications, faire un clic droit sur Scrib puis choisir **Ouvrir**.
4. Confirmer une seconde fois avec **Ouvrir**.

Scrib utilise une signature ad hoc et n’est pas encore notarée. Si macOS bloque
quand même l’ouverture, aller dans **Réglages Système → Confidentialité et
sécurité**, puis choisir **Ouvrir quand même** pour Scrib.

En dernier recours seulement, après avoir vérifié l’empreinte SHA-256 ci-dessus :

```bash
xattr -dr com.apple.quarantine /Applications/Scrib.app
```

Relancer ensuite Scrib depuis Applications.

## Autorisations au premier lancement

- Autoriser le **microphone** pour enregistrer un cours.
- Autoriser les **notifications** si macOS le propose.
- Les documents enseignant ne sont accessibles que lorsqu’ils sont choisis dans
  l’application.

Une clé API n’est pas nécessaire pour la démonstration. Si une clé est ajoutée
plus tard, elle est enregistrée dans le Trousseau macOS et les appels payants
restent désactivés jusqu’à leur activation explicite.

## Premier essai recommandé

1. Ouvrir **Démonstration** et charger le jeu de données fictif.
2. Ouvrir **Confidentialité** et approuver la revue locale.
3. Ouvrir **Réglages → Intelligence artificielle**.
4. Choisir le modèle simulé puis lancer **Tester ce modèle**.
5. Vérifier le suivi du cours et les deux documents Word générés.
6. Faire ensuite un court enregistrement micro de 20 à 30 secondes.

## Limites connues de cette alpha

- La transcription d’un véritable enregistrement n’a pas encore de moteur local :
  le pipeline de démonstration utilise une transcription simulée et identifiable.
- L’application n’est ni notarée ni destinée à une diffusion publique large.
- Le microphone interne, la veille et les chemins d’ouverture des documents
  doivent encore être validés sur le MacBook cible.
- Utiliser uniquement des données fictives pendant les premiers essais.

Les données de travail sont enregistrées localement dans
`~/Library/Application Support/Scrib`. Conserver l’archive téléchargée permet de
réinstaller exactement cette version.
