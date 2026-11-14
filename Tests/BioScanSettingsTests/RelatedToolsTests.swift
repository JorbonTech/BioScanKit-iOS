import XCTest
@testable import BioScanSettings

final class RelatedToolsTests: XCTestCase {
    // MARK: Fixtures

    private func app(
        _ id: String,
        name: String = "App",
        subtitle: String = "Subtitle"
    ) -> RecommendedApp {
        RecommendedApp(
            id: id,
            name: name,
            subtitle: subtitle,
            appStoreURL: URL(string: "https://apps.apple.com/app/id\(id.count)")!,
            imageName: "\(id)Logo"
        )
    }

    private func entry(_ id: String) -> RelatedToolEntry {
        // Every shipped route carries action copy; a bare id is a data bug.
        RelatedToolEntry(id: id, actionKey: "related.\(id).action")
    }

    private func route(
        _ trigger: String = "taxon",
        match: [String],
        apps: [String],
        minConfidence: Double? = nil,
        maxConfidence: Double? = nil
    ) -> RelatedRoute {
        RelatedRoute(
            trigger: trigger,
            match: match,
            apps: apps.map(entry),
            minConfidence: minConfidence,
            maxConfidence: maxConfidence
        )
    }

    // MARK: Taxonomy

    func testClassifiesRanks() {
        XCTAssertEqual(
            RelatedTaxon.classify(taxonomy: "Fungi > Basidiomycota > Agaricomycetes > Agaricales"),
            .fungi
        )
        XCTAssertEqual(
            RelatedTaxon.classify(taxonomy: "Animalia > Chordata > Aves > Passeriformes"),
            .birds
        )
        XCTAssertEqual(
            RelatedTaxon.classify(taxonomy: "Animalia > Chordata > Actinopterygii"),
            .fish
        )
        XCTAssertEqual(
            RelatedTaxon.classify(taxonomy: "Plantae > Magnoliopsida"),
            .plants
        )
    }

    func testFishOrderRescuesMissingClassName() {
        XCTAssertEqual(
            RelatedTaxon.classify(taxonomy: "Animalia > Chordata > Cypriniformes"),
            .fish
        )
    }

    func testUnmatchedAndConflictingTaxonomyFallsBackToOther() {
        XCTAssertEqual(RelatedTaxon.classify(taxonomy: "Bacteria > Cyanobacteria"), .other)
        // Aves and Plantae in one string is conflicting evidence, not a guess.
        XCTAssertEqual(RelatedTaxon.classify(taxonomy: "Aves > Plantae"), .other)
    }

    func testMissingTaxonomyIsUnclassifiedNotOther() {
        // `.unclassified` must not unlock the "it may be a rock" route: an empty
        // taxonomy means the host knows nothing, not that the subject is mineral.
        XCTAssertEqual(RelatedTaxon.classify(taxonomy: ""), .unclassified)
        XCTAssertEqual(RelatedTaxon.classify(taxonomy: "   "), .unclassified)

        // 缺少分类不能触发岩石推荐；低置信度仍保留无工具的提醒面板。
        let recommendation = RelatedToolsRecommender.resolve(
            routes: [route("context", match: ["other"], apps: ["mrrock"], maxConfidence: 0.5)],
            catalogue: [app("mrrock")],
            taxon: .unclassified,
            confidence: 0.2
        )
        XCTAssertEqual(recommendation?.variant, .caution)
        XCTAssertEqual(recommendation?.tools.count, 0)
    }

    // MARK: Routing

    func testTaxonRouteResolvesAtHighConfidence() throws {
        let recommendation = try XCTUnwrap(
            RelatedToolsRecommender.resolve(
                routes: [route(match: ["fungi"], apps: ["mushroom"])],
                catalogue: [app("mushroom", name: "Mr.Mushroom")],
                taxon: .fungi,
                confidence: 0.91
            )
        )

        XCTAssertEqual(recommendation.variant, .related)
        XCTAssertEqual(recommendation.tools.map(\.id), ["mushroom"])
    }

    func testCautionVariantKeepsOnlyOneTool() throws {
        let recommendation = try XCTUnwrap(
            RelatedToolsRecommender.resolve(
                routes: [route(match: ["birds"], apps: ["natureear", "mrbird"])],
                catalogue: [app("natureear"), app("mrbird")],
                taxon: .birds,
                confidence: 0.42
            )
        )

        XCTAssertEqual(recommendation.variant, .caution)
        XCTAssertEqual(recommendation.tools.map(\.id), ["natureear"])
    }

