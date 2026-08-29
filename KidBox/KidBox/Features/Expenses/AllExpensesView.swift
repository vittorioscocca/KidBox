//
//  AllExpensesView.swift
//  KidBox
//
//  L'elenco completo delle spese, con i filtri di periodo.
//
//  In home ne compaiono quattro: lì sopra ci sono i totali e il grafico, ed è
//  quello che si viene a vedere. Qui invece si cerca una spesa, quindi la lista
//  è intera e il periodo si cambia dalla stessa fila di filtri della home —
//  stesso `ExpensePeriod`, stesso view model, nessun secondo stato da tenere
//  allineato.
//

import SwiftUI
import SwiftData

struct AllExpensesView: View {
    @ObservedObject var vm: ExpensesViewModel
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(red: 0.18, green: 0.18, blue: 0.18) : .white
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PeriodPickerView(vm: vm)
                    .padding(.horizontal, 16)

                HStack {
                    Text("\(vm.expenses.count) spese")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(vm.totalAmount.formatted(.currency(code: "EUR")))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                .padding(.horizontal, 16)

                if vm.expenses.isEmpty {
                    Text("Nessuna spesa nel periodo scelto")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 32)
                } else {
                    VStack(spacing: 0) {
                        ForEach(vm.expenses) { expense in
                            ExpenseRowView(expense: expense, vm: vm)
                            if expense.id != vm.expenses.last?.id {
                                Divider().padding(.leading, vm.isSelecting ? 68 : 56)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 16)
        }
        .background(backgroundColor)
        .navigationTitle("Tutte le spese")
        .navigationBarTitleDisplayMode(.inline)
    }
}
