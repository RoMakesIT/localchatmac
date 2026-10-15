#if !LANTERN_TESTING
import SwiftUI

struct TaxRecordsView: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var editing: TaxYearRecord?
    @State private var showingPersonal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Tax Records").font(.title2.bold())
                    Text(state.activeProject?.name ?? "Global / Personal").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Personal Records") { showingPersonal = true }
                Button("Add entity / year") { editing = TaxYearRecord() }
                Button("Export Excel") { state.exportTaxRecords() }.disabled(state.scopedTaxRecords.isEmpty)
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            }
            Text("Keep actual accounting figures by entity and tax year. Save prior years here; attach returns and supporting documents to your project conversations.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Entities & years").font(.headline)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(state.scopedTaxRecords) { record in
                                Button {
                                    state.selectTaxRecord(record.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(record.entityName) · \(String(record.year))").fontWeight(.semibold)
                                        Text("\(record.checkpoint) · \(record.currencyCode)").font(.caption)
                                        Text(record.money(record.bookProfitCents)).font(.caption)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(state.activeTaxRecord?.id == record.id ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain)
                            }
                            if state.scopedTaxRecords.isEmpty {
                                Text("Add current and previous years to begin.").foregroundStyle(.secondary)
                            }
                        }
                    }
                }.frame(width: 220)
                Divider()
                ScrollView {
                    if let record = state.activeTaxRecord {
                        recordDetails(record)
                    } else {
                        ContentUnavailableView("Choose an entity / year", systemImage: "doc.text.magnifyingglass", description: Text("Select a saved record, or add your first year."))
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if !state.errorText.isEmpty { Text(state.errorText).foregroundStyle(.red).font(.caption) }
        }
        .padding(20)
        .frame(width: 1000, height: 720)
        .sheet(item: $editing) { record in
            TaxRecordEditor(state: state, record: record)
        }
        .sheet(isPresented: $showingPersonal) {
            PersonalTaxRecordsView(state: state, finishReview: { dismiss() })
        }
        .disabled(state.isSending)
    }

    private func recordDetails(_ record: TaxYearRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(record.entityName) · \(String(record.year))").font(.title3.bold())
                    Text("\(record.periodStart.isEmpty ? "Period unspecified" : record.periodStart) — \(record.periodEnd)").font(.caption)
                    Text("\(record.classification) · \(record.country) / \(record.region) · \(record.accountingMethod)").font(.caption)
                }
                Spacer()
                Button("Edit record") { editing = record }
            }
            GroupBox("Actual figures") {
                VStack(alignment: .leading, spacing: 8) {
                    metric("Income", record.money(record.incomeCents))
                    metric("Expenses", record.money(record.expenseCents))
                    metric("Book profit / loss", record.money(record.bookProfitCents))
                    metric("Net cash flow", record.money(record.netCashCents))
                    metric("Estimated tax payments", record.money(record.estimatedPaymentsCents))
                    metric("Previously filed business profit / loss", record.money(record.filedTaxableProfitCents))
                    Text("Actual totals for the recorded period. Cash flow and taxable profit differ.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Book-to-tax planning bridge") {
                VStack(alignment: .leading, spacing: 8) {
                    metric("Book profit / loss", record.money(record.bookProfitCents))
                    metric("User-confirmed adjustments", record.money(record.confirmedDeltaCents))
                    metric("Adjusted business profit / loss", record.money(record.adjustedProfitCents))
                    Divider()
                    metric("Proposed adjustments", record.money(record.proposedDeltaCents))
                    metric("Hypothetical business profit / loss", record.money(record.scenarioProfitCents))
                    Text("Proposed amounts are planning assumptions. These figures do not calculate tax due, a refund, personal taxable income, or whether a loss is deductible.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(record.adjustments) { item in
                        Text("\(item.title): \(record.money(item.amountCents)) · \(item.direction.label) · \(item.status.label)\(item.alreadyAppliedToBaseline ? " · Already applied, omitted" : "")").font(.caption)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Audit / filing risk indicator") {
                VStack(alignment: .leading, spacing: 8) {
                    Label(record.riskLabel, systemImage: record.reviewIssues.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.headline)
                        .foregroundStyle(record.riskLabel == "High attention" ? Color.red : record.reviewIssues.isEmpty ? Color.green : Color.orange)
                    Text("Record-readiness checks, based on your entries and attestations. This is not an audit probability, tax-eligibility certification, or a guarantee.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(record.reviewIssues.enumerated()), id: \.offset) { _, issue in
                        Text("• \(issue)").font(.callout)
                    }
                    if record.reviewIssues.isEmpty { Text("No unresolved issues in the recorded checks; review with your filing solution.").font(.caption) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                ForEach(["Filing preparation", "Midyear check-in", "Year-end planning"], id: \.self) { phase in
                    Button(phase) {
                        state.startTaxReview(phase)
                        dismiss()
                    }
                }
            }
            Text("Review buttons prepare a chat prompt. Send it when ready. Tax research requires configured web search or supplied official sources.").font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Saved details and evidence") {
                Text(record.analysis).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).monospacedDigit().fontWeight(.medium) }
    }
}

private struct TaxRecordEditor: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var record: TaxYearRecord
    @State private var yearText: String
    @State private var income: String
    @State private var expenses: String
    @State private var cashIn: String
    @State private var cashOut: String
    @State private var payments: String
    @State private var filedProfit: String
    @State private var error = ""
    @State private var addingAdjustment = false
    @State private var editingAdjustment: TaxAdjustment?

    init(state: AppState, record: TaxYearRecord) {
        self.state = state
        _record = State(initialValue: record)
        _yearText = State(initialValue: String(record.year))
        _income = State(initialValue: TaxMoney.edit(record.incomeCents))
        _expenses = State(initialValue: TaxMoney.edit(record.expenseCents))
        _cashIn = State(initialValue: TaxMoney.edit(record.cashInCents))
        _cashOut = State(initialValue: TaxMoney.edit(record.cashOutCents))
        _payments = State(initialValue: TaxMoney.edit(record.estimatedPaymentsCents))
        _filedProfit = State(initialValue: TaxMoney.edit(record.filedTaxableProfitCents))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Entity / year record").font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save record", action: save).buttonStyle(.borderedProminent)
            }
            ScrollView {
                Form {
                    Section("Entity and accounting period") {
                        TextField("Entity name", text: $record.entityName)
                        TextField("Tax year (period ending year)", text: $yearText)
                        HStack {
                            TextField("Country", text: $record.country)
                            TextField("State / region (or none)", text: $record.region)
                        }
                        TextField("Legal form and tax classification / election", text: $record.classification)
                        TextField("Accounting method (cash / accrual / other)", text: $record.accountingMethod)
                        TextField("Currency code", text: $record.currencyCode)
                        HStack {
                            TextField("Period start YYYY-MM-DD", text: $record.periodStart)
                            TextField("Through date YYYY-MM-DD", text: $record.periodEnd)
                        }
                        Picker("Checkpoint", selection: $record.checkpoint) {
                            ForEach(["Filing preparation", "Midyear check-in", "Year-end planning", "Filed historical year"], id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Section("Actual accounting totals") {
                        Text("Enter period totals from your books, without commas or currency symbols. Leave unknown amounts blank; enter 0 for a verified zero.").font(.caption)
                        HStack {
                            TextField("Income", text: $income)
                            TextField("Expenses", text: $expenses)
                        }
                        HStack {
                            TextField("Cash inflows", text: $cashIn)
                            TextField("Cash outflows", text: $cashOut)
                        }
                        TextField("Estimated tax payments", text: $payments)
                        TextField("Filed taxable business profit / loss (optional)", text: $filedProfit)
                        TextField("Books / P&L source reference", text: $record.booksReference)
                        TextField("Notes (owner activity, basis, carryforwards, deadlines)", text: $record.notes, axis: .vertical)
                    }
                    Section("Book-to-tax adjustments") {
                        Text("Add only differences from the entered book profit. Proposed items are hypothetical; confirmed items require your review and supporting references.").font(.caption)
                        ForEach(record.adjustments) { item in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.title)
                                    Text("\(record.money(item.amountCents)) · \(item.direction.label) · \(item.status.label)").font(.caption)
                                }
                                Spacer()
                                Button("Edit") { editingAdjustment = item }
                                Button("Remove", role: .destructive) { record.adjustments.removeAll { $0.id == item.id } }
                            }
                        }
                        Button("Add adjustment") { addingAdjustment = true }
                    }
                    Section("Filing-readiness checks") {
                        Text("Mark a check clear only after reviewing the underlying records. Blank / unreviewed checks keep the indicator incomplete.").font(.caption)
                        ForEach(TaxCheck.allCases) { check in
                            Picker(check.label, selection: Binding(
                                get: { record.checks[check.rawValue] ?? .unreviewed },
                                set: { record.checks[check.rawValue] = $0 }
                            )) {
                                ForEach(TaxReviewStatus.allCases.filter { $0 != .notApplicable || check.allowsNotApplicable }) { status in
                                    Text(status.label).tag(status)
                                }
                            }
                        }
                    }
                }.formStyle(.grouped)
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red).font(.callout) }
        }
        .padding(20)
        .frame(width: 860, height: 720)
        .sheet(isPresented: $addingAdjustment) {
            TaxAdjustmentEditor(adjustment: TaxAdjustment()) { item in record.adjustments.append(item) }
        }
        .sheet(item: $editingAdjustment) { item in
            TaxAdjustmentEditor(adjustment: item) { updated in
                if let index = record.adjustments.firstIndex(where: { $0.id == updated.id }) { record.adjustments[index] = updated }
            }
        }
    }

    private func save() {
        do {
            guard let year = Int(yearText) else { error = "Enter a numeric tax year."; return }
            record.year = year
            record.incomeCents = try TaxMoney.parse(income)
            record.expenseCents = try TaxMoney.parse(expenses)
            record.cashInCents = try TaxMoney.parse(cashIn)
            record.cashOutCents = try TaxMoney.parse(cashOut)
            record.estimatedPaymentsCents = try TaxMoney.parse(payments)
            record.filedTaxableProfitCents = try TaxMoney.parse(filedProfit, signed: true)
            try state.saveTaxRecord(record)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct TaxAdjustmentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var adjustment: TaxAdjustment
    @State private var amount: String
    @State private var cashCost: String
    @State private var error = ""
    let saveItem: (TaxAdjustment) -> Void

    init(adjustment: TaxAdjustment, saveItem: @escaping (TaxAdjustment) -> Void) {
        _adjustment = State(initialValue: adjustment)
        _amount = State(initialValue: adjustment.amountCents == 0 ? "" : TaxMoney.edit(adjustment.amountCents))
        _cashCost = State(initialValue: TaxMoney.edit(adjustment.additionalCashCostCents))
        self.saveItem = saveItem
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tax adjustment").font(.title2.bold())
            Form {
                TextField("Description", text: $adjustment.title)
                TextField("Amount (1234.56)", text: $amount)
                Picker("Effect on taxable business profit", selection: $adjustment.direction) {
                    ForEach(TaxAdjustmentDirection.allCases) { Text($0.label).tag($0) }
                }
                Picker("Status", selection: $adjustment.status) {
                    ForEach(TaxAdjustmentStatus.allCases) { Text($0.label).tag($0) }
                }
                TextField("Supporting document / receipt reference", text: $adjustment.evidenceReference)
                TextField("Applicable rule, URL and tax year", text: $adjustment.ruleReference)
                Toggle("I reviewed eligibility, timing and applicable limits", isOn: $adjustment.eligibilityReviewed)
                Toggle("This adjustment’s tax effect is already in the starting profit", isOn: $adjustment.alreadyAppliedToBaseline)
                TextField("Additional cash cost (optional)", text: $cashCost)
                TextField("Notes / prerequisites / deadline", text: $adjustment.notes, axis: .vertical)
                Text("Confirmation records your review; Lantern does not certify eligibility. Do not propose a reduction for an expense already deducted in the books. Add-backs reverse book expenses; mark already applied only if that tax effect is already reflected in your starting figure.").font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped)
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Apply to draft") {
                    do {
                        guard let value = try TaxMoney.parse(amount), value > 0 else { error = "Enter a positive amount."; return }
                        adjustment.amountCents = value
                        adjustment.additionalCashCostCents = try TaxMoney.parse(cashCost)
                        var validation = TaxYearRecord()
                        validation.entityName = "Draft"
                        validation.adjustments = [adjustment]
                        try validation.validate()
                        saveItem(adjustment)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(20).frame(width: 760, height: 600)
    }
}
#endif
