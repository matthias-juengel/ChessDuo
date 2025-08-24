//
//  GameScreenOverlays.swift
//  ChessDuo
//
//  Extracted overlay layers from GameScreen for readability & separation.
//

import SwiftUI

struct GameScreenOverlays: View {
  @ObservedObject var vm: GameViewModel
  @Binding var showPeerChooser: Bool
  @Binding var selectedPeerToJoin: String?
  @Binding var showLoadGame: Bool
  @Binding var showNameEditor: Bool // new

  // Actions
  let onCancelPromotion: () -> Void
  let onSelectPromotion: (PieceType) -> Void
  let onSelectPeer: (String) -> Void
  let onDismissPeerChooser: () -> Void

  var body: some View {
    ZStack {
  networkPermissionIntroLayer
      promotionLayer
      connectedResetLayers
  connectedHistoryRevertLayers
      peerChooserLayer
      newGameConfirmLayer
      loadGameLayer
      nameChangeLayer // new
  localNetworkPermissionHelpLayer
    }
  }
}

// MARK: - Individual Layers
private extension GameScreenOverlays {
  var promotionLayer: some View {
    ZStack {
      if vm.showingPromotionPicker, let pending = vm.pendingPromotionMove {
        let promoColor = vm.engine.board.piece(at: pending.from)?.color ?? vm.engine.sideToMove.opposite
        let rotateBoard180 = !vm.peers.isConnected && promoColor == .black
        ZStack {
          OverlayBackdrop(onTap: { onCancelPromotion() })
          ModalCard() {
            PromotionPickerView(
              color: promoColor,
              rotate180: rotateBoard180,
              onSelect: { onSelectPromotion($0) },
              onCancel: { onCancelPromotion() }
            )
          }
        }
        .modalTransition(animatedWith: vm.showingPromotionPicker)
        .zIndex(OverlayZIndex.promotion)
      }
    }
  }

  var connectedResetLayers: some View {
    ZStack {
      if vm.peers.isConnected {
        if vm.incomingResetRequest {
          IncomingResetRequestOverlay(
            message: vm.localizedIncomingResetRequestMessage,
            acceptTitle: String.loc("reset_accept_yes"),
            declineTitle: String.loc("reset_accept_no"),
            onAccept: { vm.respondToResetRequest(accept: true) },
            onDecline: { vm.respondToResetRequest(accept: false) }
          )
        }
        if vm.awaitingResetConfirmation {
          AwaitingResetOverlay(
            cancelTitle: String.loc("reset_cancel_request"),
            message: vm.localizedAwaitingResetConfirmationMessage,
            onCancel: { vm.respondToResetRequest(accept: false) }
          )
        }
      }
    }
  }

  var connectedHistoryRevertLayers: some View {
    ZStack {
      if vm.peers.isConnected {
        if let target = vm.incomingHistoryRevertRequest {
          let delta = max(0, vm.movesMade - target)
          let name = vm.opponentName ?? String.loc("turn_black")
          IncomingResetRequestOverlay( // reuse styling
            message: String.loc("opponent_requests_history_revert", name, String(delta)),
            acceptTitle: String.loc("history_revert_accept_yes"),
            declineTitle: String.loc("history_revert_accept_no"),
            onAccept: { vm.respondToHistoryRevertRequest(accept: true) },
            onDecline: { vm.respondToHistoryRevertRequest(accept: false) }
          )
        }
        if vm.awaitingHistoryRevertConfirmation {
          AwaitingResetOverlay(
            cancelTitle: String.loc("history_revert_cancel_request"),
            message: String.loc("history_revert_request_sent"),
            onCancel: { vm.cancelPendingHistoryRevertRequest() }
          )
        }
        // Famous game load negotiation overlays
        if let incomingTitle = vm.incomingLoadGameRequestTitle {
          IncomingResetRequestOverlay(
            message: String.loc("opponent_requests_load_game", incomingTitle),
            acceptTitle: String.loc("load_game_accept_yes"),
            declineTitle: String.loc("load_game_accept_no"),
            onAccept: { vm.respondToLoadGameRequest(accept: true) },
            onDecline: { vm.respondToLoadGameRequest(accept: false) }
          )
        }
        if vm.awaitingLoadGameConfirmation {
          AwaitingResetOverlay(
            cancelTitle: String.loc("load_game_cancel_request"),
            message: String.loc("load_game_request_sent"),
            onCancel: {
              // Cancel outgoing load request: send decline and clear state
              vm.respondToLoadGameRequest(accept: false)
              vm.awaitingLoadGameConfirmation = false
            }
          )
        }
      }
    }
  }

