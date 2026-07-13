//
//  VHLCKLogger.swift
//  VHLiCloud
//
//  Created by Copilot on 2026/3/25.
//

import Foundation

/// VHLiCloud 同步框架统一日志工具
/// 通过 VHLCKSyncEngine.isLoggingEnabled 控制开关
public enum VHLCKLogger {

    /// 是否启用日志输出，默认关闭。通过 VHLCKSyncEngine.isLoggingEnabled 设置
    public static var isEnabled: Bool = false

    /// 输出一条日志，自动添加 `📡 [iCloud]` 前缀
    static func log(_ message: String) {
        guard isEnabled else { return }
        #if DEBUG
        print("📡 [iCloud] \(message)")
        #endif
    }
}
