//
//  RepositoryErrors.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation

/// Repository-layer errors used by SwiftData and future data sources.
enum RepositoryError: Error {
    /// Requested entity was not found in storage.
    case notFound
    
    /// Storage is in an unexpected state (e.g. missing required IDs).
    case invalidState(String)
}