  var peerChooserLayer: some View {
    ZStack {
      if showPeerChooser {
        PeerJoinOverlayView(
            peers: vm.discoveredPeerNames,
          selected: selectedPeerToJoin,
          onSelect: { name in
            onSelectPeer(name)
          },
          onCancel: {
            onDismissPeerChooser()
          },
          animated: true
        )
        .zIndex(OverlayZIndex.peerChooser)
        .transition(.opacity)
  .onAppear { print("[UI] Showing PeerJoinOverlayView with names=\(vm.discoveredPeerNames)") }
      }
    }
  }

  var newGameConfirmLayer: some View {
    ZStack {
      if vm.offlineResetPrompt {
        NewGameConfirmOverlay(
          message: String.loc("offline_new_game_message"),
          destructiveTitle: String.loc("offline_new_game_confirm"),
          keepTitle: String.loc("offline_new_game_keep"),
          onConfirm: { vm.performLocalReset(send: false) },
          onCancel: { vm.offlineResetPrompt = false }
        )
        .zIndex(OverlayZIndex.newGameConfirm)
        .modalTransition(animatedWith: vm.offlineResetPrompt)
      }
    }
  }

  var loadGameLayer: some View {
    ZStack {
      if showLoadGame {
        LoadGameOverlay(
          vm: vm,
          showLoadGame: $showLoadGame
        )
        .zIndex(OverlayZIndex.menu + 2)
      }
    }
  }

  var nameChangeLayer: some View {
    ZStack {
      if (showNameEditor || vm.showInitialNamePrompt) && !vm.showNetworkPermissionIntro {
        NameChangeOverlay(
          initialName: vm.playerName,
          isFirstLaunch: vm.showInitialNamePrompt,
          onSave: { newName in
            vm.updatePlayerName(newName)
            vm.showInitialNamePrompt = false
            showNameEditor = false
            // After name is set, either show network intro (if not seen) or start networking now.
            if !vm.hasSeenNetworkPermissionIntro {
              vm.showNetworkPermissionIntro = true // will later trigger approveNetworkingAndStartIfNeeded on Continue
            } else {
              vm.approveNetworkingAndStartIfNeeded()
            }
          },
          onLater: {
            vm.showInitialNamePrompt = false
            showNameEditor = false
            if !vm.hasSeenNetworkPermissionIntro {
              vm.showNetworkPermissionIntro = true
            } // else: user already saw intro earlier in a prior session; networking will auto-start via VM init if approved.
          }
        )
        .zIndex(OverlayZIndex.menu + 3)
      }
    }
  }

  var networkPermissionIntroLayer: some View {
    ZStack {
      if vm.showNetworkPermissionIntro {
        NetworkPermissionIntroOverlay(
          onContinue: {
            vm.approveNetworkingAndStartIfNeeded()
          },
          onLater: {
            // User postponed enabling networking: dismiss intro TEMPORARILY but do NOT mark as seen.
            // This allows us to ask again later (e.g. via a settings/menu action) or auto-present once they perform a network action.
            vm.showNetworkPermissionIntro = false
          }
        )
        .zIndex(OverlayZIndex.menu + 10)
      }
    }
  }

  var localNetworkPermissionHelpLayer: some View {
    ZStack {
      if vm.showLocalNetworkPermissionHelp {
        LocalNetworkPermissionHelpOverlay(
          onOpenSettings: {
            // Direct call; function is @MainActor sync so no need for Task/await.
            vm.openAppSettings()
          },
          onDismiss: { vm.showLocalNetworkPermissionHelp = false }
        )
        .zIndex(OverlayZIndex.menu + 11)
      }
    }
  }
}
