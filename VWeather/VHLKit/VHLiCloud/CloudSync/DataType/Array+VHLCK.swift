//
//  VHLCKCategory.swift
//  VHLiCloud
//
//  Created by Vincent on 2021/2/19.
//

import Foundation
import CloudKit

extension Array where Element: CKRecord {
    /// Chunk the big group into smaller ones, with the given chunkSize
    /// For example, we have some dogs(You can test it in the playground):
    ///
    /*  var dogs: [Dog] = []
        for i in 0...22 {
        var dog = Dog(age: i, name: "Dog \(i)")
            dogs.append(dog)
        }
        let chunkedDogs = dogs.chunkItUp(by: 5)
    */
    // 将数组分组
    func chunkItUp(by chunkSize: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: chunkSize).map({ (startIndex) -> [Element] in
            let endIndex = (startIndex.advanced(by: chunkSize) > count) ? count : (startIndex + chunkSize)
            return Array(self[startIndex..<endIndex])
        })
    }
}
