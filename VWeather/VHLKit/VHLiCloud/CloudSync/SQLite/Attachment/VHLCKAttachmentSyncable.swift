//
//  VHLCKAttachmentSyncable.swift
//  VHLiCloud
//
//  Created by Vincent on 2025/1/1.
//

import Foundation
import CloudKit

// MARK: - 附件同步协议

/// 让 VHLSQLiteObject 模型声明哪些字段是 CKAsset 附件字段。
///
/// 采用此协议后，`VHLCKSQLiteCodable` 中的 `encodeRecord` / `decodeRecord`
/// 会通过动态类型检查（`as?`）自动注入附件处理逻辑，无需覆写任何协议方法：
///   - **推送**：通过 `applyAssetPatching(to:)` 将本地文件路径字符串转换为 `CKAsset`
///   - **拉取**：通过 `assetFieldKeys` 动态识别附件字段，将 `CKAsset` 保存到本地并写入路径字符串
///
/// ### 字段类型约定
/// 附件字段在模型中应声明为 **`String?`**，而非 `URL`（SQLite 不支持 `URL` 类型）。
/// 框架负责在 `String`（本地路径）与 `CKAsset`（CloudKit 二进制）之间转换。
///
/// ### 集成步骤
/// 1. 在模型中声明 `var avatarPath: String?`
/// 2. 实现 `assetFieldKeys`，返回所有附件字段名
/// 3. 保存附件时通过 `VHLCKAsset.create(...)` 写入本地，再将 `filePath.absoluteString` 赋给字段
/// 4. 正常调用 `sync()` 即可，框架自动处理 CKAsset 转换
///
/// ### 自定义 encodeRecord()
/// 若模型需要自定义 `encodeRecord()`，在返回 record 前调用 `applyAssetPatching(to:)` 以补全附件处理：
/// ```swift
/// func encodeRecord() -> CKRecord? {
///     guard let record = try? VHLCKRecordEncoder().encode(self) else { return nil }
///     applyAssetPatching(to: record)   // ← 补充附件字段替换
///     return record
/// }
/// ```
public protocol VHLCKAttachmentSyncable {
    /// 模型中所有附件字段的属性名列表。
    ///
    /// 这些字段在 SQLite 中存储文件 URL 路径字符串，在 CloudKit 中存储为 `CKAsset`。
    ///
    /// ```swift
    /// static var assetFieldKeys: [String] { ["coverImagePath", "audioPath"] }
    /// ```
    static var assetFieldKeys: [String] { get }
}

// MARK: - 编码辅助方法

extension VHLCKAttachmentSyncable {

    /// 将 CKRecord 中的附件字段（路径 String）替换为 `CKAsset`。
    ///
    /// `VHLCKSQLiteCodable.encodeRecord()` 通过 `as?` 自动调用此方法。
    /// 若模型自定义了 `encodeRecord()`，需在返回前手动调用此方法。
    public func applyAssetPatching(to record: CKRecord) {
        for key in type(of: self).assetFieldKeys {
            if let pathStr = record[key] as? String,
               let fileURL = URL(string: pathStr),
               fileURL.isFileURL,
               FileManager.default.fileExists(atPath: fileURL.path) {
                record[key] = CKAsset(fileURL: fileURL)
            }
        }
    }
}
