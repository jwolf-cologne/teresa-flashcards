//
//  AISubscriptionManager.swift
//  Flashcards
//
//  Created by Codex on 26.05.26.
//

import Foundation
import StoreKit
import Combine

@MainActor
final class AISubscriptionManager: ObservableObject {
    static let monthlyProductID = "flashcards_ai_monthly"

    @Published private(set) var products: [Product] = []
    @Published private(set) var hasActiveSubscription = false
    @Published private(set) var currentEntitlementJWS: String?
    @Published private(set) var isLoading = false
    @Published var statusMessage: String?

    private var updatesTask: Task<Void, Never>?

    var monthlyProduct: Product? {
        products.first { $0.id == Self.monthlyProductID }
    }

    var monthlyPriceText: String {
        monthlyProduct?.displayPrice ?? String(localized: "Preis wird geladen")
    }

    init() {
        updatesTask = listenForTransactions()
        Task {
            await refresh()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func refresh() async {
        isLoading = true
        statusMessage = nil
        defer { isLoading = false }

        await loadProducts()
        await updateSubscriptionStatus()
    }

    func purchaseMonthlySubscription() async {
        isLoading = true
        defer { isLoading = false }

        if monthlyProduct == nil {
            await loadProducts()
        }

        guard let product = monthlyProduct else {
            if products.isEmpty {
                statusMessage = String(localized: "Das KI-Abo ist gerade nicht verfügbar. Bitte versuche es später erneut.")
            }
            return
        }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verificationResult):
                let transaction = try checkVerified(verificationResult)
                await transaction.finish()
                await updateSubscriptionStatus()
                statusMessage = hasActiveSubscription ? String(localized: "KI-Funktionen sind aktiviert.") : String(localized: "Der Kauf wurde verarbeitet.")
            case .userCancelled:
                statusMessage = String(localized: "Kauf abgebrochen.")
            case .pending:
                statusMessage = String(localized: "Der Kauf wartet noch auf Bestätigung.")
            @unknown default:
                statusMessage = String(localized: "Der Kauf konnte nicht abgeschlossen werden.")
            }
        } catch {
            statusMessage = String(localized: "Der Kauf konnte nicht abgeschlossen werden: \(error.localizedDescription)")
        }
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
            statusMessage = hasActiveSubscription ? String(localized: "Käufe wiederhergestellt.") : String(localized: "Kein aktives KI-Abo gefunden.")
        } catch StoreKitError.userCancelled {
            statusMessage = String(localized: "Wiederherstellung abgebrochen.")
        } catch is CancellationError {
            statusMessage = String(localized: "Wiederherstellung abgebrochen.")
        } catch {
            statusMessage = String(localized: "Käufe konnten nicht wiederhergestellt werden: \(error.localizedDescription)")
        }
    }

    private func loadProducts() async {
        do {
            products = try await Product.products(for: [Self.monthlyProductID])
            if products.isEmpty {
                statusMessage = String(localized: "Das KI-Abo konnte gerade nicht geladen werden. In TestFlight kann das einige Minuten nach dem Upload dauern.")
            }
        } catch {
            products = []
            statusMessage = String(localized: "Store-Produkte konnten nicht geladen werden: \(error.localizedDescription)")
        }
    }

    private func updateSubscriptionStatus() async {
        var hasSubscription = false
        var entitlementJWS: String?

        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else {
                continue
            }

            guard transaction.productID == Self.monthlyProductID,
                  transaction.revocationDate == nil,
                  transaction.expirationDate.map({ $0 > Date() }) ?? true else {
                continue
            }

            hasSubscription = true
            entitlementJWS = entitlement.jwsRepresentation
            break
        }

        hasActiveSubscription = hasSubscription
        currentEntitlementJWS = entitlementJWS
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }

                do {
                    let transaction = try self.checkVerified(update)
                    await transaction.finish()
                    await self.updateSubscriptionStatus()
                } catch {
                    await MainActor.run {
                        self.statusMessage = String(localized: "Ein Store-Update konnte nicht geprüft werden.")
                    }
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw StoreError.failedVerification
        }
    }
}

private enum StoreError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        String(localized: "Der Kauf konnte nicht verifiziert werden.")
    }
}
