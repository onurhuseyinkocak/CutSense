import Testing
@testable import CutSense

@Suite("Asset Registry")
struct AssetRegistryTests {
    @Test("Starter pack has required asset coverage")
    func starterPackCoverage() {
        #expect(AssetRegistry.items(type: .sfx, category: "whoosh").count >= 5)
        #expect(AssetRegistry.items(type: .sfx, category: "impact").count >= 5)
        #expect(AssetRegistry.items(type: .sfx, category: "riser").count >= 5)
        #expect(AssetRegistry.items(type: .sfx, category: "pop_click").count >= 5)
        #expect(AssetRegistry.items(type: .sfx, category: "glitch").count >= 3)
        #expect(AssetRegistry.items(type: .sfx, category: "camera_transition").count >= 3)
        #expect(AssetRegistry.items(type: .music).count == 5)
        #expect(AssetRegistry.items(type: .visualEffect).count >= 5)
        #expect(AssetRegistry.items(type: .captionStyle).count >= 5)
    }

    @Test("Commercial safety metadata is explicit")
    func commercialSafetyMetadata() {
        let unsafeItems = AssetRegistry.all.filter { !$0.commercialUseAllowed }
        let attributionRequiredItems = AssetRegistry.all.filter(\.attributionRequired)
        let pathlessItems = AssetRegistry.all.filter { $0.localPath.isEmpty }

        #expect(unsafeItems.isEmpty)
        #expect(attributionRequiredItems.isEmpty)
        #expect(pathlessItems.isEmpty)
    }

    @Test("Bundled asset paths resolve")
    func bundledAssetPathsResolve() {
        let missing = AssetRegistry.validateBundledAssets()
        #expect(missing.isEmpty, "Missing bundled assets: \(missing.map(\.id).joined(separator: ", "))")
    }

    @Test("Templates produce non-empty edit plans for captioned content")
    func templatesProduceEditPlans() {
        let captions = [
            TestFixture.caption(start: 0.0, end: 1.4, text: "The important truth is here", role: .hook, style: .hookImpact, behavior: .hookImpact),
            TestFixture.caption(start: 1.8, end: 3.2, text: "This AI tool shows the result", role: .reveal, style: .boldCenterViral, behavior: .focusBlur)
        ]
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 3.2, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 3.2,
            cleanDuration: 3.2
        )

        for template in TemplateConfig.all {
            let plan = EditDecisionEngine.generateEditPlan(
                captions: captions,
                roughCut: roughCut,
                template: template
            )
            #expect(!plan.decisions.isEmpty, "Template \(template.name) produced no decisions")
            if template.intensity == .high {
                #expect(plan.decisions.contains { $0.type == .sfx },
                        "High-energy template \(template.name) should include at least one SFX cue")
            }
        }
    }
}