    func testRelatedVariantKeepsTwoTools() throws {
        let recommendation = try XCTUnwrap(
            RelatedToolsRecommender.resolve(
                routes: [route(match: ["birds"], apps: ["natureear", "mrbird", "inature"])],
                catalogue: [app("natureear"), app("mrbird"), app("inature")],
                taxon: .birds,
                confidence: 0.80
            )
        )

        XCTAssertEqual(recommendation.tools.map(\.id), ["natureear", "mrbird"])
    }

    func testContextRouteRespectsMaxConfidence() {
        let routes = [
            route("context", match: ["other"], apps: ["mrrock"], maxConfidence: 0.5)
        ]
        let catalogue = [app("mrrock")]

        XCTAssertNil(
            RelatedToolsRecommender.resolve(
                routes: routes,
                catalogue: catalogue,
                taxon: .other,
                confidence: 0.72
            )
        )

        let low = RelatedToolsRecommender.resolve(
            routes: routes,
            catalogue: catalogue,
            taxon: .other,
            confidence: 0.29
        )
        XCTAssertEqual(low?.tools.map(\.id), ["mrrock"])
    }

    func testSuppressedAppIsSkipped() throws {
        let recommendation = try XCTUnwrap(
            RelatedToolsRecommender.resolve(
                routes: [route(match: ["fungi"], apps: ["mushroom", "inature"])],
                catalogue: [app("mushroom"), app("inature")],
                taxon: .fungi,
                confidence: 0.88,
                suppressedAppIDs: ["mushroom"]
            )
        )

        XCTAssertEqual(recommendation.tools.map(\.id), ["inature"])
    }

    func testDuplicatesAcrossRoutesResolveOnce() throws {
        let recommendation = try XCTUnwrap(
            RelatedToolsRecommender.resolve(
                routes: [
                    route(match: ["birds"], apps: ["natureear"]),
                    route(match: ["birds"], apps: ["natureear", "mrbird"])
                ],
                catalogue: [app("natureear"), app("mrbird")],
                taxon: .birds,
                confidence: 0.9
            )
        )

        XCTAssertEqual(recommendation.tools.map(\.id), ["natureear", "mrbird"])
    }

    func testEntryWithoutActionCopyIsSkipped() throws {
        let bare = RelatedRoute(
            trigger: "taxon",
            match: ["fungi"],
            apps: [RelatedToolEntry(id: "mushroom"), entry("inature")]
        )

        let recommendation = try XCTUnwrap(
            RelatedToolsRecommender.resolve(
                routes: [bare],
                catalogue: [app("mushroom"), app("inature")],
                taxon: .fungi,
                confidence: 0.9
            )
        )

        // Without action copy the row would have shown "App", the app name —
        // the exact advert framing the panel exists to avoid.
        XCTAssertEqual(recommendation.tools.map(\.id), ["inature"])
    }

    private func makeExposure() -> RelatedToolsExposure {
        let defaults = UserDefaults(suiteName: "RelatedToolsTests.\(UUID().uuidString)")!
        return RelatedToolsExposure(defaults: defaults)
    }

    func testRerenderingOneScreenDoesNotSpendTheAllowance() {
        let exposure = makeExposure()
        let now = Date()

        // A result page re-evaluates its body many times over one context.
        for _ in 0..<10 {
            exposure.record(["mrbird"], contextID: "result-1", now: now)
        }

        XCTAssertTrue(exposure.canShow("mrbird", contextID: "result-1", now: now))
    }

    func testSessionStopsAfterTwoDistinctScreens() {
        let exposure = makeExposure()
        let now = Date()

        for context in ["r1", "r2"] {
            XCTAssertTrue(exposure.canShow("mrbird", contextID: context, now: now))
            exposure.record(["mrbird"], contextID: context, now: now)
        }

        XCTAssertFalse(
            exposure.canShow("mrbird", contextID: "r3", now: now),
            "a third result page in one session is one too many"
        )
        XCTAssertTrue(exposure.canShow("fish", contextID: "r3", now: now), "the cap is per app")
    }

    func testWeeklyCapSurvivesRelaunch() {
        let defaults = UserDefaults(suiteName: "RelatedToolsTests.\(UUID().uuidString)")!
        let now = Date()

        // Three sessions, one show each.
        for index in 0..<RelatedToolsExposure.weeklyLimit {
            let exposure = RelatedToolsExposure(defaults: defaults)
            exposure.record(["mrbird"], contextID: "r\(index)", now: now)
        }

        let freshLaunch = RelatedToolsExposure(defaults: defaults)
        XCTAssertFalse(freshLaunch.canShow("mrbird", contextID: "r9", now: now))
    }

