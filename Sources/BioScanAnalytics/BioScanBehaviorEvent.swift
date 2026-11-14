/// 跨 App 复用的行为事件名；新增调用优先使用这些常量。
public enum BioScanBehaviorEvent {
    public static let recognitionEntrySelected = "recognition_entry_selected"
    public static let recognitionCropConfirmed = "recognition_crop_confirmed"
    public static let recognitionCropCancelled = "recognition_crop_cancelled"
    public static let resultFavoriteChanged = "result_favorite_changed"
    public static let resultShareRequested = "result_share_requested"
}
