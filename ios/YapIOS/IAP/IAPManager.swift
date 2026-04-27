import StoreKit
import Foundation

// Apple requires IAP for digital subscriptions on iOS.
// This manager handles purchase, restore, and server-side verification.
// The backend needs a POST /v1/apple/verify endpoint that accepts
// { transactionId: String } and upgrades the user's plan on success.
@MainActor
final class IAPManager: ObservableObject {
    static let shared = IAPManager()

    // Match these to your App Store Connect subscription group.
    static let monthlyProductID = "app.yap.YapIOS.pro.monthly"
    static let annualProductID  = "app.yap.YapIOS.pro.annual"

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPurchasing = false
    @Published private(set) var purchaseError: String?
    @Published private(set) var isLoadingProducts = false

    private var transactionListener: Task<Void, Never>?

    private init() {
        transactionListener = listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load products

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            products = try await Product.products(for: [
                Self.monthlyProductID,
                Self.annualProductID,
            ]).sorted { a, b in
                // Monthly before annual in price (for display order)
                a.price < b.price
            }
        } catch {
            purchaseError = "Couldn't load products: \(error.localizedDescription)"
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await verifyWithBackend(transaction: transaction)
                await transaction.finish()
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            try await AppStore.sync()
            await syncActivePurchases(session: SharedSettings.shared.sessionToken ?? "")
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Sync existing purchases (called on sign-in)

    func syncActivePurchases(session: String) async {
        guard !session.isEmpty else { return }
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.monthlyProductID || transaction.productID == Self.annualProductID {
                await verifyWithBackend(transaction: transaction)
                await transaction.finish()
            }
        }
    }

    // MARK: - Transaction listener (handles purchases made outside the app)

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await verifyWithBackend(transaction: transaction)
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: - Backend verification

    private func verifyWithBackend(transaction: Transaction) async {
        guard let session = SharedSettings.shared.sessionToken else { return }
        do {
            try await APIClient.shared.verifyAppleTransaction(
                transactionID: transaction.id,
                session: session
            )
            // Refresh user object so plan badge updates immediately
            await AuthStore.shared.refresh()
        } catch {
            // Non-fatal: the subscription is valid even if the backend call fails;
            // it will be synced on next launch via syncActivePurchases.
        }
    }

    // MARK: - Verification helper

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw IAPError.failedVerification
        case .verified(let value):
            return value
        }
    }
}

enum IAPError: Error, LocalizedError {
    case failedVerification

    var errorDescription: String? {
        "Purchase verification failed."
    }
}
