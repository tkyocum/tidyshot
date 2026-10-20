import Foundation

/// Where a capture's object was written: enough of the destination to address the object again
/// after the Upload tab has been edited. Credentials are not part of it; a delete signs with
/// whatever credentials are stored at the time.
nonisolated struct ObjectLocation: Codable, Equatable, Sendable {
    var endpoint: String
    var region: String
    var bucket: String
    /// The path style actually used, including the automatic one for bucket names with a dot.
    var usePathStyle: Bool

    init(endpoint: String, region: String, bucket: String, usePathStyle: Bool) {
        self.endpoint = endpoint
        self.region = region
        self.bucket = bucket
        self.usePathStyle = usePathStyle
    }

    /// The location `config` writes to.
    init(config: S3DestinationConfig) {
        let clean = config.normalized
        self.init(endpoint: clean.endpoint, region: clean.region, bucket: clean.bucket, usePathStyle: config.effectivePathStyle)
    }

    /// A destination configuration that addresses this location. Its public URL template is
    /// empty, so it is only good for signed `HEAD` and `DELETE` requests, which is all a delete needs.
    var config: S3DestinationConfig {
        S3DestinationConfig(endpoint: endpoint, region: region, bucket: bucket, usePathStyle: usePathStyle, publicURLTemplate: "")
    }
}
