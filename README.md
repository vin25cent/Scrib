# Scrib

Scrib est une application macOS native destinée à enregistrer des cours IFSI, les
transcrire localement, puis produire automatiquement deux documents Microsoft
Word : un cours structuré fidèle et une fiche de révision.

Le dépôt contient la spécification, l'architecture et l'alpha Swift de
l'enregistrement, de la transcription locale, du suivi persistant d’activités, des
métriques et du rendu DOCX. WhisperKit est intégré comme premier moteur
expérimental de benchmark ; le choix définitif reste ouvert. Tous les appels
payants sont désactivés par défaut.

## Documents de référence

- [Cahier des charges](docs/CAHIER_DES_CHARGES.md)
- [Architecture technique](docs/ARCHITECTURE.md)
- [Feuille de route](docs/ROADMAP.md)
- [Décisions ouvertes](docs/DECISIONS_OUVERTES.md)
- [Référentiel des UE](docs/REFERENTIEL_UE.md)
- [Protocole de benchmark de transcription](docs/BENCHMARK_TRANSCRIPTION.md)
- [Format DOCX déterministe](docs/FORMAT_DOCX.md)
- [Contrat JSON de génération](docs/STRUCTURED_GENERATION.md)
- [Barrière locale de confidentialité](docs/PRIVACY_GATE.md)
- [Génération IA](docs/AI_GENERATION.md)
- [Installer l’alpha sur macOS](docs/INSTALLATION_ALPHA_MACOS.md)
- [Notes de version 0.1.0-alpha.13](docs/RELEASE_NOTES_0.1.0_ALPHA.13.md)

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
cible « My Mac ». Le dépôt ne contient aucune clé API. WhisperKit 1.0.0 est
épinglé exactement via Swift Package Manager ; aucun Python, Homebrew, serveur
local ou ffmpeg externe n’est requis par l’application distribuée.

### Tests du cœur sur Windows

Windows ne peut pas produire l'application macOS, mais il peut compiler et tester
les modules de domaine, d’application et d’infrastructure :

```powershell
.\Scripts\Test-Windows.ps1
```

Le script charge automatiquement l'environnement C++ de Visual Studio, le SDK
Windows fourni avec Swift et le toolchain installé dans le profil utilisateur.

### Intégration continue macOS

Le workflow `.github/workflows/macos.yml` utilise le runner Apple Silicon
`macos-15` avec Xcode 16.4 épinglé pour compiler la cible `ScribApp` et exécuter tous les tests après
chaque envoi sur `main` et pour chaque pull request. Il publie également pendant
14 jours l’archive de l’alpha. Une release dédiée peut également être publiée
avec son
empreinte SHA-256. L’application porte une signature ad hoc vérifiée pendant le
build ; elle n’est pas notarée et macOS demandera donc une autorisation manuelle
au premier lancement.

## État du projet

- dépôt Git local initialisé ;
- exigences consolidées depuis la conversation « Préparation prise de notes » ;
- architecture modulaire préparée ;
- formulaire et référentiel des 61 UE intégrés ;
- autorisation d'enregistrer mémorisée par enseignant ;
- moteur AVFoundation AAC mono, vu-mètre, pause/reprise et segments récupérables
  intégrés et validés sur le microphone du Mac cible ;
- suivi persistant SwiftData des activités réellement exécutées : enregistrement
  et transcription locale ;
- tableau de bord de suivi avec filtres, compteurs, détail d’activité et
  progression lorsqu’elle est fournie par le workflow réel ;
- éditeur local de transcription avec recherche, corrections, marqueurs et
  renvois vers les horodatages audio ;
- import persistant des supports enseignant Word, PDF, présentation, tableur et
  image, avec rejet des documents déjà générés par Scrib ;
- extraction locale des DOCX (titres, paragraphes, listes, tableaux et repères
  d’images) et des PDF (texte page par page et pages scannées signalées), avec
  résultat persisté pour les traitements réels ;
- écran de confidentialité avec aperçus masqués et approbation manuelle liée à
  l’empreinte exacte de la transcription ;
- mesures secteur, réseau, température et pression mémoire pour les benchmarks ;
  elles ne pilotent pas encore la transcription ni le suivi ;
- métriques de benchmark de transcription et corpus S1 préparés pour les UE 2.1,
  2.2, 2.4 et 2.11, sans média versionné ;
- transcription locale réelle expérimentale par WhisperKit 1.0.0, à partir des
  vrais segments M4A de Scrib, en français et avec horodatages ;
- téléchargement volontaire des modèles multilingues Tiny (tests techniques,
  environ 76,6 Mo) et Small (premiers essais qualité, environ 486 Mo), puis
  fonctionnement hors ligne ;
- progression, annulation, provenance moteur/modèle, facteur temps réel,
  contexte machine et persistance de la transcription brute ;
- premier renderer DOCX déterministe en Swift pur, couvert par des tests A4 avec
  sommaire, tableaux, figures et liens audio ;
- contrat JSON `1.0` validé localement et filtre patient bloquant avant le cloud ;
- orchestrateur IA et adaptateur OpenAI Responses conservés, avec sorties
  structurées strictes, idempotence, reprises bornées et validation locale avant
  rendu ;
- clé API conservée dans le Trousseau macOS, appels payants désactivés par défaut,
  plafond total bloquant et historique comparatif coût/jetons/durée ;
- adaptateurs simulés conservés pour tester le benchmark sans modèle ni audio ;
- aucun modèle ML lourd téléchargé et aucun appel API exécuté en CI.

## Confidentialité du dépôt

Le code est public, mais les clés, enregistrements, transcriptions,
documents de cours, modèles téléchargés et journaux locaux ne doivent jamais être
versionnés. Le code est publié sous licence Apache 2.0. Voir `LICENSE`,
`.gitignore` et la section sécurité du cahier des charges.
