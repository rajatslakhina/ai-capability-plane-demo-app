import Foundation
import CapabilityPlane
import CapabilityPlaneUI

/// The compiled-in fleet, residency policy and eval scores for the demo.
/// In production this config would arrive remotely (versioned), with this copy
/// as the last-known-good fallback shipped in the binary.
@MainActor
enum DemoFleet {
    // Force-unwraps below are on two-letter ASCII literals, which `CountryCode.init?`
    // provably accepts (it rejects only non-two-letter or non-ASCII-letter input).
    nonisolated static let us = CountryCode("US")!
    nonisolated static let cn = CountryCode("CN")!
    nonisolated static let de = CountryCode("DE")!
    nonisolated static let india = CountryCode("IN")!

    static let allCapabilities = Set(Capability.allCases)

    static let apple = ProviderDescriptor(
        id: "apple.ondevice", displayName: "Apple Intelligence (on-device)", kind: .onDevice, processing: .onDevice,
        // China: Writing Tools + translation from iOS 27.3, no assistant at launch.
        offers: [.china: ProviderOffer(capabilities: [.summarize, .translate, .rewrite], minimumOS: OSVersion(27, 3))],
        defaultOffer: ProviderOffer(capabilities: allCapabilities, minimumOS: OSVersion(27, 0)),
        requiresNetwork: false, relativeCost: 0)

    static let regionalCN = ProviderDescriptor(
        id: "regional.cn", displayName: "Regional cloud (CN-hosted)", kind: .regionalCloud, processing: .hostedIn(.china),
        offers: [.china: ProviderOffer(capabilities: [.summarize, .translate, .extract, .rewrite])],
        defaultOffer: nil, requiresNetwork: true, relativeCost: 2)

    static let regionalEU = ProviderDescriptor(
        id: "regional.eu", displayName: "Regional cloud (EU-hosted)", kind: .regionalCloud, processing: .hostedIn(.europeanUnion),
        offers: [.europeanUnion: ProviderOffer(capabilities: [.summarize, .translate, .extract, .rewrite])],
        defaultOffer: nil, requiresNetwork: true, relativeCost: 2)

    static let claude = ProviderDescriptor(
        id: "claude.us", displayName: "Claude (US-hosted)", kind: .frontierCloud, processing: .hostedIn(.unitedStates),
        defaultOffer: ProviderOffer(capabilities: allCapabilities), excluded: [.china],
        requiresNetwork: true, relativeCost: 5)

    static let residency = ResidencyPolicy(rules: [
        .unitedStates: [.publicContent: [.hostedIn(.unitedStates), .hostedIn(.europeanUnion)],
                        .personal: [.hostedIn(.unitedStates)], .sensitive: []],
        .europeanUnion: [.publicContent: [.hostedIn(.europeanUnion), .hostedIn(.unitedStates)],
                         .personal: [.hostedIn(.europeanUnion)], .sensitive: []],
        .china: [.publicContent: [.hostedIn(.china)], .personal: [.hostedIn(.china)], .sensitive: []],
        .restOfWorld: [.publicContent: [.hostedIn(.unitedStates), .hostedIn(.europeanUnion)],
                       .personal: [.hostedIn(.unitedStates)], .sensitive: []],
    ])

    /// Optional launch arguments for scripted screenshots and UI tests, e.g.
    /// `-storefront CN -os 27.2 -outage apple.ondevice -autorun YES`.
    /// Anything missing or invalid falls back to the defaults (US, iOS 27.2, no outage).
    struct LaunchScenario {
        var storefront: CountryCode
        var deviceRegion: CountryCode
        var osVersion: OSVersion
        var outage: String?
        var autorun: Bool

        init(defaults: UserDefaults = .standard) {
            storefront = defaults.string(forKey: "storefront").flatMap(CountryCode.init) ?? DemoFleet.us
            deviceRegion = defaults.string(forKey: "region").flatMap(CountryCode.init) ?? storefront
            osVersion = defaults.string(forKey: "os").flatMap { OSVersion(string: $0) } ?? OSVersion(27, 2)
            outage = defaults.string(forKey: "outage")
            autorun = defaults.bool(forKey: "autorun")
        }
    }

    static func makeConsoleModel(scenario: LaunchScenario = LaunchScenario()) -> CapabilityConsoleModel {
        var outages: [String: FailureSwitch] = [:]
        let adapters: [any ProviderAdapter] = [apple, regionalCN, regionalEU, claude].map { descriptor in
            let failure = FailureSwitch(isOn: descriptor.id == scenario.outage)
            outages[descriptor.id] = failure
            return SimulatedProviderAdapter(descriptor: descriptor, failure: failure, latency: .milliseconds(350))
        }

        var parity = ParityLedger()
        parity.record(0.91, jurisdiction: .unitedStates, capability: .summarize, providerID: apple.id)
        parity.record(0.84, jurisdiction: .china, capability: .summarize, providerID: apple.id)
        parity.record(0.78, jurisdiction: .china, capability: .summarize, providerID: regionalCN.id)
        parity.record(0.88, jurisdiction: .europeanUnion, capability: .summarize, providerID: regionalEU.id)
        parity.record(0.93, jurisdiction: .unitedStates, capability: .translate, providerID: claude.id)
        parity.record(0.71, jurisdiction: .china, capability: .translate, providerID: regionalCN.id)

        let context = RegionContext(storefront: scenario.storefront, deviceRegion: scenario.deviceRegion,
                                    osVersion: scenario.osVersion)
        let plane = CapabilityPlane(
            adapters: adapters,
            config: PlaneConfig(version: 1, residency: residency, parityFloor: 0.6),
            context: context,
            jurisdictionMap: JurisdictionMap(mapping: [us: .unitedStates, cn: .china, de: .europeanUnion]),
            parity: parity,
            health: HealthBoard(failureThreshold: 2, cooldown: 20))

        return CapabilityConsoleModel(
            plane: plane, initialContext: context, countries: [us, cn, de, india],
            osVersions: [OSVersion(27, 2), OSVersion(27, 3)], outageSwitches: outages,
            sampleInput: "Meeting notes from Tuesday. The launch moves to March. Legal review is pending.",
            runOnAppear: scenario.autorun)
    }
}
