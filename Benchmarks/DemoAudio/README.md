# Audios de démonstration

Ce dossier décrit deux courts messages médicaux en français destinés aux essais
locaux du pipeline Scrib. Les fichiers WAV ne sont jamais versionnés : le script
`Scripts/Download-DemoAudio.ps1` les place dans le sous-dossier ignoré `Local/`
et vérifie leur empreinte SHA-256.

Les deux enregistrements ont été produits par le Centre de recherche en santé de
Nouna (CRSN) dans le cadre d'un projet de recherche financé par le CRDI, puis
publiés sur Wikimedia Commons sous licence Creative Commons Attribution — Partage
dans les mêmes conditions 4.0 International (CC BY-SA 4.0).

Ils ne contiennent pas de données de cours, d'étudiant ou de patient fournies à
Scrib. Les sorties qui reprennent ou adaptent leur contenu doivent conserver
l'attribution et respecter la licence CC BY-SA 4.0. Les métadonnées complètes,
liens sources, tailles et empreintes se trouvent dans `sources.json`.

Téléchargement local :

```powershell
.\Scripts\Download-DemoAudio.ps1
```
