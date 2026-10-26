import Foundation

/// Removes well-known tracking query parameters (utm_*, fbclid, gclid, …) from web links.
public enum LinkCleaner {
    static let trackingPrefixes = ["utm_"]

    static let trackingNames: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid",
        "igshid", "igsh", "li_fat_id", "mc_cid", "mc_eid", "_hsenc", "_hsmi", "mkt_tok", "oly_anon_id",
        "oly_enc_id", "vero_id", "vero_conv", "wickedid", "rb_clickid", "s_cid", "_openstat",
        "pk_campaign", "pk_kwd", "pk_source", "pk_medium", "pk_content",
    ]

    public static func isTrackingParameter(_ name: String) -> Bool {
        let name = name.lowercased()
        return trackingNames.contains(name) || trackingPrefixes.contains { name.hasPrefix($0) }
    }

    public static func removingTrackingParameters(from url: URL) -> URL {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.percentEncodedQueryItems, !items.isEmpty
        else { return url }

        let kept = items.filter { !isTrackingParameter($0.name) }
        guard kept.count != items.count else { return url }
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return components.url ?? url
    }
}
