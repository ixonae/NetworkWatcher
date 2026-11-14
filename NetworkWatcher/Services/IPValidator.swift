import Foundation

struct IPValidationResult {
    var matched: Bool
    var isVPN: Bool
}

/// A parsed IPv4 (4 bytes) or IPv6 (16 bytes) address.
struct ParsedIP: Equatable {
    let bytes: [UInt8]

    var isIPv6: Bool { bytes.count == 16 }
    var bitCount: Int { bytes.count * 8 }
}

struct IPValidator {
    static func validate(ip: String, against entries: [AllowedIPEntry]) -> IPValidationResult {
        for entry in entries {
            let range = entry.range.trimmingCharacters(in: .whitespaces)
            let matched: Bool
            if range == "*" {
                matched = true
            } else if range.contains("/") {
                matched = matchesCIDR(ip: ip, cidr: range)
            } else if let address = parse(ip), let expected = parse(range) {
                // Compare parsed addresses so "2001:DB8::1" equals "2001:db8:0:0::1".
                matched = address == expected
            } else {
                matched = false
            }
            if matched {
                return IPValidationResult(matched: true, isVPN: entry.isVPN)
            }
        }
        return IPValidationResult(matched: false, isVPN: false)
    }

    /// True when `ip` falls inside `cidr`. An IPv4 address never matches an IPv6 range, or vice versa.
    static func matchesCIDR(ip: String, cidr: String) -> Bool {
        guard let (network, prefixLength) = parseCIDR(cidr),
              let address = parse(ip),
              address.isIPv6 == network.isIPv6 else {
            return false
        }

        var remaining = prefixLength
        for (addressByte, networkByte) in zip(address.bytes, network.bytes) where remaining > 0 {
            let bits = min(remaining, 8)
            let mask = UInt8(truncatingIfNeeded: 0xFF << (8 - bits))
            if addressByte & mask != networkByte & mask {
                return false
            }
            remaining -= bits
        }
        return true
    }

    /// Parses a plain IPv4 or IPv6 address (no prefix, no zone). IPv4-mapped IPv6 addresses
    /// such as "::ffff:1.2.3.4" are treated as IPv6, matching how lookup services report them.
    static func parse(_ ip: String) -> ParsedIP? {
        let trimmed = ip.trimmingCharacters(in: .whitespaces)
        // inet_pton reads a C string, so it would stop at a NUL and accept an address followed by junk.
        guard !trimmed.contains("\0") else { return nil }
        if trimmed.contains(":") {
            // Darwin's inet_pton accepts "%zone" suffixes, which are meaningless for external IPs.
            guard !trimmed.contains("%") else { return nil }
            var address = in6_addr()
            guard inet_pton(AF_INET6, trimmed, &address) == 1 else { return nil }
            let bytes = withUnsafeBytes(of: &address) { Array($0) }
            return ParsedIP(bytes: bytes)
        }
        guard let value = ipToUInt32(trimmed) else { return nil }
        return ParsedIP(bytes: withUnsafeBytes(of: value.bigEndian) { Array($0) })
    }

    static func ipToUInt32(_ ip: String) -> UInt32? {
        let octets = ip.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return nil }

        var result: UInt32 = 0
        for octet in octets {
            guard let value = UInt8(octet) else { return nil }
            result = (result << 8) | UInt32(value)
        }
        return result
    }

    /// True for a single IPv4 or IPv6 address; rejects CIDR ranges and "*".
    static func isValidIPAddress(_ input: String) -> Bool {
        parse(input) != nil
    }

    static func isValidIPOrCIDR(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        if trimmed == "*" {
            return true
        } else if trimmed.contains("/") {
            return parseCIDR(trimmed) != nil
        } else {
            return parse(trimmed) != nil
        }
    }

    private static func parseCIDR(_ cidr: String) -> (ParsedIP, Int)? {
        let parts = cidr.trimmingCharacters(in: .whitespaces).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let prefixLength = Int(parts[1]),
              let network = parse(String(parts[0])),
              (0...network.bitCount).contains(prefixLength) else {
            return nil
        }
        return (network, prefixLength)
    }
}
