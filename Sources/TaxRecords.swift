import Foundation

// Tax records contain actual period totals, never annualized budget estimates.
enum TaxAdjustmentDirection: String, Codable, CaseIterable, Identifiable {
    case reduction, addBack
    var id: String { rawValue }
    var label: String { self == .reduction ? "Reduce taxable profit" : "Add back to taxable profit" }
}

enum TaxAdjustmentStatus: String, Codable, CaseIterable, Identifiable {
    case proposed, confirmed, excluded
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum TaxReviewStatus: String, Codable, CaseIterable, Identifiable {
    case unreviewed, clear, issue, notApplicable
    var id: String { rawValue }
    var label: String {
        switch self {
        case .unreviewed: return "Not reviewed"
        case .clear: return "Checked — clear"
        case .issue: return "Issue to resolve"
        case .notApplicable: return "Not applicable"
        }
    }
}

enum TaxCheck: String, Codable, CaseIterable, Identifiable {
    case reconciliation, documentation, incomeMatching, ownerSeparation, payroll, carryforwards
    var id: String { rawValue }
    var label: String {
        switch self {
        case .reconciliation: return "Books reconciled to bank / card accounts"
        case .documentation: return "Income and expenses have supporting records"
        case .incomeMatching: return "Income matched to applicable information returns"
        case .ownerSeparation: return "Owner activity and inter-entity transfers separated"
        case .payroll: return "Payroll and required reporting checked"
        case .carryforwards: return "Prior-year carryforwards and basis reviewed"
        }
    }
    var allowsNotApplicable: Bool { self == .payroll || self == .carryforwards || self == .incomeMatching }
}

struct TaxAdjustment: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var amountCents = 0
    var direction: TaxAdjustmentDirection = .reduction
    var status: TaxAdjustmentStatus = .proposed
    var evidenceReference = ""
    var ruleReference = ""
    var eligibilityReviewed = false
    var alreadyAppliedToBaseline = false
    var additionalCashCostCents: Int?
    var notes = ""

