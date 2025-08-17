//
//  ContentView.swift
//  ChessDuo
//
//  Created by Matthias Jüngel on 10.08.25.
//


import SwiftUI

// Thin wrapper hosting the shared GameViewModel and delegating UI to GameScreen.
struct ContentView: View {
  @StateObject private var vm = GameViewModel()
  var body: some View { GameScreen(vm: vm) }
}

