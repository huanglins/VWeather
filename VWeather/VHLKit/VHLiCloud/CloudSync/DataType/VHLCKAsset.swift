//
//  VHLCKAsset.swift
//  VHLiCloud
//
//  Created by Vincent on 2021/2/21.
//

import Foundation
import CloudKit

// MARK: - VHLCKAsset

/// CloudKit 附件的本地文件管理对象。
///
/// `VHLCKAsset` 负责将 CloudKit 的 `CKAsset`（二进制文件）与本地持久化文件路径关联起来。
/// 所有附件文件统一存放在 `Documents/VHLCKAsset/` 目录下，文件名格式为：
/// ```
/// {objectID}_{propName}
/// ```
/// 其中 `objectID` 为记录的 `recordID.recordName`，`propName` 为模型中的属性名。
/// 此命名规则保证同一记录的不同附件字段各自独立，互不干扰。
///
/// ### 典型用法
/// ```swift
/// // 写入附件（从 Data）
/// let asset = VHLCKAsset.create(objectID: note.noteID, propName: "coverImagePath",
///                                data: imageData, sholdOverwrite: true)
/// note.coverImagePath = asset?.filePath.absoluteString
///
/// // 读取附件
/// let data = asset?.storedData()
///
/// // 删除记录关联的所有附件
/// VHLCKAsset.deleteAssetFile(with: note.noteID)
/// ```
public class VHLCKAsset {

    /// 本地文件的唯一名称，格式：`{objectID}_{propName}`。
    @objc dynamic private var uniqueFileName = ""

    /// 附件文件的完整本地路径（位于 `Documents/VHLCKAsset/` 目录下）。
    public var filePath: URL {
        return VHLCKAsset.assetDefaultURL().appendingPathComponent(uniqueFileName)
    }

    /// 读取附件文件的原始数据。文件不存在时返回 `nil`。
    public func storedData() -> Data? {
        return try? Data(contentsOf: filePath)
    }

    /// 将本地文件包装为 `CKAsset`，用于上传到 CloudKit。
    var asset: CKAsset {
        return CKAsset(fileURL: filePath)
    }

    /// 通过 objectID + propName 构造唯一文件名。
    fileprivate convenience init(objectID: String, propName: String) {
        self.init()
        self.uniqueFileName = "\(objectID)_\(propName)"
    }
}

// MARK: - CloudKit 解析

extension VHLCKAsset {

    /// 将 CloudKit 拉取到的 `CKAsset` 复制到本地永久存储路径，并返回对应的 `VHLCKAsset`。
    ///
    /// 此方法由 `VHLCKSQLiteCodable.decodeRecord` 在同步拉取时自动调用，无需手动调用。
    ///
    /// - Parameters:
    ///   - propName: 附件对应的模型属性名（用于构造唯一文件名）
    ///   - record: 包含该附件的 `CKRecord`（用于获取 `recordID.recordName`）
    ///   - asset: CloudKit 返回的 `CKAsset`（含临时下载文件路径）
    /// - Returns: 成功复制后的 `VHLCKAsset`；若 `CKAsset.fileURL` 为 nil（文件未下载）则返回 `nil`
    static func parse(from propName: String, record: CKRecord, asset: CKAsset) -> VHLCKAsset? {
        guard let url = asset.fileURL else { return nil }
        return create(objectID: record.recordID.recordName,
                      propName: propName,
                      url: url,
                      shouldOverwrite: true)
    }

    /// 将数据写入本地附件目录，供 `create` 工厂方法使用。
    fileprivate static func save(data: Data, to path: String, shouldOverwrite: Bool) throws {
        let url = assetDefaultURL().appendingPathComponent(path)
        guard shouldOverwrite || !FileManager.default.fileExists(atPath: url.path) else { return }
        try data.write(to: url)
    }
}

// MARK: - 工厂方法

extension VHLCKAsset {

    /// 将 `Data` 写入本地附件目录并返回 `VHLCKAsset`。
    ///
    /// - Parameters:
    ///   - objectID: 记录的唯一标识（建议使用 `recordID.recordName`，即 UUID 字符串）
    ///   - propName: 附件对应的模型属性名
    ///   - data: 要写入的文件数据
    ///   - sholdOverwrite: 若本地已存在同名文件，是否覆盖；默认为 `true`
    /// - Returns: 成功时返回 `VHLCKAsset`，写入失败时返回 `nil`
    public static func create(objectID: String,
                              propName: String,
                              data: Data,
                              sholdOverwrite: Bool = true) -> VHLCKAsset? {
        let asset = VHLCKAsset(objectID: objectID, propName: propName)
        do {
            try save(data: data, to: asset.uniqueFileName, shouldOverwrite: sholdOverwrite)
            return asset
        } catch {
            return nil
        }
    }