    var signedCents: Int { direction == .reduction ? -amountCents : amountCents }
    // Confirmation is a user attestation; the app does not certify tax eligibility.
    var canApply: Bool {
        status == .confirmed && eligibilityReviewed && !alreadyAppliedToBaseline
            && !evidenceReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !ruleReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct TaxYearRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var projectID: UUID?
    var entityName = ""
    var year = Calendar.current.component(.year, from: Date())
    var country = ""
    var region = ""
    var classification = ""
    var accountingMethod = ""
    var currencyCode = "USD"
    var periodStart = ""
    var periodEnd = ""
    var checkpoint = "Filing preparation"
    var incomeCents: Int?
    var expenseCents: Int?
    var cashInCents: Int?
    var cashOutCents: Int?
    var estimatedPaymentsCents: Int?
    var filedTaxableProfitCents: Int?
    var booksReference = ""
    var notes = ""
    var checks: [String: TaxReviewStatus] = [:]
    var adjustments: [TaxAdjustment] = []
    var updatedAt = Date()

    var bookProfitCents: Int? {
        guard let incomeCents, let expenseCents else { return nil }
        return incomeCents - expenseCents
    }
    var netCashCents: Int? {
        guard let cashInCents, let cashOutCents else { return nil }
        return cashInCents - cashOutCents
    }
    var confirmedDeltaCents: Int {
        adjustments.filter(\.canApply).reduce(0) { $0 + $1.signedCents }
    }
    var proposedDeltaCents: Int {
        adjustments.filter { $0.status == .proposed && !$0.alreadyAppliedToBaseline }.reduce(0) { $0 + $1.signedCents }
    }
    var adjustedProfitCents: Int? { bookProfitCents.map { $0 + confirmedDeltaCents } }
    var scenarioProfitCents: Int? { adjustedProfitCents.map { $0 + proposedDeltaCents } }

    func money(_ cents: Int?) -> String {
        guard let cents else { return "Not recorded" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let value = NSDecimalNumber(value: cents).dividing(by: 100)
        return "\(currencyCode) \(formatter.string(from: value) ?? value.stringValue)"
    }

    var reviewIssues: [String] {
        var issues: [String] = []
        if entityName.isEmpty || country.isEmpty || region.isEmpty || classification.isEmpty || accountingMethod.isEmpty {
            issues.append("Complete entity, jurisdiction, tax classification and accounting method.")
        }
        if periodStart.isEmpty || periodEnd.isEmpty { issues.append("Record the exact accounting period; figures are not annualized.") }
        if bookProfitCents == nil { issues.append("Record both actual income and actual expenses.") }
        if booksReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("Link or describe the source books / P&L.") }
        for check in TaxCheck.allCases {
            let value = checks[check.rawValue] ?? .unreviewed
            if value == .unreviewed { issues.append("Not reviewed: \(check.label).") }
            if value == .issue { issues.append("Resolve: \(check.label).") }
            if value == .notApplicable && !check.allowsNotApplicable { issues.append("Review required: \(check.label) cannot be marked not applicable.") }
        }
        for adjustment in adjustments where adjustment.status != .excluded {
            if adjustment.alreadyAppliedToBaseline { issues.append("Do not double count ‘\(adjustment.title)’; its tax effect is already in the starting profit and omitted from adjustments.") }
            if adjustment.status == .confirmed && !adjustment.canApply { issues.append("‘\(adjustment.title)’ lacks confirmation requirements; omitted from confirmed totals.") }
            if adjustment.status == .proposed { issues.append("Planning assumption: ‘\(adjustment.title)’ is not confirmed for filing.") }
        }
        return issues
    }

    var riskLabel: String {
        if checks.values.contains(.issue) || adjustments.contains(where: { $0.status == .confirmed && !$0.canApply }) {
            return "High attention"
        }
        if bookProfitCents == nil || country.isEmpty || classification.isEmpty || TaxCheck.allCases.contains(where: { checks[$0.rawValue] == nil || checks[$0.rawValue] == .unreviewed }) {
            return "Needs information"
        }
        return reviewIssues.isEmpty ? "No recorded issues" : "Review needed"
    }

    var analysis: String {
        var lines = [
            "Entity: \(entityName) | Tax year: \(year) | \(checkpoint)",
            "Jurisdiction: \(country) / \(region); tax classification: \(classification); accounting: \(accountingMethod).",
            "Period: \(periodStart.isEmpty ? "unspecified" : periodStart) through \(periodEnd.isEmpty ? "unspecified" : periodEnd). Currency: \(currencyCode). Actual entered totals; not annualized.",
            "Books reference: \(booksReference)",
            "Income: \(money(incomeCents)); expenses: \(money(expenseCents)); book net profit/loss: \(money(bookProfitCents)).",
            "Cash inflows: \(money(cashInCents)); cash outflows: \(money(cashOutCents)); net cash: \(money(netCashCents)). Cash flow is distinct from taxable profit.",
            "User-confirmed book-to-tax adjustment: \(money(confirmedDeltaCents)); adjusted business profit/loss: \(money(adjustedProfitCents)).",
            "Proposed adjustment: \(money(proposedDeltaCents)); hypothetical business profit/loss: \(money(scenarioProfitCents)). Proposed amounts are assumptions, not verified deductions.",
            "Estimated tax payments: \(money(estimatedPaymentsCents)); previously filed taxable business profit/loss: \(money(filedTaxableProfitCents)).",
            "These business figures are not total personal taxable income, tax liability, refund, or usable loss deductions. Limits, basis, elections and owner-level items require separate review.",
            "Audit / filing risk indicator: \(riskLabel). Rule-based record-readiness checks only; not an audit probability or validation of tax eligibility.",
            "Checks are user attestations; not independently verified. Updated: \(updatedAt.formatted(date: .numeric, time: .omitted))."
        ]
        for item in adjustments {
            lines.append("Adjustment: \(item.title) | \(item.direction.label) | \(money(item.amountCents)) | \(item.status.label) | Applied: \(item.canApply) | Tax effect already in starting profit: \(item.alreadyAppliedToBaseline) | Eligibility reviewed: \(item.eligibilityReviewed) | Additional cash cost: \(money(item.additionalCashCostCents)) | Evidence: \(item.evidenceReference) | Rule/year reference: \(item.ruleReference) | Notes: \(item.notes)")
        }
        lines += TaxCheck.allCases.map { "\($0.label): \((checks[$0.rawValue] ?? .unreviewed).label)" }
        lines += reviewIssues.map { "Action: \($0)" }
        lines.append("Notes: \(notes)")
        return lines.joined(separator: "\n")
    }

    func validate() throws {
        func fail(_ text: String) throws { throw NSError(domain: "Lantern.Tax", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
        guard !entityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { try fail("Enter an entity name."); return }
        guard (1900...2200).contains(year) else { try fail("Enter a tax year between 1900 and 2200."); return }
        guard currencyCode.count == 3, currencyCode.unicodeScalars.allSatisfy({ CharacterSet.uppercaseLetters.contains($0) }) else { try fail("Use a three-letter currency code, such as USD."); return }
        for value in [incomeCents, expenseCents, cashInCents, cashOutCents, estimatedPaymentsCents].compactMap({ $0 }) {
            if value < 0 || value > TaxMoney.maximumCents { try fail("Period amounts must be nonnegative and within the supported range.") }
        }
        if let value = filedTaxableProfitCents, (value < -TaxMoney.maximumCents || value > TaxMoney.maximumCents) { try fail("Filed profit is outside the supported range.") }
        let dates = [periodStart, periodEnd]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        for date in dates where !date.isEmpty {
            guard let parsed = formatter.date(from: date), formatter.string(from: parsed) == date else { try fail("Enter period dates as YYYY-MM-DD."); return }
        }
        if !periodStart.isEmpty && !periodEnd.isEmpty && periodStart > periodEnd { try fail("The period start must precede its end.") }
        if !periodEnd.isEmpty && Int(periodEnd.prefix(4)) != year { try fail("The tax year should be the year the recorded period ends.") }
        guard adjustments.count <= 200 else { try fail("Limit each record to 200 adjustments."); return }
        for item in adjustments {
            if item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || item.amountCents <= 0 || item.amountCents > TaxMoney.maximumCents { try fail("Each adjustment needs a description and a positive amount within range.") }
            if let cash = item.additionalCashCostCents, cash < 0 || cash > TaxMoney.maximumCents { try fail("Additional cash cost must be nonnegative and within range.") }
            if item.status == .confirmed && !item.canApply { try fail("Confirmed adjustments need evidence, a rule/year reference, and eligibility review, and must not already have been applied to the starting profit. Keep uncertain items proposed.") }
        }
    }
}

enum TaxMoney {
    static let maximumCents = 1_000_000_000_000
    static func parse(_ text: String, signed: Bool = false) throws -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return nil }
        let pattern = signed ? #"^-?[0-9]+(?:\.[0-9]{1,2})?$"# : #"^[0-9]+(?:\.[0-9]{1,2})?$"#
        guard cleaned.range(of: pattern, options: .regularExpression) != nil,
              let number = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")),
              abs(number) <= Decimal(maximumCents) / 100 else {
            throw NSError(domain: "Lantern.Tax", code: 1, userInfo: [NSLocalizedDescriptionKey: "Enter amounts like 1234.56, without commas or currency symbols (maximum 10 billion)."])
        }
        return NSDecimalNumber(decimal: number * 100).intValue
    }
    static func edit(_ cents: Int?) -> String {
        guard let cents else { return "" }
        return NSDecimalNumber(value: cents).dividing(by: 100).stringValue
    }
}
