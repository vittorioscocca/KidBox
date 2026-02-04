//
//  HomeView.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import SwiftUI

struct HomeView: View {
    var body: some View {
        Text("KidBox Home")
            .navigationTitle("KidBox")
    }
}

#Preview {
    NavigationStack { HomeView() }
}
