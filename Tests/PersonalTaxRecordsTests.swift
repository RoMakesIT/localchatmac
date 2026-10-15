import Foundation

@MainActor
enum PersonalTaxRecordsTests {
    static func run() async throws {
        var personal = PersonalTaxYearRecord()
        personal.name = "Example Household"
        personal.year = 2026
        personal.country = "US"
        personal.region = "CA"
        personal.throughDate = "2026-12-31"
        personal.filingStatus = .joint
        personal.otherIncomeCents = 100000
        personal.federalEstimatedPaymentsCents = 200000
        personal.stateEstimatedPaymentsCents = 50000
        personal.incomeSourcesReviewed = .clear
        personal.paymentsReviewed = .clear
        var wage = WageRecord()
        wage.employer = "Employer A"
        wage.wagesCents = 10000000
        wage.federalWithholdingCents = 1500000
        wage.sourceReference = "2026 W-2"
        wage.reviewed = true
        wage.stateLines = [WageStateLine(region: "CA", wagesCents: 10000000, withholdingCents: 600000), WageStateLine(region: "NY", wagesCents: 10000000, withholdingCents: 100000)]
        var spouse = wage
        spouse.id = UUID()
        spouse.recipient = .spouse
        spouse.wagesCents = 5000000
        spouse.federalWithholdingCents = 500000
        spouse.stateLines = [WageStateLine(region: "CA", wagesCents: 5000000, withholdingCents: 200000)]
        personal.wages = [wage, spouse]
        try personal.validate()
        var analysis = PersonalTaxAnalysis(record: personal, businesses: [])
        assert(analysis.wageIncomeCents == 15000000) // Multi-state wages never increase federal income.
        assert(analysis.recordedIncomeCents == 15100000)
        assert(analysis.federalWithholdingCents == 2000000)
        assert(analysis.federalPaymentsCents == 2200000) // State/FICA withholding excluded.
        assert(analysis.stateWithholding.first(where: { $0.region == "CA" })?.withheld == 800000)
        assert(analysis.stateWithholding.first(where: { $0.region == "NY" })?.withheld == 100000)
        assert(analysis.riskLabel == "No recorded issues")
        var invalid = personal
        invalid.filingStatus = .separate
        assert((try? invalid.validate()) == nil)
        invalid = personal
        invalid.wages.append(wage)
        assert((try? invalid.validate()) == nil)
        invalid = personal
        invalid.throughDate = "2026-06-30"
        assert((try? invalid.validate()) == nil)
        invalid.wages = invalid.wages.map { var item = $0; item.source = .yearToDatePaystub; return item }
        try invalid.validate()
        invalid.wages[0].wagesCents = nil
        analysis = PersonalTaxAnalysis(record: invalid, businesses: [])
        assert(analysis.wageIncomeCents == nil && analysis.recordedIncomeCents == nil)
        invalid = personal
        invalid.wages[0].statutoryEmployee = true
        analysis = PersonalTaxAnalysis(record: invalid, businesses: [])
        assert(analysis.wageIncomeCents == nil && analysis.federalWithholdingCents == 2000000)
        var noWages = personal
        noWages.wages = []
        assert(PersonalTaxAnalysis(record: noWages, businesses: []).wageIncomeCents == nil)
        noWages.noWagesConfirmed = true
        assert(PersonalTaxAnalysis(record: noWages, businesses: []).wageIncomeCents == 0)

        var business = TaxYearRecord()
        business.entityName = "Consulting"
        business.year = 2026
        business.country = "US"
        business.region = "CA"
        business.classification = "Sole proprietor"
        business.accountingMethod = "Cash"
        business.periodStart = "2026-01-01"
        business.periodEnd = "2026-12-31"
        business.incomeCents = 4000000
        business.expenseCents = 1000000
        var adjustment = TaxAdjustment()
        adjustment.title = "Proposed additional deduction"
        adjustment.amountCents = 500000
        business.adjustments = [adjustment]
        var link = PersonalBusinessLink(id: business.id)
        personal.businessLinks = [link]
        analysis = PersonalTaxAnalysis(record: personal, businesses: [business])
        assert(analysis.linkedBusinessIncomeCents == 0) // Reference-only contributes no business income.
        link.treatment = .soleProprietorPlanning
        personal.businessLinks = [link]
        assert(PersonalTaxAnalysis(record: personal, businesses: [business]).recordedIncomeCents == nil)
        link.ownerTreatmentReviewed = true
        link.sourceReference = "Owner reviewed 2026 source and treatment"
        personal.businessLinks = [link]
        analysis = PersonalTaxAnalysis(record: personal, businesses: [business])
        assert(analysis.linkedBusinessIncomeCents == 3000000)
        assert(analysis.recordedIncomeCents == 18100000)
        assert(analysis.scenarioIncomeCents == 17600000)
        assert(analysis.recordedIncomeCents != analysis.scenarioIncomeCents)
        var corporate = business
        corporate.classification = "LLC taxed as S corporation"
        assert(PersonalTaxAnalysis(record: personal, businesses: [corporate]).recordedIncomeCents == nil)
        var lossScenario = business
        lossScenario.adjustments[0].amountCents = 4000000
        let lossPlanning = PersonalTaxAnalysis(record: personal, businesses: [lossScenario])
        assert(lossPlanning.recordedIncomeCents == 18100000)
        assert(lossPlanning.scenarioIncomeCents == nil)
        business.periodEnd = "2026-06-30"
        assert(PersonalTaxAnalysis(record: personal, businesses: [business]).recordedIncomeCents == nil)
        business.periodEnd = "2026-12-31"
        link.treatment = .ownerReported
        link.ownerIncomeCents = 1000000
        personal.businessLinks = [link]
        analysis = PersonalTaxAnalysis(record: personal, businesses: [business])
        assert(analysis.linkedBusinessIncomeCents == 1000000) // Never substitutes total company profit.
        assert(analysis.scenarioIncomeCents == nil) // Cannot pass an entity proposal through automatically.
        link.proposedOwnerIncomeCents = 800000
        personal.businessLinks = [link]
        assert(PersonalTaxAnalysis(record: personal, businesses: [business]).scenarioIncomeCents == 15900000)
        link.ownerIncomeCents = -100000
        personal.businessLinks = [link]
        assert(PersonalTaxAnalysis(record: personal, businesses: [business]).recordedIncomeCents == nil)
        link.lossLimitsReviewed = true
        personal.businessLinks = [link]
        assert(PersonalTaxAnalysis(record: personal, businesses: [business]).linkedBusinessIncomeCents == -100000)
        var mismatch = business
        mismatch.currencyCode = "EUR"
        assert(PersonalTaxAnalysis(record: personal, businesses: [mismatch]).recordedIncomeCents == nil)
        assert(PersonalTaxAnalysis(record: personal, businesses: []).recordedIncomeCents == nil)
        invalid = personal
        invalid.businessLinks.append(link)
        assert((try? invalid.validate()) == nil)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("personal-tax-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState(storageDirectory: root, startsServices: false)
        state.createProject(named: "Business project")
        try state.saveTaxRecord(business)
        state.createProject(named: "Personal project")
        try state.savePersonalTaxRecord(personal)
        assert(state.taxRecordScope == "personal")
        assert(state.taxAnalysisContext.contains("Example Household") && state.taxAnalysisContext.contains("Consulting"))
        assert(state.scopedTaxRecords.isEmpty) // Explicit cross-project link still resolves.
        assert(state.taxResearchQuery.contains("W-2") && !state.taxResearchQuery.contains("Example Household"))
        assert(state.taxDocumentationRoute?.domains == ["irs.gov"])
        assert(state.personalTaxExportCSV.contains("\"-1000\""))
        var prior = personal
        prior.id = UUID()
        prior.year = 2025
        prior.throughDate = "2025-12-31"
        prior.businessLinks = []
        try state.savePersonalTaxRecord(prior)
        state.selectPersonalTaxRecord(personal.id)
        assert(state.taxAnalysisContext.contains("2025") && state.taxAnalysisContext.contains("2026"))
        let restored = AppState(storageDirectory: root, startsServices: false)
        assert(restored.personalTaxRecords.map(\.id) == state.personalTaxRecords.map(\.id))
        assert(restored.activePersonalTaxRecord?.wages == personal.wages)
        assert(restored.personalAnalysis(restored.activePersonalTaxRecord!).linkedBusinessIncomeCents == -100000)
        assert(restored.taxRecordScope == "personal")
        restored.createProject(named: "Unrelated project")
        assert(!restored.taxAnalysisContext.contains("Example Household"))
        TaxRecordsTests.assertThrows { try restored.savePersonalTaxRecord(personal) }
        var badLink = prior
        badLink.id = UUID()
        badLink.name = "Mismatched"
        badLink.businessLinks = [link]
        TaxRecordsTests.assertThrows { try restored.savePersonalTaxRecord(badLink) }
        let before = state.personalTaxRecords
        let beforeScope = state.taxRecordScope
        let url = root.appendingPathComponent("state.json")
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        var edited = personal
        edited.notes = "Failed write"
        TaxRecordsTests.assertThrows { try state.savePersonalTaxRecord(edited) }
        assert(state.personalTaxRecords == before && state.taxRecordScope == beforeScope)
        print("PASS: personal wages, multi-state withholding, joint/separate boundaries, YTD dates, unknown/zero, owner mappings, proposed scenarios, losses, cross-project links, history, persistence, exports and failed-write rollback")
    }
}
