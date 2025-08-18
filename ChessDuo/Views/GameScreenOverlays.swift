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

  // Actions
  let onCancelPromotion: () -> Void
  let onSelectPromotion: (PieceType) -> Void
  let onSelectPeer: (String) -> Void
  let onDismissPeerChooser: () -> Void

  var body: some View {
    ZStack {
      promotionLayer
      connectedResetLayers
  connectedHistoryRevertLayers
      peerChooserLayer
      newGameConfirmLayer
      loadGameLayer
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
            message: String.loc("opponent_requests_reset"),
            acceptTitle: String.loc("reset_accept_yes"),
            declineTitle: String.loc("reset_accept_no"),
            onAccept: { vm.respondToResetRequest(accept: true) },
            onDecline: { vm.respondToResetRequest(accept: false) }
          )
        }
        if vm.awaitingResetConfirmation {
          AwaitingResetOverlay(
            cancelTitle: String.loc("reset_cancel_request"),
            message: String.loc("reset_request_sent"),
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
          IncomingResetRequestOverlay( // reuse styling
            message: String.loc("opponent_requests_history_revert", String(target)),
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
          let localizedTitle = FamousGamesLoader.shared.getLocalizedTitle(for: incomingTitle)
          IncomingResetRequestOverlay(
            message: String.loc("opponent_requests_load_game", localizedTitle),
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
}
