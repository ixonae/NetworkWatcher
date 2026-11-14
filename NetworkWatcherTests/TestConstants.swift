// swiftlint:disable type_body_length
/// Test fixture IP addresses and CIDR ranges. None of these are real endpoints.
enum TestIP { // NOSONAR
    static let stub = "1.2.3.4" // NOSONAR
    static let stubAlt = "1.2.3.5" // NOSONAR
    static let secondary = "5.6.7.8" // NOSONAR
    static let dns = "8.8.8.8" // NOSONAR
    static let zero = "0.0.0.0" // NOSONAR
    static let broadcast = "255.255.255.255" // NOSONAR
    static let private10 = "10.0.0.1" // NOSONAR
    static let private10_50 = "10.0.0.50" // NOSONAR
    static let private10_5 = "10.0.0.5" // NOSONAR
    static let private10Alt = "10.0.1.50" // NOSONAR
    static let private192 = "192.168.1.1" // NOSONAR
    static let private192_100 = "192.168.1.100" // NOSONAR
    static let private192_0 = "192.168.1.0" // NOSONAR
    static let private192_255 = "192.168.1.255" // NOSONAR
    static let private192_2 = "192.168.2.1" // NOSONAR
    static let private172 = "172.16.5.10" // NOSONAR
    static let private172Alt = "172.17.0.1" // NOSONAR
    static let private172_16 = "172.16.0.1" // NOSONAR
    static let private10_2 = "10.0.0.2" // NOSONAR
    static let overflow = "256.1.1.1" // NOSONAR
    static let overflow2 = "256.0.0.0" // NOSONAR
    static let negative = "-1.0.0.0" // NOSONAR

    // CIDR ranges
    static let cidr10_8 = "10.0.0.0/8" // NOSONAR
    static let cidr10_24 = "10.0.0.0/24" // NOSONAR
    static let cidr192_24 = "192.168.1.0/24" // NOSONAR
    static let cidr172_16 = "172.16.0.0/16" // NOSONAR
    static let cidrAll = "0.0.0.0/0" // NOSONAR
    static let cidrHost = "1.2.3.4/32" // NOSONAR
    static let cidrHostSingle = "10.0.0.1/32" // NOSONAR

    // IPv6 (2001:db8::/32 is the documentation range)
    static let v6 = "2001:db8:1:2::10" // NOSONAR
    static let v6Expanded = "2001:0DB8:0001:0002:0000:0000:0000:0010" // NOSONAR
    static let v6SameSubnet = "2001:db8:1:2::ffff" // NOSONAR
    static let v6OtherSubnet = "2001:db8:1:3::10" // NOSONAR
    static let v6Outside = "2001:db9::1" // NOSONAR
    static let v6Loopback = "::1" // NOSONAR
    static let v6Mapped = "::ffff:1.2.3.4" // NOSONAR
    static let cidrV6_32 = "2001:db8::/32" // NOSONAR
    static let cidrV6_48 = "2001:db8:1::/48" // NOSONAR
    static let cidrV6_64 = "2001:db8:1:2::/64" // NOSONAR
    static let cidrV6Host = "2001:db8:1:2::10/128" // NOSONAR
    static let cidrV6All = "::/0" // NOSONAR
}
// swiftlint:enable type_body_length
