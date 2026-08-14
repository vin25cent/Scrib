# Prototype DOCX déterministe

## Portée

Le prototype transforme un `CourseDocument` validé en package Office Open XML
local. Aucun modèle d'IA ne produit directement le fichier Word. Le renderer
écrit son résultat de façon atomique via Foundation.

Deux documents témoins fictifs sont générés par `ScribDocxPreview` : le cours
complet et la fiche de révision. Ils servent à tester le package, les styles et
la compatibilité Word ; ils ne constituent pas un contenu pédagogique.

## Système visuel

Le prototype reprend le preset `compact_reference_guide` :

- page Letter portrait, marges de 1 pouce, largeur utile 9360 DXA ;
- Calibri 11 pt, interligne 1,25 et espacement 6 pt ;
- titres 16/13/12 pt avec hiérarchie bleue ;
- vraies définitions OOXML de listes, sans puces tapées à la main ;
- encadrés à géométrie fixe 9360 DXA, retrait 120 DXA et marges de cellule
  explicites ;
- en-tête discret sans filet et pied de page numéroté ;
- accent Scrib `#355AF3` limité au bloc de titre et aux liens.

Les encadrés ont quatre rôles stables : information, passage incertain,
information médicale importante et mise à jour scientifique. Les deux premiers
types sensibles peuvent afficher un horodatage audio.

Le format A4, la table des matières automatique, les images et les tableaux
complexes seront validés avant le jalon de phase 4. Le prototype Letter permet
d'abord une comparaison visuelle reproductible entre Word et LibreOffice.

## Déterminisme et sécurité

- entrées ZIP triées et datées de façon fixe ;
- CRC32 calculé localement ;
- texte et attributs XML échappés ;
- aucune macro, aucun objet OLE et aucun contenu distant incorporé ;
- liens externes déclarés comme relations explicites ;
- métadonnées auteur limitées à `Scrib` ;
- même modèle structuré et même date de génération donnent exactement les mêmes
  octets.

## Commande de génération

```powershell
swift run ScribDocxPreview Samples/Generated
```

La validation automatisée vérifie la signature ZIP, les parties OOXML
obligatoires, le déterminisme, l'échappement XML et les horodatages. La validation
visuelle rend ensuite chaque page en PNG et inspecte les débordements, tableaux,
polices, en-têtes, pieds de page et ruptures.