    func testWeeklyCapRollsOff() {
        let defaults = UserDefaults(suiteName: "RelatedToolsTests.\(UUID().uuidString)")!
        let now = Date()

        for index in 0..<RelatedToolsExposure.weeklyLimit {
            RelatedToolsExposure(defaults: defaults).record(["mrbird"], contextID: "r\(index)", now: now)
        }

        let later = now.addingTimeInterval(RelatedToolsExposure.window + 60)
        XCTAssertTrue(RelatedToolsExposure(defaults: defaults).canShow("mrbird", contextID: "r9", now: later))
    }

    func testCurrentResultRemainsVisibleAtWeeklyLimit() {
        let defaults = UserDefaults(suiteName: "RelatedToolsTests.\(UUID().uuidString)")!
        let now = Date()
        for index in 0..<2 {
            RelatedToolsExposure(defaults: defaults).record(["mrbird"], contextID: "old-\(index)", now: now)
        }
        let exposure = RelatedToolsExposure(defaults: defaults)
        exposure.record(["mrbird"], contextID: "current", now: now)
        XCTAssertTrue(exposure.canShow("mrbird", contextID: "current", now: now))
        XCTAssertFalse(exposure.canShow("mrbird", contextID: "new", now: now))
    }

    func testWeeklyCapExpiresWithoutRelaunch() {
        let exposure = makeExposure()
        let now = Date()
        // 不传 context，单独验证周窗口，不受会话上限影响。
        exposure.record(["mrbird"], contextID: "r1", now: now)
        exposure.record(["mrbird"], contextID: "r2", now: now)
        exposure.record(["mrbird"], contextID: "r3", now: now)
        XCTAssertFalse(exposure.canShow("mrbird", now: now))
        XCTAssertTrue(exposure.canShow("mrbird", now: now.addingTimeInterval(RelatedToolsExposure.window + 1)))
    }

    func testCappedFirstCandidateAllowsFallback() {
        let recommendation = RelatedToolsRecommender.resolve(
            routes: [route(match: ["birds"], apps: ["natureear", "mrbird"])],
            catalogue: [app("natureear"), app("mrbird")],
            taxon: .birds,
            confidence: 0.3,
            isAppAllowed: { $0 != "natureear" }
        )
        XCTAssertEqual(recommendation?.tools.map(\.id), ["mrbird"])
    }

    func testHostThresholdOverridesTheSharedLine() {
        let routes = [route(match: ["birds"], apps: ["natureear"])]
        let catalogue = [app("natureear")]

        // Mr.Bird routes at 0.45; a 0.47 result is "normal" there, so the panel
        // must not claim the identification is unclear.
        XCTAssertEqual(
            RelatedToolsRecommender.resolve(
                routes: routes,
                catalogue: catalogue,
                taxon: .birds,
                confidence: 0.47,
                threshold: 0.45
            )?.variant,
            .related
        )

        // The same result under the shared 0.45 line stays caution when the host
        // passes a higher gate of its own.
        XCTAssertEqual(
            RelatedToolsRecommender.resolve(
                routes: routes,
                catalogue: catalogue,
                taxon: .birds,
                confidence: 0.47,
                threshold: 0.5
            )?.variant,
            .caution
        )
    }

    func testLowConfidenceAlwaysGetsACautionPanel() throws {
        let recommendation = try XCTUnwrap(
            RelatedToolsRecommender.resolve(
                routes: [],
                catalogue: [],
                taxon: .plants,
                confidence: 0.31
            )
        )

        XCTAssertEqual(recommendation.variant, .caution)
        XCTAssertTrue(recommendation.tools.isEmpty)
    }

    func testTrustworthyResultWithoutRoutesIsHidden() {
        XCTAssertNil(
            RelatedToolsRecommender.resolve(
                routes: [],
                catalogue: [],
                taxon: .plants,
                confidence: 0.9
            )
        )
    }

    func testUnrelatedTaxonDoesNotMatch() {
        XCTAssertNil(
            RelatedToolsRecommender.resolve(
                routes: [route(match: ["fungi"], apps: ["mushroom"])],
                catalogue: [app("mushroom")],
                taxon: .insects,
                confidence: 0.9
            )
        )
    }

    // MARK: Document

    func testDecodesRoutesDocument() throws {
        let data = Data(
            """
            {
              "version": 1,
              "routes": {
                "inature": [{
                  "trigger": "taxon",
                  "match": ["fungi"],
                  "apps": [{ "id": "mushroom", "action_key": "related.mushroom.action" }]
                }]
              }
            }
            """.utf8
        )

        let document = try JSONDecoder().decode(RelatedRoutesDocument.self, from: data)

        XCTAssertEqual(document.version, 1)
        XCTAssertEqual(document.routes["inature"]?.first?.match, ["fungi"])
        XCTAssertEqual(
            document.routes["inature"]?.first?.apps.first?.actionKey,
            "related.mushroom.action"
        )
        XCTAssertEqual(document.routes["inature"]?.first?.isEnabled, true)
    }
}
