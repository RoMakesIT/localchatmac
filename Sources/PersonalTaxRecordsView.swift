#if !LANTERN_TESTING
import SwiftUI

struct PersonalTaxRecordsView: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var editing: PersonalTaxYearRecord?
    var finishReview: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Personal Tax Records").font(.title2.bold())
                    Text(state.activeProject?.name ?? "Global / Personal").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add personal year") { editing = PersonalTaxYearRecord() }
                Button("Export Excel") { state.exportPersonalTaxRecords() }.disabled(state.scopedPersonalTaxRecords.isEmpty)
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            }
            Text("Track W-2 or YTD wages, withholding and estimated payments. Link business records explicitly, including from your other projects.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("People / households & years").font(.headline)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(state.scopedPersonalTaxRecords) { record in
                                Button { state.selectPersonalTaxRecord(record.id) } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(record.name) · \(String(record.year))").fontWeight(.semibold)
                                        Text(record.filingStatus.label).font(.caption)
                                        Text(record.throughDate).font(.caption)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                        .background(state.activePersonalTaxRecord?.id == record.id ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.06))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain)
                            }
                            if state.scopedPersonalTaxRecords.isEmpty { Text("Add the current year and prior years here.").foregroundStyle(.secondary) }
                        }
                    }
                }.frame(width: 220)
                Divider()
                ScrollView {
                    if let record = state.activePersonalTaxRecord { details(record) }
                    else { ContentUnavailableView("Choose a personal year", systemImage: "person.crop.rectangle", description: Text("Select a saved record, or add your first year.")) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if !state.errorText.isEmpty { Text(state.errorText).foregroundStyle(.red).font(.caption) }
        }.padding(20).frame(width: 1000, height: 720)
            .sheet(item: $editing) { PersonalTaxRecordEditor(state: state, record: $0) }
            .disabled(state.isSending)
    }

    private func details(_ record: PersonalTaxYearRecord) -> some View {
        let analysis = state.personalAnalysis(record)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(record.name) · \(String(record.year))").font(.title3.bold())
                    Text("\(record.filingStatus.label) · through \(record.throughDate)").font(.caption)
                }
                Spacer()
                Button("Edit personal record") { editing = record }
            }
            GroupBox("Income overview") {
                VStack(alignment: .leading, spacing: 8) {
                    metric("Ordinary wages", record.money(analysis.wageIncomeCents))
                    metric("Linked owner-level business income", record.money(analysis.linkedBusinessIncomeCents))
                    metric("Other recorded income", record.money(record.otherIncomeCents))
                    metric("Combined recorded income", record.money(analysis.recordedIncomeCents))
                    Divider()
                    metric("Hypothetical combined income", record.money(analysis.scenarioIncomeCents))
                    Text("Planning subtotals before personal deductions and credits. These are not AGI, taxable income, tax due or a refund. YTD figures are not annualized.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
            }
            GroupBox("Withholding and payments") {
                VStack(alignment: .leading, spacing: 8) {
                    metric("Federal wage withholding", record.money(analysis.federalWithholdingCents))
                    metric("Federal estimated payments", record.money(record.federalEstimatedPaymentsCents))
                    metric("Recorded federal payments", record.money(analysis.federalPaymentsCents))
                    Divider()
                    metric("\(record.region) estimated payments", record.money(record.stateEstimatedPaymentsCents))
                    ForEach(analysis.stateWithholding, id: \.region) { line in
                        metric("\(line.region) wage withholding", record.money(line.withheld))
                    }
                    Text("Federal and state amounts remain separate. Social Security / Medicare withholding is not included as federal income tax withholding.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
            }
            GroupBox("Saved income sources") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(record.wages) { wage in
                        Text("\(wage.employer) · \(wage.recipient.label) · \(wage.source.label): \(record.money(wage.wagesCents))").font(.callout)
                    }
                    ForEach(record.businessLinks) { link in
                        Text("\(analysis.linkedRecord(link)?.entityName ?? "Unavailable business") · \(link.treatment.label)").font(.callout)
                    }
                    if record.noWagesConfirmed { Text("No wage income confirmed by user.").font(.caption) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Audit / filing readiness") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(analysis.riskLabel).font(.headline).foregroundStyle(analysis.riskLabel == "High attention" ? Color.red : analysis.issues.isEmpty ? Color.green : Color.orange)
                    Text("Based on recorded checks and user review, not audit probability or tax-eligibility certification.").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(analysis.issues.enumerated()), id: \.offset) { _, issue in Text("• \(issue)").font(.callout) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                ForEach(["Filing preparation", "Midyear check-in", "Year-end planning"], id: \.self) { phase in
                    Button(phase) {
                        state.startPersonalTaxReview(phase)
                        dismiss()
                        finishReview()
                    }
                }
            }
            Text("Review buttons prepare a chat prompt; send it when ready. Source documents and applicable official rules are still required.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func metric(_ label: String, _ value: String) -> some View {
        HStack { Text(label); Spacer(); Text(value).monospacedDigit().fontWeight(.medium) }
    }
}

private struct PersonalTaxRecordEditor: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var record: PersonalTaxYearRecord
    @State private var year: String
    @State private var otherIncome: String
    @State private var federalPayments: String
    @State private var statePayments: String
    @State private var editingWage: WageRecord?
    @State private var editingLink: PersonalBusinessLink?
    @State private var error = ""

    init(state: AppState, record: PersonalTaxYearRecord) {
        self.state = state
        _record = State(initialValue: record)
        _year = State(initialValue: String(record.year))
        _otherIncome = State(initialValue: TaxMoney.edit(record.otherIncomeCents))
        _federalPayments = State(initialValue: TaxMoney.edit(record.federalEstimatedPaymentsCents))
        _statePayments = State(initialValue: TaxMoney.edit(record.stateEstimatedPaymentsCents))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Personal / household year").font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save personal record", action: save).buttonStyle(.borderedProminent)
            }
            ScrollView {
                Form {
                    Section("Personal filing details") {
                        TextField("Record name (your name or household)", text: $record.name)
                        TextField("Tax year", text: $year)
                        Picker("Filing status", selection: $record.filingStatus) { ForEach(PersonalFilingStatus.allCases) { Text($0.label).tag($0) } }
                        HStack {
                            TextField("Country", text: $record.country)
                            TextField("Residence state / region", text: $record.region)
                        }
                        TextField("Currency code", text: $record.currencyCode)
                        TextField("Through date YYYY-MM-DD", text: $record.throughDate)
                        Text("Use December 31 for annual W-2s. For midyear, enter taxable wages and withholding from YTD paystubs through this date.").font(.caption)
                        Picker("Checkpoint", selection: $record.checkpoint) {
                            ForEach(["Filing preparation", "Midyear check-in", "Year-end planning", "Filed historical year"], id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Section("W-2 / wage sources") {
                        Toggle("I confirmed no W-2 / wage income for this period", isOn: $record.noWagesConfirmed)
                        ForEach(record.wages) { wage in
                            HStack {
                                Text("\(wage.employer) · \(wage.recipient.label) · \(wage.source.label)")
                                Spacer()
                                Button("Edit") { editingWage = wage }
                                Button("Remove", role: .destructive) { record.wages.removeAll { $0.id == wage.id } }
                            }
                        }
                        Button("Add employer / wage source") { editingWage = WageRecord() }.disabled(record.noWagesConfirmed)
                        Text("Update an existing source for newer YTD figures or a corrected W-2; do not count both. Spouse wages require a joint overview.").font(.caption)
                    }
                    Section("Business links") {
                        Text("Explicit links can reference saved businesses from other projects. Each starts reference-only. Select reviewed owner treatment to include an amount.").font(.caption)
                        ForEach(record.businessLinks) { link in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(state.taxRecords.first(where: { $0.id == link.id })?.entityName ?? "Unavailable business")
                                    Text(link.treatment.label).font(.caption)
                                }
                                Spacer()
                                Button("Edit mapping") { editingLink = link }
                                Button("Unlink", role: .destructive) { record.businessLinks.removeAll { $0.id == link.id } }
                            }
                        }
                        Menu("Link a business-year record") {
                            ForEach(state.taxRecords.filter { business in
                                business.year == Int(year) && business.currencyCode == record.currencyCode.uppercased()
                                    && !record.businessLinks.contains(where: { $0.id == business.id })
                            }) { business in
                                Button("\(business.entityName) · \(business.year) · \(state.projects.first(where: { $0.id == business.projectID })?.name ?? "Global / Personal")") {
                                    editingLink = PersonalBusinessLink(id: business.id)
                                }
                            }
                        }
                    }
                    Section("Other income and payments") {
                        Text("Leave unknown values blank. Enter 0 only after confirming none. Other income excludes wages and the linked business figures above.").font(.caption)
                        TextField("Other income total (interest, dividends, other sources)", text: $otherIncome)
                        TextField("Federal estimated payments", text: $federalPayments)
                        TextField("Residence-state estimated payments", text: $statePayments)
                        TextField("Notes / additional states / other withholding / deduction and credit sources", text: $record.notes, axis: .vertical)
                    }
                    Section("Review checks") {
                        reviewPicker("All income sources reviewed", $record.incomeSourcesReviewed)
                        reviewPicker("Withholding and estimated payments reconciled", $record.paymentsReviewed)
                    }
                }.formStyle(.grouped)
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
        }.padding(20).frame(width: 860, height: 720)
            .sheet(item: $editingWage) { wage in
                WageRecordEditor(wage: wage) { saved in
                    if let index = record.wages.firstIndex(where: { $0.id == saved.id }) { record.wages[index] = saved }
                    else { record.wages.append(saved) }
                }
            }
            .sheet(item: $editingLink) { link in
                PersonalBusinessLinkEditor(link: link, business: state.taxRecords.first(where: { $0.id == link.id })) { saved in
                    if let index = record.businessLinks.firstIndex(where: { $0.id == saved.id }) { record.businessLinks[index] = saved }
                    else { record.businessLinks.append(saved) }
                }
            }
    }
    private func reviewPicker(_ label: String, _ binding: Binding<TaxReviewStatus>) -> some View {
        Picker(label, selection: binding) {
            ForEach(TaxReviewStatus.allCases.filter { $0 != .notApplicable }) { Text($0.label).tag($0) }
        }
    }
    private func save() {
        do {
            guard let parsedYear = Int(year) else { error = "Enter a numeric tax year."; return }
            record.year = parsedYear
            record.otherIncomeCents = try TaxMoney.parse(otherIncome, signed: true)
            record.federalEstimatedPaymentsCents = try TaxMoney.parse(federalPayments)
            record.stateEstimatedPaymentsCents = try TaxMoney.parse(statePayments)
            try state.savePersonalTaxRecord(record)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct WageStateDraft: Identifiable {
    var id: UUID
    var region: String
    var wages: String
    var withholding: String
    init(_ line: WageStateLine = WageStateLine()) {
        id = line.id
        region = line.region
        wages = TaxMoney.edit(line.wagesCents)
        withholding = TaxMoney.edit(line.withholdingCents)
    }
}

private struct WageRecordEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var wage: WageRecord
    @State private var wages: String
    @State private var federal: String
    @State private var states: [WageStateDraft]
    @State private var error = ""
    let saveWage: (WageRecord) -> Void
    init(wage: WageRecord, saveWage: @escaping (WageRecord) -> Void) {
        _wage = State(initialValue: wage)
        _wages = State(initialValue: TaxMoney.edit(wage.wagesCents))
        _federal = State(initialValue: TaxMoney.edit(wage.federalWithholdingCents))
        _states = State(initialValue: wage.stateLines.map { WageStateDraft($0) })
        self.saveWage = saveWage
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Employer / wage source").font(.title2.bold())
            ScrollView {
                Form {
                    TextField("Employer name", text: $wage.employer)
                    Picker("Recipient", selection: $wage.recipient) { ForEach(WageRecipient.allCases) { Text($0.label).tag($0) } }
                    Picker("Source", selection: $wage.source) { ForEach(WageSource.allCases) { Text($0.label).tag($0) } }
                    TextField(wage.source == .w2 ? "Box 1 wages" : "YTD federal taxable wages", text: $wages)
                    TextField(wage.source == .w2 ? "Box 2 federal income tax withheld" : "YTD federal income tax withheld", text: $federal)
                    Text("Enter income tax withholding only. Do not add Social Security or Medicare taxes. Do not use take-home pay as wages.").font(.caption)
                    Toggle("Statutory employee (W-2 box 13)", isOn: $wage.statutoryEmployee)
                    Section("State rows — boxes 15, 16 and 17 or YTD equivalents") {
                        ForEach($states) { $line in
                            HStack {
                                TextField("State", text: $line.region).frame(width: 80)
                                TextField("State wages", text: $line.wages)
                                TextField("State income tax withheld", text: $line.withholding)
                                Button("Remove", role: .destructive) { states.removeAll { $0.id == line.id } }
                            }
                        }
                        Button("Add state row") { states.append(WageStateDraft()) }
                        Text("State wages can overlap across states; they are not additional federal wages.").font(.caption)
                    }
                    TextField("Source document reference", text: $wage.sourceReference)
                    Toggle("I checked these figures against the source", isOn: $wage.reviewed)
                }.formStyle(.grouped)
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Apply to draft") {
                    do {
                        guard !wage.employer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Enter an employer name."; return }
                        wage.wagesCents = try TaxMoney.parse(wages)
                        wage.federalWithholdingCents = try TaxMoney.parse(federal)
                        wage.stateLines = try states.map {
                            WageStateLine(id: $0.id, region: $0.region.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), wagesCents: try TaxMoney.parse($0.wages), withholdingCents: try TaxMoney.parse($0.withholding))
                        }
                        saveWage(wage)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(20).frame(width: 780, height: 650)
    }
}

private struct PersonalBusinessLinkEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var link: PersonalBusinessLink
    @State private var ownerIncome: String
    @State private var scenarioIncome: String
    @State private var error = ""
    let business: TaxYearRecord?
    let saveLink: (PersonalBusinessLink) -> Void
    init(link: PersonalBusinessLink, business: TaxYearRecord?, saveLink: @escaping (PersonalBusinessLink) -> Void) {
        _link = State(initialValue: link)
        _ownerIncome = State(initialValue: TaxMoney.edit(link.ownerIncomeCents))
        _scenarioIncome = State(initialValue: TaxMoney.edit(link.proposedOwnerIncomeCents))
        self.business = business
        self.saveLink = saveLink
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(business?.entityName ?? "Unavailable business").font(.title2.bold())
            Form {
                Picker("Personal income treatment", selection: $link.treatment) { ForEach(PersonalBusinessTreatment.allCases) { Text($0.label).tag($0) } }
                if link.treatment == .soleProprietorPlanning {
                    Text("Use only for a 100%-owned sole proprietor / disregarded business. Uses its current confirmed and proposed profit bridge for the same period. Other entity classifications need owner-level figures.").font(.callout)
                }
                if link.treatment == .ownerReported {
                    TextField("Reviewed includable owner income / loss", text: $ownerIncome)
                    TextField("Hypothetical includable owner income / loss (optional)", text: $scenarioIncome)
                    Text("Use the appropriate owner-level tax amount. Company profit, cash distributions and an ownership percentage alone are not sufficient. Proposed entity changes require a separate owner scenario.").font(.caption)
                }
                TextField("Owner-level source and applicable tax-year reference", text: $link.sourceReference)
                Toggle("I reviewed how this business result applies to this personal return", isOn: $link.ownerTreatmentReviewed)
                Toggle("I reviewed loss limitations / basis for any included negative amount", isOn: $link.lossLimitsReviewed)
                Text("Reference-only links are excluded from income totals. Unreviewed includable amounts keep the overview incomplete.").font(.caption)
            }.formStyle(.grouped)
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Apply to draft") {
                    do {
                        link.ownerIncomeCents = try TaxMoney.parse(ownerIncome, signed: true)
                        link.proposedOwnerIncomeCents = try TaxMoney.parse(scenarioIncome, signed: true)
                        saveLink(link)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(20).frame(width: 800, height: 520)
    }
}
#endif
