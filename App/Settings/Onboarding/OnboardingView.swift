import AppKit
import Integrations
import NotchShell
import SwiftUI

struct OnboardingView: View {
    let coordinator: AppCoordinator
    let model: OnboardingModel
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.step {
                case 0: intro
                case 1: profiles
                default: permissions
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 32)
            .padding(.top, 36)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(model.step)
            footer
        }
        .frame(width: 600, height: 480)
        .animation(.spring(duration: 0.35, bounce: 0), value: model.step)
    }

    // MARK: Adımlar

    private var intro: some View {
        VStack(spacing: 18) {
            NotchIllustration()
            Text("Notch'unuz artık işe yarıyor").font(.title.weight(.semibold))
            VStack(alignment: .leading, spacing: 12) {
                tip("cursorarrow.motionlines", "Üzerine gelin", "İmleci çentiğin üstüne getirince açılır; tıklarsanız açık kalır.")
                tip("hand.draw", "Kaydırın", "İki parmakla aşağı kaydırmak açar, yukarı kaydırmak kapatır.")
                tip("doc.on.doc", "Sürükleyin", "Dosyaları ve ekran görüntüsü küçük resimlerini çentiğe bırakınca rafa girer.")
            }
            .frame(maxWidth: 440)
        }
    }

    private var profiles: some View {
        VStack(spacing: 14) {
            Text("Notch'u nasıl kullanacaksınız?").font(.title2.weight(.semibold))
            Text("Birden çok seçebilirsiniz; seçtiklerinizin özellikleri açılır. Hepsi sonra Ayarlar'dan değişir.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(OnboardingProfile.allCases) { profile in
                    ProfileCard(profile: profile, isSelected: model.profiles.contains(profile)) {
                        if model.profiles.contains(profile) { model.profiles.remove(profile) } else { model.profiles.insert(profile) }
                    }
                }
            }
            Text("Pil, uyanık tutma, not ve zamanlayıcı her durumda açık.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var permissions: some View {
        let center = coordinator.permissions
        let needed = PermissionKind.allCases.filter(center.isNeeded).filter { center.status($0) != .granted }
        return VStack(spacing: 14) {
            Text(needed.isEmpty ? "Her şey hazır" : "Birkaç izin").font(.title2.weight(.semibold))
            Text(needed.isEmpty
                 ? "Seçtiğiniz özellikler için ek izin gerekmiyor."
                 : "Yalnız seçtiğiniz özellikler için. İsterseniz şimdi verin, isterseniz sonra; her izin ilgili ayar sayfasında da durur.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if needed.isEmpty {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)
                    .padding(.top, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(needed) { kind in
                        PermissionRow(kind: kind, center: center, showsIcon: true)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                        if kind != needed.last { Divider().padding(.leading, 50) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
                Label("İzin verilen veri bu Mac'te kalır; hiçbir yere gönderilmez.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { center.refresh() }
    }

    private func tip(_ symbol: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Alt çubuk

    private var footer: some View {
        HStack {
            // Adım noktaları.
            HStack(spacing: 6) {
                ForEach(0..<OnboardingModel.stepCount, id: \.self) { index in
                    Circle()
                        .fill(index == model.step ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: 6, height: 6)
                }
            }
            Spacer()
            if model.step == 0 {
                Button("Atla") { finish() }
                    .help("Ayarlara dokunmadan kapatır")
            } else {
                Button("Geri") { model.step -= 1 }
            }
            Button(primaryTitle) { advance() }
                .keyboardShortcut(.defaultAction)
                .disabled(model.step == 1 && model.profiles.isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.bar)
    }

    private var primaryTitle: LocalizedStringKey {
        switch model.step {
        case 0: "Başlayalım"
        case 1: "Uygula"
        default: "Bitir"
        }
    }

    private func advance() {
        switch model.step {
        case 1:
            OnboardingProfile.apply(model.profiles, to: coordinator.settings)
            AppLog.coordinator.notice("karşılama: \(model.profiles.map(\.rawValue).sorted().joined(separator: ","), privacy: .public) profilleri uygulandı")
            model.step = 2
        case OnboardingModel.stepCount - 1:
            finish()
        default:
            model.step += 1
        }
    }
}

private struct ProfileCard: View {
    let profile: OnboardingProfile
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 10) {
                SettingsIcon(symbol: profile.symbol, tint: profile.tint, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: profile.title).font(.headline)
                    Text(verbatim: profile.detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Karşılamanın üstündeki küçük notch çizimi: menü çubuğu ve açılmış notch.
private struct NotchIllustration: View {
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Color.blue.opacity(0.55), Color.purple.opacity(0.45)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 300, height: 92)
            UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16, style: .continuous)
                .fill(.black)
                .frame(width: 190, height: 58)
                .overlay(alignment: .center) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.orange.gradient).frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 3) {
                            Capsule().fill(.white.opacity(0.85)).frame(width: 70, height: 5)
                            Capsule().fill(.white.opacity(0.4)).frame(width: 48, height: 5)
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 2) {
                            ForEach([0.5, 0.9, 0.65, 0.4], id: \.self) { scale in
                                Capsule().fill(.white.opacity(0.8)).frame(width: 2.5, height: 14 * scale)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                }
        }
        .accessibilityHidden(true)
    }
}