    /// 将 `Data` 写入本地附件目录并返回 `VHLCKAsset`（通过 `VHLCKRecordCodable` 对象传入 objectID）。
    ///
    /// - Parameters:
    ///   - object: 实现了 `VHLCKRecordCodable` 的模型实例，其 `recordID.recordName` 作为 objectID
    ///   - propName: 附件对应的模型属性名
    ///   - data: 要写入的文件数据
    ///   - shouldOverwrite: 若本地已存在同名文件，是否覆盖；默认为 `true`
    /// - Returns: 成功时返回 `VHLCKAsset`，写入失败时返回 `nil`
    public static func create(object: any VHLCKRecordCodable,
                              propName: String,
                              data: Data,
                              shouldOverwrite: Bool = true) -> VHLCKAsset? {
        return create(objectID: object.recordID.recordName,
                      propName: propName,
                      data: data,
                      sholdOverwrite: shouldOverwrite)
    }

    /// 将指定 URL 的文件复制到本地附件目录并返回 `VHLCKAsset`。
    ///
    /// - Parameters:
    ///   - objectID: 记录的唯一标识（建议使用 `recordID.recordName`，即 UUID 字符串）
    ///   - propName: 附件对应的模型属性名
    ///   - url: 源文件 URL（可以是任意本地路径，包括 CloudKit 的临时下载路径）
    ///   - shouldOverwrite: 若本地已存在同名文件，是否先删除再复制；默认为 `true`
    /// - Returns: `VHLCKAsset` 实例（若复制失败，`filePath` 处的文件可能不存在）
    public static func create(objectID: String,
                              propName: String,
                              url: URL,
                              shouldOverwrite: Bool = true) -> VHLCKAsset? {
        let asset = VHLCKAsset(objectID: objectID, propName: propName)
        if shouldOverwrite {
            try? FileManager.default.removeItem(at: asset.filePath)
        }
        if !FileManager.default.fileExists(atPath: asset.filePath.path) {
            try? FileManager.default.copyItem(at: url, to: asset.filePath)
        }
        return asset
    }

    /// 将指定 URL 的文件复制到本地附件目录并返回 `VHLCKAsset`（通过 `VHLCKRecordCodable` 对象传入 objectID）。
    ///
    /// - Parameters:
    ///   - object: 实现了 `VHLCKRecordCodable` 的模型实例，其 `recordID.recordName` 作为 objectID
    ///   - propName: 附件对应的模型属性名
    ///   - url: 源文件 URL
    ///   - shouldOverwrite: 若本地已存在同名文件，是否先删除再复制；默认为 `true`
    /// - Returns: `VHLCKAsset` 实例（若复制失败，`filePath` 处的文件可能不存在）
    public static func create(object: any VHLCKRecordCodable,
                              propName: String,
                              url: URL,
                              shouldOverwrite: Bool = true) -> VHLCKAsset? {
        return create(objectID: object.recordID.recordName,
                      propName: propName,
                      url: url,
                      shouldOverwrite: shouldOverwrite)
    }
}

// MARK: - 目录与文件管理

extension VHLCKAsset {

    /// 返回指定名称的附件子目录 URL，目录不存在时自动创建。
    ///
    /// - Parameter name: 子目录名称
    /// - Returns: `Documents/{name}/` 的 URL
    public static func assetURL(with name: String) -> URL {
        let documentDir = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let commonAssetPath = documentDir.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: commonAssetPath.path) {
            try? FileManager.default.createDirectory(at: commonAssetPath, withIntermediateDirectories: false, attributes: nil)
        }
        return commonAssetPath
    }

    /// 返回默认附件目录 URL（`Documents/VHLCKAsset/`），目录不存在时自动创建。
    public static func assetDefaultURL() -> URL {
        let dirName = String(describing: type(of: self))
        return assetURL(with: dirName)
    }

    /// 返回默认附件目录中所有文件的文件名列表。
    public static func assetFilesPaths() -> [String] {
        do {
            return try FileManager.default.contentsOfDirectory(atPath: VHLCKAsset.assetDefaultURL().path)
        } catch {
            return []
        }
    }

    /// 删除与指定 `objectID` 关联的所有本地附件文件。
    ///
    /// 文件名以 `{objectID}_` 为前缀，删除时会匹配所有包含该 ID 的文件。
    /// 通常在软删除记录并同步到 CloudKit 后调用，用于清理本地磁盘占用。
    ///
    /// - Parameter id: 记录的唯一标识（`recordID.recordName`）
    public static func deleteAssetFile(with id: String) {
        let needToDeleteCacheFiles = assetFilesPaths().filter { $0.contains(id) }
        excecuteDeletions(in: needToDeleteCacheFiles)
    }

    /// 批量删除指定文件名列表对应的本地附件文件。
    fileprivate static func excecuteDeletions(in fileNames: [String]) {
        for filename in fileNames {
            let absolutePath = assetDefaultURL().appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: absolutePath)
        }
    }
}
