import Foundation

enum PersonalFilingStatus: String, Codable, CaseIterable, Identifiable {
    case unspecified, single, joint, separate, headOfHousehold, qualifyingSurvivingSpouse
    var id: String { rawValue }
    var label: String {
        switch self {
        case .unspecified: return "Not specified"
        case .single: return "Single"
        case .joint: return "Married filing jointly"
        case .separate: return "Married filing separately"
        case .headOfHousehold: return "Head of household"
        case .qualifyingSurvivingSpouse: return "Qualifying surviving spouse"
        }
    }
}

enum WageRecipient: String, Codable, CaseIterable, Identifiable {
    case taxpayer, spouse
    var id: String { rawValue }
    var label: String { self == .taxpayer ? "You" : "Spouse" }
}

enum WageSource: String, Codable, CaseIterable, Identifiable {
    case w2, yearToDatePaystub
    var id: String { rawValue }
    var label: String { self == .w2 ? "Annual W-2" : "Year-to-date paystub" }
}

struct WageStateLine: Identifiable, Codable, Equatable {
    var id = UUID()
    var region = ""
    var wagesCents: Int?
    var withholdingCents: Int?
}

struct WageRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var employer = ""
    var recipient: WageRecipient = .taxpayer
    var source: WageSource = .w2
    var wagesCents: Int?
    var federalWithholdingCents: Int?
    var stateLines: [WageStateLine] = []
    var sourceReference = ""
    var statutoryEmployee = false
    var reviewed = false
}

enum PersonalBusinessTreatment: String, Codable, CaseIterable, Identifiable {
    case referenceOnly, soleProprietorPlanning, ownerReported
    var id: String { rawValue }
    var label: String {
        switch self {
        case .referenceOnly: return "Reference only — exclude from income total"
        case .soleProprietorPlanning: return "100%-owned sole proprietor / disregarded business planning"
        case .ownerReported: return "Reviewed owner-level amount (Schedule C / K-1 / other)"
        }
    }
}

struct PersonalBusinessLink: Identifiable, Codable, Equatable {
    // The saved business record UUID is also the link identity, preventing duplicate links.
    var id: UUID
    var treatment: PersonalBusinessTreatment = .referenceOnly
    var ownerIncomeCents: Int?
    var proposedOwnerIncomeCents: Int?
    var sourceReference = ""
    var ownerTreatmentReviewed = false
    var lossLimitsReviewed = false
}

