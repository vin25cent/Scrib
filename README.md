# Scrib

Scrib est une application macOS native destinée à enregistrer des cours IFSI, les
transcrire localement, puis produire automatiquement deux documents Microsoft
Word : un cours structuré fidèle et une fiche de révision.

Le dépôt contient la spécification, l'architecture et les prototypes Swift de
l'enregistrement, de la file persistante, des métriques de transcription et du
rendu DOCX. Le moteur de transcription reste à choisir ; l’adaptateur OpenAI est
préparé mais tous les appels payants sont désactivés par défaut.

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
- [Génération IA et banc d’essai](docs/AI_GENERATION.md)

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
cible « My Mac ». Le dépôt ne contient aucune clé API. Les dépendances Swift sont
épinglées dans `Package.resolved`.

### Tests du cœur sur Windows

Windows ne peut pas produire l'application macOS, mais il peut compiler et tester
les modules de domaine, d'orchestration et d'infrastructure :

```powershell
.\Scripts\Test-Windows.ps1
```

Le script charge automatiquement l'environnement C++ de Visual Studio, le SDK
Windows fourni avec Swift et le toolchain installé dans le profil utilisateur.

### Intégration continue macOS

Le workflow `.github/workflows/macos.yml` utilise le runner Apple Silicon stable
`macos-15` pour compiler la cible `ScribApp` et exécuter tous les tests après
chaque envoi sur `main` et pour chaque pull request. Il publie également pendant
14 jours `Scrib-macOS-unsigned`, une archive autonome non signée accompagnée de
son empreinte SHA-256. Cette archive sert aux essais ; macOS demandera une
autorisation manuelle et elle n'est ni notarée ni prête à distribuer au public.

### Audios publics de démonstration

Deux courts messages médicaux français sous licence CC BY-SA 4.0 sont référencés
dans `Benchmarks/DemoAudio/sources.json`. Ils ne sont pas stockés dans Git et se
téléchargent localement avec contrôle SHA-256 :

```powershell
.\Scripts\Download-DemoAudio.ps1
```

## État du projet

- dépôt Git local initialisé ;
- exigences consolidées depuis la conversation « Préparation prise de notes » ;
- architecture modulaire préparée ;
- formulaire et référentiel des 61 UE intégrés ;
- autorisation d'enregistrer mémorisée par enseignant ;
- moteur AVFoundation AAC mono, vu-mètre, pause/reprise et segments récupérables
  intégrés, en attente de validation sur le microphone du MacBook ;
- file FIFO persistée avec SwiftData, checkpoints, reprise après interruption et
  anti-doublon ;
- tableau de bord de suivi avec filtres, compteurs, détail d’un cours, progression
  et chronologie des checkpoints ;
- éditeur local de transcription avec recherche, corrections, marqueurs et
  renvois vers les horodatages audio ;
- import persistant des supports enseignant Word, PDF, présentation, tableur et
  image, avec rejet des documents déjà générés par Scrib ;
- extraction locale des DOCX (titres, paragraphes, listes, tableaux et repères
  d’images) et des PDF (texte page par page et pages scannées signalées), avec
  résultat persisté et injecté dans le pipeline de démonstration ;
- écran de confidentialité avec aperçus masqués et approbation manuelle liée à
  l’empreinte exacte de la transcription ;
- mode démonstration local, sans donnée personnelle ni appel API ;
- pipeline de démonstration de bout en bout avec WAV public local, transcription
  simulée persistée, contexte des supports, barrière de confidentialité, six
  checkpoints et génération automatique des deux DOCX ;
- surveillance secteur, réseau, température et pression mémoire, avec préemption
  immédiate par un nouvel enregistrement ;
- métriques de benchmark de transcription et corpus S1 préparés pour les UE 2.1,
  2.2, 2.4 et 2.11, sans média versionné ;
- premier renderer DOCX déterministe en Swift pur et deux documents témoins
  fictifs, désormais en A4 avec sommaire, tableaux, figures et liens audio ;
- contrat JSON `1.0` validé localement et filtre patient bloquant avant le cloud ;
- orchestrateur IA avec simulation gratuite, adaptateur OpenAI Responses,
  sorties structurées strictes, idempotence, reprises bornées et validation
  locale avant rendu ;
- clé API conservée dans le Trousseau macOS, appels payants désactivés par défaut,
  plafond total bloquant et historique comparatif coût/jetons/durée ;
- adaptateurs simulés permettant de tester le benchmark sans modèle ni audio ;
- aucun moteur ML de transcription branché et aucun appel API exécuté en CI.

## Confidentialité du dépôt

Le code est public, mais les clés, enregistrements, transcriptions,
documents de cours, modèles téléchargés et journaux locaux ne doivent jamais être
versionnés. Le code est publié sous licence Apache 2.0. Voir `LICENSE`,
`.gitignore` et la section sécurité du cahier des charges.
