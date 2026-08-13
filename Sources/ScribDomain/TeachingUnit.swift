public struct TeachingUnit: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let semester: Semester
    public let code: String
    public var title: String
    public let occurrence: Int

    public init(
        semester: Semester,
        code: String,
        title: String,
        occurrence: Int = 1
    ) {
        self.semester = semester
        self.code = code
        self.title = title
        self.occurrence = occurrence
        self.id = "s\(semester.rawValue)-\(code)-\(occurrence)"
    }

    public var displayName: String {
        "UE \(code) — \(title)"
    }
}

public enum TeachingUnitCatalog {
    public static func units(for semester: Semester) -> [TeachingUnit] {
        all.filter { $0.semester == semester }
    }

    public static let all: [TeachingUnit] = [
        unit(.semester1, "1.1", "Psychologie, sociologie, anthropologie"),
        unit(.semester1, "1.3", "Législation, éthique, déontologie"),
        unit(.semester1, "2.1", "Biologie fondamentale"),
        unit(.semester1, "2.2", "Cycles de la vie et grandes fonctions"),
        unit(.semester1, "2.4", "Processus traumatiques"),
        unit(.semester1, "2.10", "Infectiologie, hygiène"),
        unit(.semester1, "2.11", "Pharmacologie et thérapeutiques"),
        unit(.semester1, "3.1", "Raisonnement et démarche clinique infirmière"),
        unit(.semester1, "4.1", "Soins de confort et de bien-être"),
        unit(.semester1, "5.1", "Accompagnement de la personne dans la réalisation de ses soins quotidiens"),
        unit(.semester1, "6.1", "Méthodes de travail"),
        unit(.semester1, "6.2", "Anglais"),

        unit(.semester2, "1.1", "Psychologie, sociologie, anthropologie"),
        unit(.semester2, "1.2", "Santé publique et économie de la santé"),
        unit(.semester2, "2.3", "Santé, maladie, handicap, accidents de la vie"),
        unit(.semester2, "2.6", "Processus psychopathologiques"),
        unit(.semester2, "3.1", "Raisonnement et démarche clinique infirmière"),
        unit(.semester2, "3.2", "Projet de soins infirmiers"),
        unit(.semester2, "4.2", "Soins relationnels"),
        unit(.semester2, "4.3", "Soins d’urgence"),
        unit(.semester2, "4.4", "Thérapeutiques et contribution au diagnostic médical"),
        unit(.semester2, "4.5", "Soins infirmiers et gestion des risques"),
        unit(.semester2, "5.2", "Évaluation d’une situation clinique"),
        unit(.semester2, "6.2", "Anglais"),

        unit(.semester3, "1.2", "Santé publique et économie de la santé"),
        unit(.semester3, "2.5", "Processus inflammatoires et infectieux"),
        unit(.semester3, "2.8", "Processus obstructifs"),
        unit(.semester3, "2.11", "Pharmacologie et thérapeutiques"),
        unit(.semester3, "3.2", "Projet de soins infirmiers"),
        unit(.semester3, "3.3", "Rôles infirmiers, organisation du travail et interprofessionnalité"),
        unit(.semester3, "4.2", "Soins relationnels"),
        unit(.semester3, "4.6", "Soins éducatifs et préventifs"),
        unit(.semester3, "5.3", "Communication et conduite de projet"),
        unit(.semester3, "6.2", "Anglais"),

        unit(.semester4, "1.3", "Législation, éthique, déontologie"),
        unit(.semester4, "2.7", "Défaillances organiques et processus dégénératifs"),
        unit(.semester4, "3.4", "Initiation à la démarche de recherche"),
        unit(.semester4, "3.5", "Encadrement des professionnels de soins"),
        unit(.semester4, "4.3", "Soins d’urgence"),
        unit(.semester4, "4.4", "Thérapeutiques et contribution au diagnostic médical"),
        unit(.semester4, "4.5", "Soins infirmiers et gestion des risques"),
        unit(.semester4, "4.6", "Soins éducatifs et préventifs"),
        unit(.semester4, "6.2", "Anglais"),
        unit(.semester4, "5.4", "Soins éducatifs et formation des professionnels et des stagiaires"),
        unit(.semester4, "4.3", "Soins d’urgence", occurrence: 2),
        unit(.semester4, "6.2", "Anglais", occurrence: 2),

        unit(.semester5, "2.6", "Processus psychopathologiques"),
        unit(.semester5, "2.9", "Processus tumoraux"),
        unit(.semester5, "2.11", "Pharmacologie et thérapeutiques"),
        unit(.semester5, "3.3", "Rôles infirmiers, organisation du travail et interprofessionnalité"),
        unit(.semester5, "4.2", "Soins relationnels"),
        unit(.semester5, "4.4", "Thérapeutiques et contribution au diagnostic médical"),
        unit(.semester5, "4.7", "Soins palliatifs et de fin de vie"),
        unit(.semester5, "5.5", "Mise en œuvre des thérapeutiques et coordination des soins"),
        unit(.semester5, "5.7", "Optionnelle — intitulé à préciser"),
        unit(.semester5, "6.2", "Anglais"),

        unit(.semester6, "3.4", "Initiation à la démarche de recherche"),
        unit(.semester6, "4.8", "Qualité des soins, évaluation des pratiques"),
        unit(.semester6, "5.6", "Analyse de la qualité et traitement des données scientifiques et professionnelles"),
        unit(.semester6, "5.7", "Optionnelle — intitulé à préciser"),
        unit(.semester6, "6.2", "Anglais")
    ]

    private static func unit(
        _ semester: Semester,
        _ code: String,
        _ title: String,
        occurrence: Int = 1
    ) -> TeachingUnit {
        TeachingUnit(
            semester: semester,
            code: code,
            title: title,
            occurrence: occurrence
        )
    }
}