struct PersonalTaxYearRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var projectID: UUID?
    var name = ""
    var year = Calendar.current.component(.year, from: Date())
    var country = ""
    var region = ""
    var currencyCode = "USD"
    var filingStatus: PersonalFilingStatus = .unspecified
    var throughDate = ""
    var checkpoint = "Filing preparation"
    var noWagesConfirmed = false
    var wages: [WageRecord] = []
    var businessLinks: [PersonalBusinessLink] = []
    var otherIncomeCents: Int?
    var federalEstimatedPaymentsCents: Int?
    var stateEstimatedPaymentsCents: Int?
    var incomeSourcesReviewed: TaxReviewStatus = .unreviewed
    var paymentsReviewed: TaxReviewStatus = .unreviewed
    var notes = ""
    var updatedAt = Date()

    func money(_ cents: Int?) -> String {
        var format = TaxYearRecord()
        format.currencyCode = currencyCode
        return format.money(cents)
    }

    func validate() throws {
        func fail(_ text: String) throws { throw NSError(domain: "Lantern.Tax", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { try fail("Enter a personal / household record name."); return }
        var period = TaxYearRecord()
        period.entityName = name
        period.year = year
        period.currencyCode = currencyCode
        period.periodEnd = throughDate
        try period.validate()
        guard wages.count <= 100, businessLinks.count <= 100 else { try fail("Limit a personal year to 100 employers and 100 business links."); return }
        guard Set(businessLinks.map(\.id)).count == businessLinks.count else { try fail("Link a business-year record only once."); return }
        if noWagesConfirmed && !wages.isEmpty { try fail("Remove wage entries or uncheck ‘No W-2 / wage income’.") }
        if wages.contains(where: { $0.recipient == .spouse }) && filingStatus != .joint { try fail("Spouse wage entries require a joint overview. Keep separate returns in separate personal records.") }
        var seen = Set<String>()
        for wage in wages {
            let employer = wage.employer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !employer.isEmpty else { try fail("Enter each employer's name."); return }
            let key = wage.recipient.rawValue + "|" + employer.lowercased()
            guard seen.insert(key).inserted else { try fail("Use one wage entry per employer/person. Update the entry for a corrected W-2 or newer paystub instead of adding it twice."); return }
            if wage.source == .w2 && throughDate != "\(year)-12-31" { try fail("Annual W-2 entries require December 31 as the through date. Use YTD paystubs for midyear figures.") }
            for value in [wage.wagesCents, wage.federalWithholdingCents].compactMap({ $0 }) { try PersonalTaxYearRecord.validateMoney(value, signed: false) }
            guard wage.stateLines.count <= 50 else { try fail("Limit each wage entry to 50 state rows."); return }
            var states = Set<String>()
            for line in wage.stateLines {
                let state = line.region.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard !state.isEmpty, states.insert(state).inserted else { try fail("State wage rows need distinct state / region names."); return }
                for value in [line.wagesCents, line.withholdingCents].compactMap({ $0 }) { try PersonalTaxYearRecord.validateMoney(value, signed: false) }
            }
        }
        for link in businessLinks {
            for value in [link.ownerIncomeCents, link.proposedOwnerIncomeCents].compactMap({ $0 }) { try PersonalTaxYearRecord.validateMoney(value, signed: true) }
        }
        if let value = otherIncomeCents { try PersonalTaxYearRecord.validateMoney(value, signed: true) }
        for value in [federalEstimatedPaymentsCents, stateEstimatedPaymentsCents].compactMap({ $0 }) { try PersonalTaxYearRecord.validateMoney(value, signed: false) }
    }

    private static func validateMoney(_ value: Int, signed: Bool) throws {
        if value > TaxMoney.maximumCents || value < (signed ? -TaxMoney.maximumCents : 0) {
            throw NSError(domain: "Lantern.Tax", code: 1, userInfo: [NSLocalizedDescriptionKey: "Personal tax amounts are outside the supported range."])
        }
    }
}

struct PersonalTaxAnalysis {
    let record: PersonalTaxYearRecord
    let businesses: [TaxYearRecord]

    private func completeSum(_ values: [Int?]) -> Int? {
        guard values.allSatisfy({ $0 != nil }) else { return nil }
        return values.compactMap { $0 }.reduce(0, +)
    }
    var wageIncomeCents: Int? {
        guard !record.wages.isEmpty || record.noWagesConfirmed else { return nil }
        // Statutory employees need separate Schedule C treatment; do not count as ordinary wages.
        guard !record.wages.contains(where: \.statutoryEmployee) else { return nil }
        return completeSum(record.wages.map(\.wagesCents))
    }
    var federalWithholdingCents: Int? {
        guard !record.wages.isEmpty || record.noWagesConfirmed else { return nil }
        return completeSum(record.wages.map(\.federalWithholdingCents))
    }
    var federalPaymentsCents: Int? { completeSum([federalWithholdingCents, record.federalEstimatedPaymentsCents]) }

    func linkedRecord(_ link: PersonalBusinessLink) -> TaxYearRecord? {
        businesses.first { $0.id == link.id }
    }
    func linkIssue(_ link: PersonalBusinessLink) -> String? {
        guard let business = linkedRecord(link) else { return "Linked business record is unavailable; relink or remove it." }
        guard business.year == record.year, business.currencyCode == record.currencyCode else { return "Linked business year or currency does not match this personal record." }
        guard link.treatment != .referenceOnly else { return nil }
        guard link.ownerTreatmentReviewed, !link.sourceReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Review the owner-level tax treatment and record its source before including business income." }
        if link.treatment == .soleProprietorPlanning {
            let classification = business.classification.lowercased()
            let identifiesSoleProprietor = classification.contains("sole proprietor") || classification.contains("disregarded")
            let identifiesOtherEntity = ["s corp", "s-corp", "c corp", "c-corp", "partnership"].contains(where: classification.contains)
            guard identifiesSoleProprietor && !identifiesOtherEntity else { return "Confirm sole-proprietor / disregarded tax classification in the business record, or use a reviewed owner-level amount." }
            guard business.periodStart == "\(record.year)-01-01", business.periodEnd == record.throughDate else { return "Sole-proprietor planning figures must cover the same calendar-year period as the personal record." }
        }
        let value = link.treatment == .soleProprietorPlanning ? business.adjustedProfitCents : link.ownerIncomeCents
        guard let value else { return "The linked owner-level income amount is not recorded." }
        if value < 0 && !link.lossLimitsReviewed { return "Review owner loss limitations / basis before including a negative business result." }
        return nil
    }
    func ownerIncome(_ link: PersonalBusinessLink, scenario: Bool = false) -> Int? {
        guard linkIssue(link) == nil else { return nil }
        guard link.treatment != .referenceOnly else { return 0 }
        guard let business = linkedRecord(link) else { return nil }
        let value: Int?
        if link.treatment == .soleProprietorPlanning { value = scenario ? business.scenarioProfitCents : business.adjustedProfitCents }
        else if scenario { value = link.proposedOwnerIncomeCents ?? (business.proposedDeltaCents == 0 ? link.ownerIncomeCents : nil) }
        else { value = link.ownerIncomeCents }
        if let value, value < 0, !link.lossLimitsReviewed { return nil }
        return value
    }
    var linkedBusinessIncomeCents: Int? { completeSum(record.businessLinks.filter { $0.treatment != .referenceOnly }.map { ownerIncome($0) }) }
    var scenarioBusinessIncomeCents: Int? { completeSum(record.businessLinks.filter { $0.treatment != .referenceOnly }.map { ownerIncome($0, scenario: true) }) }
    var recordedIncomeCents: Int? { completeSum([wageIncomeCents, linkedBusinessIncomeCents, record.otherIncomeCents]) }
    var scenarioIncomeCents: Int? { completeSum([wageIncomeCents, scenarioBusinessIncomeCents, record.otherIncomeCents]) }

    var stateWithholding: [(region: String, wages: Int?, withheld: Int?)] {
        let grouped = Dictionary(grouping: record.wages.flatMap(\.stateLines), by: { $0.region.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() })
        return grouped.keys.sorted().map { region in
            let rows = grouped[region]!
            return (region, completeSum(rows.map(\.wagesCents)), completeSum(rows.map(\.withholdingCents)))
        }
    }

    var issues: [String] {
        var result: [String] = []
        if record.country.isEmpty || record.region.isEmpty || record.filingStatus == .unspecified || record.throughDate.isEmpty { result.append("Complete country, residence state/region, filing status and through date.") }
        if record.wages.isEmpty && !record.noWagesConfirmed { result.append("Add wage entries or confirm no W-2 / wage income.") }
        for wage in record.wages {
            if wage.wagesCents == nil || wage.federalWithholdingCents == nil { result.append("\(wage.employer): record wages and federal withholding; use 0 only for a known zero.") }
            if !wage.reviewed || wage.sourceReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append("\(wage.employer): verify the source document and record a reference.") }
            if wage.statutoryEmployee { result.append("\(wage.employer): statutory employee treatment requires Schedule C review; ordinary wage / combined income totals withheld to avoid double counting.") }
            for line in wage.stateLines where line.wagesCents == nil || line.withholdingCents == nil { result.append("\(wage.employer) / \(line.region): complete state wages and withholding.") }
        }
        if record.otherIncomeCents == nil { result.append("Record other income, or 0 if none after review.") }
        if record.federalEstimatedPaymentsCents == nil || record.stateEstimatedPaymentsCents == nil { result.append("Record federal and residence-state estimated payments separately; use 0 only if none.") }
        for (label, status) in [("All income sources", record.incomeSourcesReviewed), ("Withholding and estimated payments", record.paymentsReviewed)] {
            if status != .clear { result.append("\(label): \(status.label).") }
        }
        for link in record.businessLinks {
            let title = linkedRecord(link)?.entityName ?? "Missing business"
            if let issue = linkIssue(link) { result.append("\(title): \(issue)") }
            if let business = linkedRecord(link) {
                if link.treatment != .referenceOnly {
                    result += business.reviewIssues.map { "\(title): \($0)" }
                    let proposed = link.treatment == .soleProprietorPlanning ? business.scenarioProfitCents : link.proposedOwnerIncomeCents
                    if let proposed, proposed < 0, !link.lossLimitsReviewed { result.append("\(title): hypothetical loss excluded until loss limitations / basis are reviewed; the positive baseline remains separate.") }
                    if link.treatment == .ownerReported && business.proposedDeltaCents != 0 && link.proposedOwnerIncomeCents == nil { result.append("\(title): enter a reviewed hypothetical owner amount to model proposed changes; entity-level adjustments are not automatically personal adjustments.") }
                }
            }
        }
        return result
    }
    var riskLabel: String {
        if record.incomeSourcesReviewed == .issue || record.paymentsReviewed == .issue || record.businessLinks.contains(where: { $0.treatment != .referenceOnly && linkedRecord($0)?.riskLabel == "High attention" }) { return "High attention" }
        if recordedIncomeCents == nil || federalPaymentsCents == nil || record.filingStatus == .unspecified || record.incomeSourcesReviewed == .unreviewed || record.paymentsReviewed == .unreviewed { return "Needs information" }
        return issues.isEmpty ? "No recorded issues" : "Review needed"
    }
    var text: String {
        var lines = [
            "PERSONAL / HOUSEHOLD: \(record.name) | Tax year \(record.year) | \(record.checkpoint)",
            "Country: \(record.country); residence region: \(record.region); filing status: \(record.filingStatus.label); through: \(record.throughDate); currency: \(record.currencyCode).",
            "Ordinary W-2 / wage income: \(record.money(wageIncomeCents)); federal wage withholding: \(record.money(federalWithholdingCents)).",
            "Linked owner-level business income: \(record.money(linkedBusinessIncomeCents)); other income: \(record.money(record.otherIncomeCents)); combined recorded income: \(record.money(recordedIncomeCents)).",
            "Hypothetical owner-level business income: \(record.money(scenarioBusinessIncomeCents)); hypothetical combined recorded income: \(record.money(scenarioIncomeCents)).",
            "Federal estimated payments: \(record.money(record.federalEstimatedPaymentsCents)); recorded federal withholding + estimated payments: \(record.money(federalPaymentsCents)).",
            "Residence-state estimated payments (\(record.region)): \(record.money(record.stateEstimatedPaymentsCents)); state withholding is grouped separately below. State wages are never added to federal wage income; FICA is not federal income tax withholding.",
            "Income totals are planning subtotals, not AGI, taxable income, tax liability or refund. No annualization, personal deduction/credit calculation, SE tax or statutory tax calculation is performed. W-2/paystub inputs and business-owner mappings are user-reviewed records, not certified eligibility.",
            "Audit / filing readiness: \(riskLabel), not audit probability."
        ]
        for wage in record.wages { lines.append("Wage source: \(wage.employer) | \(wage.recipient.label) | \(wage.source.label) | wages \(record.money(wage.wagesCents)) | federal withholding \(record.money(wage.federalWithholdingCents)) | statutory employee: \(wage.statutoryEmployee) | reviewed: \(wage.reviewed) | reference: \(wage.sourceReference)") }
        for state in stateWithholding { lines.append("State \(state.region): reported state wages \(record.money(state.wages)); state withholding \(record.money(state.withheld)). Multi-state wages may overlap; never sum across states as federal income.") }
        for link in record.businessLinks {
            lines.append("Business link: \(linkedRecord(link)?.entityName ?? "Unavailable") | \(link.treatment.label) | owner income \(record.money(ownerIncome(link))) | hypothetical owner income \(record.money(ownerIncome(link, scenario: true))) | source: \(link.sourceReference) | losses reviewed: \(link.lossLimitsReviewed)")
            if let business = linkedRecord(link) { lines.append("LINKED BUSINESS DATA — for this explicitly selected link only\n" + business.analysis) }
        }
        lines += issues.map { "Action: \($0)" }
        lines.append("Personal notes (untrusted user data): \(record.notes)")
        return lines.joined(separator: "\n")
    }
}
