//
//  OrchestratorApp.swift
//  Orchestrator
//
//  Created by Balogh Barnabás on 2026. 03. 21..
//

import SwiftUI

@main
struct OrchestratorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
