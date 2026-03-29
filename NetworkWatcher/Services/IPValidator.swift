import Foundation

struct IPValidationResult {
    var matched: Bool
    var isVPN: Bool
}

struct IPValidator {
    static func validate(ip: String, against entries: [AllowedIPEntry]) -> IPValidationResult {
        for entry in entries {
            let range = entry.range
            if range.trimmingCharacters(in: .whitespaces) == "*" {
                return IPValidationResult(matched: true, isVPN: entry.isVPN)
            } else if range.contains("/") {
                if matchesCIDR(ip: ip, cidr: range) {
                    return IPValidationResult(matched: true, isVPN: entry.isVPN)
                }
            } else {
                if ip == range.trimmingCharacters(in: .whitespaces) {
                    return IPValidationResult(matched: true, isVPN: entry.isVPN)
                }
            }
        }
        return IPValidationResult(matched: false, isVPN: false)
    }

    static func matchesCIDR(ip: String, cidr: String) -> Bool {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2,
              let prefixLength = Int(parts[1]),
              prefixLength >= 0 && prefixLength <= 32,
              let ipNum = ipToUInt32(String(ip)),
              let networkNum = ipToUInt32(String(parts[0])) else {
            return false
        }

        let mask: UInt32 = prefixLength == 0 ? 0 : ~UInt32(0) << (32 - prefixLength)
        return (ipNum & mask) == (networkNum & mask)
    }

    static func ipToUInt32(_ ip: String) -> UInt32? {
        let octets = ip.trimmingCharacters(in: .whitespaces).split(separator: ".")
        guard octets.count == 4 else { return nil }

        var result: UInt32 = 0
        for octet in octets {
            guard let value = UInt8(octet) else { return nil }
            result = (result << 8) | UInt32(value)
        }
        return result
    }

    static func isValidIPOrCIDR(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        if trimmed == "*" {
            return true
        } else if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/")
            guard parts.count == 2,
                  let prefix = Int(parts[1]),
                  prefix >= 0 && prefix <= 32,
                  ipToUInt32(String(parts[0])) != nil else {
                return false
            }
            return true
        } else {
            return ipToUInt32(trimmed) != nil
        }
    }
}
