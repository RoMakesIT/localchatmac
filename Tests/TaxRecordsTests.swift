import Foundation

@MainActor
enum TaxRecordsTests {
    static func run() async throws {
        // Unknown and zero are different; cent arithmetic avoids binary rounding.
        let blank = try TaxMoney.parse("")
        assert(blank == nil)
        let zero = try TaxMoney.parse("0")
        assert(zero == 0)
        let exact = try TaxMoney.parse("1234.56")
        assert(exact == 123456)
        let negative = try TaxMoney.parse("-0.01", signed: true)
        assert(negative == -1)
        for invalid in ["1,000", "0.001", "NaN", "-1", "1e6", "10000000000.01"] {
            assert((try? TaxMoney.parse(invalid)) == nil)
        }
        var record = TaxYearRecord()
        record.entityName = "Example LLC"
        record.year = 2026
        record.country = "US"
        record.region = "CA"
        record.classification = "LLC taxed as sole proprietor"
        record.accountingMethod = "Cash"
        record.periodStart = "2026-01-01"
        record.periodEnd = "2026-06-30"
        record.checkpoint = "Midyear check-in"
        record.incomeCents = 10000001
        record.expenseCents = 4000001
        record.cashInCents = 12000000
        record.cashOutCents = 7000000
        record.booksReference = "Reconciled P&L"
        assert(record.bookProfitCents == 6000000)
        assert(record.netCashCents == 5000000)
        assert(record.riskLabel == "Needs information")
        for check in TaxCheck.allCases { record.checks[check.rawValue] = .clear }
        assert(record.riskLabel == "No recorded issues")
        record.checks[TaxCheck.incomeMatching.rawValue] = .issue
        assert(record.riskLabel == "High attention")
        record.checks[TaxCheck.incomeMatching.rawValue] = .clear

        var proposed = TaxAdjustment()
        proposed.title = "Potential additional deduction"
        proposed.amountCents = 500000
        var confirmed = TaxAdjustment()
        confirmed.title = "Reviewed book-to-tax reduction"
        confirmed.amountCents = 200000
        confirmed.status = .confirmed
        confirmed.evidenceReference = "Receipt register"
        confirmed.ruleReference = "Applicable 2026 authority, reviewed externally"
        confirmed.eligibilityReviewed = true
        var addBack = confirmed
        addBack.id = UUID()
        addBack.title = "Nondeductible expense add-back"
        addBack.direction = .addBack
        addBack.amountCents = 50000
        var duplicate = proposed
        duplicate.id = UUID()
        duplicate.title = "Deduction already applied"
        duplicate.alreadyAppliedToBaseline = true
        var excluded = proposed
        excluded.id = UUID()
        excluded.status = .excluded
        record.adjustments = [proposed, confirmed, addBack, duplicate, excluded]
        assert(record.confirmedDeltaCents == -150000)
        assert(record.adjustedProfitCents == 5850000)
        assert(record.proposedDeltaCents == -500000)
        assert(record.scenarioProfitCents == 5350000)
        assert(record.riskLabel == "Review needed")
        try record.validate()
        var invalid = record
        invalid.adjustments[1].evidenceReference = ""
        assert((try? invalid.validate()) == nil)
        assert(invalid.riskLabel == "High attention")
        assert(invalid.confirmedDeltaCents == 50000)
        invalid = record
        invalid.periodEnd = "2026-02-30"
        assert((try? invalid.validate()) == nil)
        invalid.periodEnd = "2025-12-31"
        assert((try? invalid.validate()) == nil)
        var unknown = TaxYearRecord()
        unknown.entityName = "Unknown"
        assert(unknown.bookProfitCents == nil && unknown.scenarioProfitCents == nil)
        unknown.incomeCents = 0
        unknown.expenseCents = 10000
        assert(unknown.bookProfitCents == -10000)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tax-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState(storageDirectory: directory, startsServices: false)
        state.selectAssistantMode(.tax)
        state.memoryEnabled = false
        assert(state.activeToolNames.contains("analyze_tax_records"))
        assert(!state.activeToolNames.contains("analyze_finance_ledger"))
        assert(state.verificationEnabled && state.systemPromptPreset == .precise)
        assert(!state.webSearchEnabled) // No provider calls without explicit configuration.
        try state.saveTaxRecord(record)
        assert(state.activeTaxRecord?.id == record.id)
        var prior = record
        prior.id = UUID()
        prior.year = 2025
        prior.periodStart = "2025-01-01"
        prior.periodEnd = "2025-12-31"
        prior.checkpoint = "Filed historical year"
        prior.filedTaxableProfitCents = 7000000
        try state.saveTaxRecord(prior)
        state.selectTaxRecord(record.id)
        assert(state.taxAnalysisContext.contains("2025") && state.taxAnalysisContext.contains("2026"))
        var other = record
        other.id = UUID()
        other.entityName = "Other Entity"
        try state.saveTaxRecord(other)
        state.selectTaxRecord(record.id)
        assert(!state.taxAnalysisContext.contains("Other Entity"))
        assert(state.taxExportCSV.contains("\"-1500\""))
        assert(!state.taxExportCSV.contains("\"'-1500\""))
        var unsafeName = record
        unsafeName.id = UUID()
        unsafeName.entityName = "=SUM(A1:A2)"
        try state.saveTaxRecord(unsafeName)
        assert(state.taxExportCSV.contains("\"'=SUM(A1:A2)\""))
        state.selectTaxRecord(record.id)
        var repeated = record
        repeated.id = UUID()
        assertThrows { try state.saveTaxRecord(repeated) }
        let restored = AppState(storageDirectory: directory, startsServices: false)
        assert(restored.taxRecords.map(\.id) == state.taxRecords.map(\.id))
        assert(restored.taxRecords.map(\.adjustments) == state.taxRecords.map(\.adjustments))
        assert(restored.taxRecords.map(\.scenarioProfitCents) == state.taxRecords.map(\.scenarioProfitCents))
        assert(restored.activeTaxRecord?.id == record.id)
        assert(restored.assistantMode == .tax)
        assert(!restored.taxResearchQuery.contains(record.entityName))
        assert(!restored.taxResearchQuery.contains("100000"))
        assert(restored.taxDocumentationRoute?.domains == ["irs.gov"])
        restored.createProject(named: "Separate project")
        assert(restored.scopedTaxRecords.isEmpty)
        assert(!restored.taxAnalysisContext.contains(record.entityName))
        assertThrows { try restored.saveTaxRecord(record) }
        var projectRecord = record
        projectRecord.id = UUID()
        try restored.saveTaxRecord(projectRecord)
        assert(restored.scopedTaxRecords.count == 1)
        assert(!restored.taxAnalysisContext.contains("2025"))
        restored.deleteProject(restored.activeProject!.id)
        assert(restored.taxRecords.allSatisfy { $0.projectID == nil })

        // Saving must fail visibly and preserve records if the atomic file write fails.
        let savedRecords = state.taxRecords
        let savedSelection = state.selectedTaxRecordID
        let stateURL = directory.appendingPathComponent("state.json")
        try FileManager.default.removeItem(at: stateURL)
        try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: false)
        var edited = record
        edited.notes = "Should not survive a failed write"
        assertThrows { try state.saveTaxRecord(edited) }
        assert(state.taxRecords == savedRecords && state.selectedTaxRecordID == savedSelection)
        print("PASS: tax cent arithmetic, P&L bridge, scenario separation, double-count prevention, readiness checks, validation, entity/project isolation, history, persistence and failed-write rollback")
    }

    static func assertThrows(_ block: () throws -> Void) {
        do { try block(); assertionFailure("Expected failure") } catch { }
    }
}
