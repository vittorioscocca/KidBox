//
//  AuthProvider..swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation

enum AuthProvider: String, CaseIterable, Identifiable {
    case apple
    case google
    
    var id: String { rawValue }
}
