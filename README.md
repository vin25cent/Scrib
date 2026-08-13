# Scrib

Scrib est une application macOS native destinée à enregistrer des cours IFSI, les
transcrire localement, puis produire automatiquement deux documents Microsoft
Word : un cours structuré fidèle et une fiche de révision.

Le dépôt contient actuellement la spécification, l'architecture et un squelette
Swift léger. Les traitements lourds (audio, Whisper, appels d'IA, analyse de
supports et génération DOCX) ne sont pas encore implémentés.

## Documents de référence

- [Cahier des charges](docs/CAHIER_DES_CHARGES.md)
- [Architecture technique](docs/ARCHITECTURE.md)
- [Feuille de route](docs/ROADMAP.md)
- [Décisions ouvertes](docs/DECISIONS_OUVERTES.md)
- [Référentiel des UE](docs/REFERENTIEL_UE.md)

## Structure

```text
Sources/
├── ScribDomain/          Modèles et états métier, sans dépendance d'interface
├── ScribApplication/     Cas d'usage et contrats des services
├── ScribInfrastructure/  Futurs adaptateurs macOS, IA, DOCX et stockage
└── ScribApp/             Point d'entrée SwiftUI et interface légère
Tests/
├── ScribDomainTests/
└── ScribApplicationTests/
```

## Préparer le projet sur un Mac

Prérequis de développement : macOS 14 ou plus récent et une version de Xcode
compatible avec Swift 6. Le MacBook cible n'aura besoin que de l'application
compilée ; les outils de développement pourront rester sur une machine de build
ou un service d'intégration continue.

Dans Xcode, ouvrir `Package.swift`, choisir le schéma `ScribApp`, puis lancer la
cible « My Mac ». Le squelette ne contient volontairement aucune dépendance
externe ni clé d'API.

### Tests du cœur sur Windows

Windows ne peut pas produire l'application macOS, mais il peut compiler et tester
les modules de domaine, d'orchestration et d'infrastructure :

```powershell
.\Scripts\Test-Windows.ps1
```

Le script charge automatiquement l'environnement C++ de Visual Studio, le SDK
Windows fourni avec Swift et le toolchain installé dans le profil utilisateur.

### Intégration continue macOS

Le workflow `.github/workflows/macos.yml` utilise un runner Apple Silicon
`macos-latest` pour compiler la cible `ScribApp` et exécuter tous les tests après
chaque envoi sur `main` et pour chaque pull request.

## État du projet

- dépôt Git local initialisé ;
- exigences consolidées depuis la conversation « Préparation prise de notes » ;
- architecture modulaire préparée ;
- interface de cadrage minimale créée ;
- aucun moteur audio, modèle ML ou fournisseur cloud branché.

## Confidentialité du dépôt

Le code est public, mais les clés, enregistrements, transcriptions,
documents de cours, modèles téléchargés et journaux locaux ne doivent jamais être
versionnés. Le code est publié sous licence Apache 2.0. Voir `LICENSE`,
`.gitignore` et la section sécurité du cahier des charges.
