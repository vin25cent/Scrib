import Testing
@testable import ScribInfrastructure

@Test func infrastructureStartsUnconfigured() {
    #expect(InfrastructureRegistry().status == .notConfigured)
}
