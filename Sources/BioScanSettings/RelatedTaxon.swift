import Foundation

/// Product-level taxon vocabulary shared by every BioScan host app.
///
/// Raw values are the stable keys used by `RelatedRoutes.json`, so renaming a
/// case is a breaking change for the routing document, not just for Swift.
public enum RelatedTaxon: String, CaseIterable, Sendable {
    case birds
    case fish
    case insects
    case mammals
    case reptiles
    case amphibians
    case plants
    case fungi
    case mineral
    /// Ranks were present but matched nothing in the biological tree. This is
    /// the only signal that the subject may not be a living thing.
    case other
    /// No taxonomy at all: the host learned nothing, so no route may fire.
    case unclassified

    /// Classifies a `kingdom > phylum > class > order > family > genus` string.
    ///
    /// Missing or conflicting evidence is deliberately reported as `.other`
    /// instead of guessing, because `.other` is what unlocks the "this may not
    /// be a living thing" route.
    public static func classify(taxonomy: String) -> RelatedTaxon {
        let tokens = Set(
            taxonomy
                .components(separatedBy: CharacterSet(charactersIn: ">/|;,→\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        guard !tokens.isEmpty else { return .unclassified }

        var matches = Set(tokens.compactMap { markers[$0] })
        if !tokens.isDisjoint(with: fishOrders) { matches.insert(.fish) }
        guard matches.count == 1, let match = matches.first else { return .other }
        return match
    }

    private static let markers: [String: RelatedTaxon] = {
        let groups: [(RelatedTaxon, [String])] = [
            (.birds, ["aves", "birds", "鸟纲", "鸟类"]),
            (.fish, ["actinopterygii", "actinopteri", "chondrichthyes", "elasmobranchii",
                     "holocephali", "myxini", "petromyzonti", "petromyzontida", "dipnoi",
                     "coelacanthi", "鱼类", "辐鳍鱼纲", "软骨鱼纲"]),
            (.insects, ["insecta", "昆虫纲", "昆虫"]),
            (.mammals, ["mammalia", "哺乳纲", "哺乳动物"]),
            (.reptiles, ["reptilia", "squamata", "testudines", "crocodylia", "crocodilia",
                         "sphenodontia", "rhynchocephalia", "爬行纲", "爬行动物"]),
            (.amphibians, ["amphibia", "两栖纲", "两栖动物"]),
            (.plants, ["plantae", "植物界", "植物", "magnoliopsida", "liliopsida",
                       "polypodiopsida", "pinopsida", "bryopsida", "lycopodiopsida"]),
            (.fungi, ["fungi", "真菌界", "真菌", "basidiomycota", "ascomycota"]),
            (.mineral, ["mineral", "minerals", "矿物", "矿物类"])
        ]
        return Dictionary(uniqueKeysWithValues: groups.flatMap { taxon, names in
            names.map { ($0, taxon) }
        })
    }()

    /// These orders occur in the bundled species databases with a missing
    /// `class_name`. Do not infer fish from `Chordata` alone: that would also
    /// include birds and mammals.
    private static let fishOrders: Set<String> = [
        "acipenseriformes", "albuliformes", "amiiformes", "anguilliformes", "atheriniformes",
        "aulopiformes", "batrachoidiformes", "beloniformes", "beryciformes", "characiformes",
        "clupeiformes", "cypriniformes", "cyprinodontiformes", "elopiformes", "esociformes",
        "gadiformes", "gasterosteiformes", "gobiesociformes", "gonorynchiformes", "gymnotiformes",
        "lepisosteiformes", "lophiiformes", "mugiliformes", "myctophiformes", "ophidiiformes",
        "osmeriformes", "osteoglossiformes", "perciformes", "percopsiformes", "pleuronectiformes",
        "polypteriformes", "salmoniformes", "scorpaeniformes", "siluriformes", "synbranchiformes",
        "syngnathiformes", "tetraodontiformes", "zeiformes"
    ]
}
