import Foundation
import ScribDomain
import ScribInfrastructure

private let generationDate = ISO8601DateFormatter().date(from: "2026-08-14T12:00:00Z")!
private let courseDate = ISO8601DateFormatter().date(from: "2026-09-14T08:00:00Z")!
private let formatter: DateFormatter = {
    let value = DateFormatter()
    value.locale = Locale(identifier: "fr_FR")
    value.timeZone = TimeZone(secondsFromGMT: 0)
    value.dateFormat = "dd/MM/yyyy"
    return value
}()

private let metadata = [
    CourseDocumentMetadata(label: "Semestre", value: "Semestre 1"),
    CourseDocumentMetadata(label: "UE", value: "UE 2.1 - Biologie fondamentale"),
    CourseDocumentMetadata(label: "Cours", value: "La cellule et les tissus"),
    CourseDocumentMetadata(label: "Enseignant", value: "Dr Martin (exemple fictif)"),
    CourseDocumentMetadata(label: "Date", value: formatter.string(from: courseDate))
]

private let demonstrationSource = CourseDocumentSource(
    authority: "Organisation mondiale de la Santé (démonstration du format)",
    title: "Portail institutionnel",
    url: URL(string: "https://www.who.int/fr")!,
    verifiedAt: generationDate
)

private let fullCourse = CourseDocument(
    kind: .fullCourse,
    title: "La cellule et les tissus",
    subtitle: "UE 2.1 - Biologie fondamentale",
    metadata: metadata,
    sections: [
        CourseDocumentSection(
            title: "Objectifs du cours",
            blocks: [
                .bullets([
                    "Repérer les niveaux d'organisation utilisés dans l'exemple.",
                    "Distinguer une information issue du cours d'une vérification externe.",
                    "Retrouver rapidement un passage incertain grâce à son horodatage audio."
                ])
            ]
        ),
        CourseDocumentSection(
            title: "1. Organisation générale",
            blocks: [
                .paragraph("Dans cette démonstration fictive, la cellule est présentée comme l'unité de base autour de laquelle le cours organise définitions, exemples et liens avec les tissus."),
                .paragraph("Le renderer conserve la hiérarchie fournie par le modèle structuré : les titres, paragraphes, listes et encadrés sont produits localement sans laisser le modèle génératif modifier la mise en page Word."),
                .callout(
                    kind: .medicalImportance,
                    title: "Information médicale importante à vérifier",
                    body: "Ce bloc démontre le signalement visuel d'une information sensible. Le texte est fictif ; aucune conduite clinique ne doit en être déduite.",
                    audioTimestamp: 742
                )
            ]
        ),
        CourseDocumentSection(
            title: "2. De la cellule au tissu",
            blocks: [
                .paragraph("Le document peut regrouper les explications successives tout en conservant une formulation fidèle à la transcription validée."),
                .bullets([
                    "Les notions définies pendant le cours restent dans l'ordre de l'enseignant.",
                    "Les reformulations ajoutées par Scrib doivent être identifiables.",
                    "Les informations incertaines gardent un lien vers l'audio local."
                ]),
                .callout(
                    kind: .uncertainty,
                    title: "Passage incertain",
                    body: "Le terme entendu dans l'enregistrement doit être confirmé avant la validation du document final.",
                    audioTimestamp: 1034
                )
            ]
        ),
        CourseDocumentSection(
            title: "3. Contrôle scientifique",
            blocks: [
                .paragraph("Une vérification externe ne remplace pas le cours. Elle ajoute l'autorité consultée, le lien canonique et la date de vérification, puis signale explicitement toute divergence."),
                .callout(
                    kind: .scientificUpdate,
                    title: "Mise à jour scientifique - exemple de présentation",
                    body: "Cet encadré teste uniquement le style du document. Il ne contient aucune recommandation clinique.",
                    audioTimestamp: nil
                )
            ]
        )
    ],
    sources: [demonstrationSource],
    generatedAt: generationDate
)

private let revisionSheet = CourseDocument(
    kind: .revisionSheet,
    title: "La cellule et les tissus",
    subtitle: "Fiche de révision - UE 2.1",
    metadata: metadata,
    sections: [
        CourseDocumentSection(
            title: "À retenir",
            blocks: [
                .bullets([
                    "La fiche reprend seulement les notions présentes dans le cours validé.",
                    "Les termes médicaux importants sont conservés sans simplification ambiguë.",
                    "Les passages à revoir renvoient au même horodatage que le cours complet."
                ])
            ]
        ),
        CourseDocumentSection(
            title: "Questions flash",
            blocks: [
                .paragraph("1. Quel est le rôle de la hiérarchie des titres dans le document ?"),
                .paragraph("2. Comment distinguer le contenu du cours d'une vérification externe ?"),
                .paragraph("3. Où retrouver un terme transcrit avec une confiance insuffisante ?")
            ]
        ),
        CourseDocumentSection(
            title: "Points à revoir",
            blocks: [
                .callout(
                    kind: .uncertainty,
                    title: "Terme à confirmer",
                    body: "Réécouter le passage avant d'utiliser la fiche comme support de révision.",
                    audioTimestamp: 1034
                ),
                .callout(
                    kind: .information,
                    title: "Méthode",
                    body: "Comparer la fiche avec le cours complet, puis valider les éléments signalés avant export vers iCloud.",
                    audioTimestamp: nil
                )
            ]
        )
    ],
    generatedAt: generationDate
)

let outputDirectory: URL
if CommandLine.arguments.count > 1 {
    outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
} else {
    outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Samples/Generated", isDirectory: true)
}

let renderer = OOXMLDocumentRenderer()
let outputs = [
    (fullCourse, outputDirectory.appendingPathComponent("Cours-complet-demo.docx")),
    (revisionSheet, outputDirectory.appendingPathComponent("Fiche-revision-demo.docx"))
]

do {
    for (document, destination) in outputs {
        try renderer.render(document, to: destination)
        print(destination.path)
    }
} catch {
    FileHandle.standardError.write(Data("Erreur de génération DOCX : \(error)\n".utf8))
    exit(1)
}
