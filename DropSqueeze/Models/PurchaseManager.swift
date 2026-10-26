import Combine
import Foundation
import StoreKit

enum ProProductID {
    static let annual = "com.dropsqueeze.pro.annual"
    static let lifetime = "com.dropsqueeze.pro.lifetime"
    static let all = [annual, lifetime]
}

@MainActor
final class PurchaseManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var isPro = false
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var statusMessage: String?

    var onEntitlementChanged: ((Bool) -> Void)?

    private var transactionUpdatesTask: Task<Void, Never>?

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func start() {
        guard transactionUpdatesTask == nil else { return }
        transactionUpdatesTask = Task { [weak self] in
            guard let self else { return }
            await self.observeTransactionUpdates()
        }
        Task { await loadProducts() }
    }

    func loadProducts() async {
        guard products.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: ProProductID.all)
            products = loaded.sorted { left, right in
                left.id == ProProductID.lifetime && right.id != ProProductID.lifetime
            }
            if products.isEmpty {
                statusMessage = "商店暂时没有可用的 Pro 商品，请稍后重试。"
            }
        } catch {
            statusMessage = "无法加载 App Store 商品：\(error.localizedDescription)"
        }
    }

    func retryLoadingProducts() async {
        products = []
        statusMessage = nil
        await loadProducts()
    }

    func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        statusMessage = nil
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                let transaction = try verified(verification)
                await refreshEntitlements()
                await transaction.finish()
                statusMessage = isPro ? "DropSqueeze Pro 已解锁。" : "购买已完成，正在更新权限。"
            case .pending:
                statusMessage = "购买正在等待批准。"
            case .userCancelled:
                statusMessage = "已取消购买。"
            @unknown default:
                statusMessage = "App Store 返回了未知购买状态。"
            }
        } catch {
            statusMessage = "购买未完成：\(error.localizedDescription)"
        }
    }

    func restorePurchases() async {
        isPurchasing = true
        statusMessage = nil
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            statusMessage = isPro ? "已恢复 Pro 购买。" : "没有找到可恢复的 Pro 购买。"
        } catch {
            statusMessage = "无法恢复购买：\(error.localizedDescription)"
        }
    }

    func refreshEntitlements() async {
        var hasProEntitlement = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if ProProductID.all.contains(transaction.productID) {
                hasProEntitlement = true
            }
        }
        guard isPro != hasProEntitlement else { return }
        isPro = hasProEntitlement
        onEntitlementChanged?(hasProEntitlement)
    }

    private func observeTransactionUpdates() async {
        for await result in Transaction.updates {
            do {
                let transaction = try verified(result)
                await refreshEntitlements()
                await transaction.finish()
            } catch {
                statusMessage = "无法验证 App Store 交易：\(error.localizedDescription)"
            }
        }
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): return value
        case .unverified(_, let error): throw error
        }
    }
}
