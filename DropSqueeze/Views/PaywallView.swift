import AppKit
import StoreKit
import SwiftUI

struct PaywallView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var purchaseManager: PurchaseManager
    let onClose: () -> Void
    @State private var isShowingPrivacy = false

    private var request: PaywallRequest? { model.paywallRequest }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }

            Image(systemName: purchaseManager.isPro ? "checkmark.seal.fill" : "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
            Text(purchaseManager.isPro ? "Pro 已解锁" : (request?.reason.title ?? "解锁 DropSqueeze Pro"))
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(purchaseManager.isPro
                 ? "感谢支持 DropSqueeze。所有 Pro 规则和无限自动额度现已启用。"
                 : (request?.reason.detail ?? "解锁无限自动压缩、批量处理、多文件夹监控和高级格式规则。"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !purchaseManager.isPro {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.forward.and.arrow.up.backward")
                    Text("本周已为你节省")
                    Spacer()
                    Text(model.formattedSize(request?.weeklySavedBytes ?? model.weeklySavedBytes))
                        .fontWeight(.semibold)
                }
                .font(.callout)
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

                productOptions

                if let status = purchaseManager.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button("恢复购买") {
                    Task { await purchaseManager.restorePurchases() }
                }
                .disabled(purchaseManager.isPurchasing)

                if purchaseManager.products.contains(where: { $0.type == .autoRenewable }) {
                    Text("订阅将按 App Store 页面显示的周期自动续费，可在 Apple ID 订阅设置中随时取消。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 14) {
                    if let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                        Link("使用条款", destination: termsURL)
                    }
                    Button("隐私政策") { isShowingPrivacy = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                }
                .font(.caption2)
            } else {
                Button("完成") { onClose() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 440, height: 540)
        .task {
            await purchaseManager.loadProducts()
            await purchaseManager.refreshEntitlements()
        }
        .sheet(isPresented: $isShowingPrivacy) {
            PrivacyPolicyView()
        }
    }

    @ViewBuilder
    private var productOptions: some View {
        if purchaseManager.isLoadingProducts {
            ProgressView("正在读取 App Store 商品…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        } else if purchaseManager.products.isEmpty {
            VStack(spacing: 8) {
                Text(purchaseManager.statusMessage ?? "当前没有可用的 Pro 商品。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("重新加载") { Task { await purchaseManager.retryLoadingProducts() } }
                    .disabled(purchaseManager.isPurchasing)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        } else {
            VStack(spacing: 9) {
                ForEach(purchaseManager.products) { product in
                    Button {
                        Task { await purchaseManager.purchase(product) }
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(product.displayName).fontWeight(.semibold)
                                Text(product.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Text(billingDescription(for: product))
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 6)
                            Text(product.displayPrice).fontWeight(.bold)
                        }
                        .padding(12)
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.accentColor.opacity(product.type == .nonConsumable ? 0.6 : 0.25), lineWidth: 1)
                    }
                    .disabled(purchaseManager.isPurchasing)
                }
            }
            if purchaseManager.isPurchasing {
                ProgressView("正在处理购买…").controlSize(.small)
            }
        }
    }

    private func billingDescription(for product: Product) -> String {
        guard product.type == .autoRenewable else { return "一次购买，不会续费" }
        guard let period = product.subscription?.subscriptionPeriod else {
            return "自动续费周期以 App Store 商品页面为准"
        }
        let unit: String
        switch period.unit {
        case .day: unit = "天"
        case .week: unit = "周"
        case .month: unit = "个月"
        case .year: unit = "年"
        @unknown default: return "自动续费周期以 App Store 商品页面为准"
        }
        if period.value == 1 { return "每\(unit)自动续费" }
        return "每 \(period.value) \(unit) 自动续费"
    }
}

@MainActor
final class PaywallWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        self.window = window
        super.init()
        window.title = "DropSqueeze Pro"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: PaywallView(
            model: model,
            purchaseManager: model.purchaseManager,
            onClose: { [weak self] in self?.window.close() }
        ))
        window.delegate = self
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        model.dismissPaywall()
    }
}
