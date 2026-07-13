//
//  VHLCKSyncable.swift
//  VHLiCloud
//
//  Created by Vincent on 2021/2/19.
//

import Foundation
import CloudKit

/**
 单个同步对象的 同步协议。处理同步对象的新增，修改，删除
 */

public protocol VHLCKSyncable: AnyObject {
    /// CKRecordZone related 。className
    var recordType: String { get }
    var zoneID: CKRecordZone.ID { get }
    
    /// 本地存储
    var zoneChangesToken: CKServerChangeToken? { get set }
    var isCustomZoneCreated: Bool { get set }
    
    /// 触发更新推送至 iCloud；onProgress 每保存一条记录后回调；completion 在 CloudKit 确认成功后回调
    var pipeToEngine: ((_ recordsToStore: [CKRecord], _ recordIDsToDelete: [CKRecord.ID], _ onProgress: (() -> Void)?, _ completion: (() -> Void)?) -> ())? { get set }
    
    /// 本地数据相应操作
    func registerLocalDatabase()
    /// 清除数据（清除已经被标记为删除的数据等）
    func cleanUp()
    
    /// 添加或者修改
    func addOrUpdate(record: CKRecord)
    /// 删除数据
    func delete(recordID: CKRecord.ID)
    
    /// 推送本地数据到 CloudKit
    /// - onPrepare: 同步回调，传入本次实际需推送的 record 数量（用于 Engine 层计算精准进度总数）
    /// - onProgress: 每条 record 保存成功后回调（用于进度上报）
    /// - completion: 整批推送完成后回调
    func pushLocalObjectsToCloudKit(onPrepare: ((Int) -> Void)?, onProgress: (() -> Void)?, completion: (() -> Void)?)
    
    /// CloudKit 成功保存 record 后回调，用于更新本地的 cloudKitSystemFields（增量推送状态跟踪）
    func recordWasSavedToCloudKit(_ record: CKRecord)
    
    /// 处理数据关系
    func resolvePendingRelationships()
    
    /// 本地记录总数（用于同步进度估算）
    var localRecordCount: Int { get }
}

extension VHLCKSyncable {
    func resolvePendingRelationships() { }
    func recordWasSavedToCloudKit(_ record: CKRecord) { }
    var localRecordCount: Int { 0 }
}
