import AppKit
import StoreKit
import SwiftUI

struct PaywallView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var l10n = LocalizationManager.shared
    @ObservedObject var purchaseManager: PurchaseManager
    let onClose: () -> Void
    @State private var isShowingPrivacy = false

    private var request: PaywallRequest? { model.paywallRequest }

    var body: some View {
        VStack(spacing: 16) {
            // Top Close Button
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .help(L10n.tr("关闭"))
            }

            // Hero Brand Badge
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 64, height: 64)
                    .blur(radius: 8)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 8, y: 3)

                Image(systemName: purchaseManager.isPro ? "checkmark.seal.fill" : "sparkles")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
            }

            // Headline
            VStack(spacing: 4) {
                Text(purchaseManager.isPro ? L10n.tr("DropSqueeze Pro 已解锁") : (request?.reason.title ?? L10n.tr("解锁 DropSqueeze Pro")))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)

                Text(purchaseManager.isPro ? L10n.tr("感谢支持！所有 Pro 规则、无限自动压缩与多文件夹监控已全部启用。") : (request?.reason.detail ?? L10n.tr("无限静默压缩、平台硬指标预设、Vision OCR 提取与多文件夹实时监控。")))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }

            if !purchaseManager.isPro {
                // Weekly Savings Banner
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                    Text(L10n.tr("本周已为你累计节省"))
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text(model.formattedSize(request?.weeklySavedBytes ?? model.weeklySavedBytes))
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 0.75)
                )

                // Feature Highlights
                featureHighlightsGrid

                // Product Options List
                productOptions

                if let status = purchaseManager.statusMessage {
                    Text(status)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Restore Button
                Button {
                    Task { await purchaseManager.restorePurchases() }
                } label: {
                    Text(L10n.tr("恢复先前购买"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.tactile)
                .disabled(purchaseManager.isPurchasing)

                if purchaseManager.products.contains(where: { $0.type == .autoRenewable }) {
                    Text(L10n.tr("订阅将按 App Store 页面周期自动续费，可在 Apple ID 订阅管理中随时取消。"))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }

                // Legal links
                HStack(spacing: 12) {
                    if let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                        Link(L10n.tr("使用条款 (EULA)"), destination: termsURL)
                    }
                    Text("·").foregroundStyle(.tertiary)
                    Button(L10n.tr("隐私安全声明")) { isShowingPrivacy = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                }
                .font(.system(size: 10))
            } else {
                Spacer()
                Button(L10n.tr("完成")) { onClose() }
                    .buttonStyle(.tactile)
                    .controlSize(.regular)
            }
        }
        .padding(22)
        .frame(width: 440, height: 560)
        .task {
            await purchaseManager.loadProducts()
            await purchaseManager.refreshEntitlements()
        }
        .sheet(isPresented: $isShowingPrivacy) {
            PrivacyPolicyView()
        }
    }

    // MARK: - Feature Highlights Grid

    private var featureHighlightsGrid: some View {
        HStack(spacing: 8) {
            featurePill(title: L10n.tr("无限静默压缩"), icon: "infinity")
            featurePill(title: L10n.tr("录屏静音压制"), icon: "speaker.slash.fill")
            featurePill(title: L10n.tr("端侧 OCR 提取"), icon: "text.viewfinder")
            featurePill(title: L10n.tr("多目录自动监控"), icon: "folder.badge.gearshape")
        }
    }

    private func featurePill(title: String, icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.75)
        )
    }

    // MARK: - Product Options

    @ViewBuilder
    private var productOptions: some View {
        if purchaseManager.isLoadingProducts {
            ProgressView(L10n.tr("正在读取 App Store 商品…"))
                .font(.system(size: 11))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        } else if purchaseManager.products.isEmpty {
            VStack(spacing: 6) {
                Text(purchaseManager.statusMessage ?? L10n.tr("当前没有可用的 Pro 商品。"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(L10n.tr("重新连接")) { Task { await purchaseManager.retryLoadingProducts() } }
                    .buttonStyle(.tactile)
                    .controlSize(.small)
                    .disabled(purchaseManager.isPurchasing)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } else {
            VStack(spacing: 8) {
                ForEach(purchaseManager.products) { product in
                    Button {
                        Task { await purchaseManager.purchase(product) }
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(product.displayName)
                                        .font(.system(size: 12, weight: .bold))
                                    if product.type == .nonConsumable {
                                        StatusBadge(title: L10n.tr("终身买断"), color: .accentColor, isSubtle: true)
                                    }
                                }
                                Text(product.description)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Text(billingDescription(for: product))
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 6)
                            Text(product.displayPrice)
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    Color.accentColor.opacity(product.type == .nonConsumable ? 0.6 : 0.25),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.tactile)
                    .disabled(purchaseManager.isPurchasing)
                }
            }

            if purchaseManager.isPurchasing {
                ProgressView(L10n.tr("正在安全处理购买…"))
                    .font(.system(size: 10))
                    .controlSize(.small)
            }
        }
    }

    private func billingDescription(for product: Product) -> String {
        guard product.type == .autoRenewable else { return L10n.tr("一次性买断，终生使用") }
        guard let period = product.subscription?.subscriptionPeriod else {
            return L10n.tr("自动续费周期以 App Store 商品页面为准")
        }
        let unit: String
        switch period.unit {
        case .day: unit = L10n.tr("天")
        case .week: unit = L10n.tr("周")
        case .month: unit = L10n.tr("个月")
        case .year: unit = L10n.tr("年")
        @unknown default: return L10n.tr("自动续费周期以 App Store 商品页面为准")
        }
        if period.value == 1 { return L10n.tr("每%@自动续费", unit) }
        return L10n.tr("每 %d %@ 自动续费", period.value, unit)
    }
}

@MainActor
final class PaywallWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
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
