//
//  InviteCodeGenerator.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import Foundation

enum InviteCodeGenerator {
    private static let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") // no 0 O 1 I
    
    static func generate(length: Int = 6) -> String {
        var s = ""
        s.reserveCapacity(length)
        for _ in 0..<length {
            s.append(chars.randomElement()!)
        }
        return s
    }
}
