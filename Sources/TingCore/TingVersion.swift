/// The version of this source tree, for runs without a bundle (`swift run`, `.build/debug/Ting`,
/// tests), where Info.plist gives none. It must equal `MARKETING_VERSION` in `version.env`;
/// a TingCore test fails when the two differ, so a release bumps both.
public enum TingVersion {
    public static let marketing = "0.7.27"
}
