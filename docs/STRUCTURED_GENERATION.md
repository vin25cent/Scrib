# Contrat de génération structurée

Scrib n'accepte jamais un document Word produit directement par un modèle. Le
fournisseur doit répondre avec le contrat JSON versionné `1.0`, décrit par
[`Schemas/course-generation-v1.schema.json`](../Schemas/course-generation-v1.schema.json).

Le validateur local impose notamment :

- l'identifiant UUID exact du cours demandé ;
- exactement un cours complet et une fiche de révision ;
- des limites de taille, de sections, de blocs et de lignes ;
- un seul contenu cohérent par type de bloc ;
- des références connues et des URL HTTPS appartenant à la liste blanche ;
- un horodatage audio pour chaque passage incertain ou information médicale
  importante ;
- des tableaux rectangulaires et des figures dotées d'une légende et d'un texte
  alternatif.

Les données validées sont ensuite converties en `CourseDocument`, puis rendues
localement en OOXML déterministe. Le schéma JSON sert de contrat interopérable ;
la validation Swift reste la barrière de sécurité faisant autorité.

## Versionnement

Une version majeure inconnue est rejetée. Toute évolution incompatible créera un
nouveau fichier de schéma et un nouveau chemin de conversion. Les réponses et
leurs empreintes pourront ainsi être rejouées sans modifier silencieusement un
cours existant.
