import SwiftUI
import AVKit

struct NativePlayer: UIViewControllerRepresentable {
    @ObservedObject var model: PlayerModel
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = model.player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
    @MainActor final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        let model: PlayerModel
        private var pip = false
        private var fullScreen = false
        init(_ model: PlayerModel) { self.model = model }
        private func update() {
            model.externalPresentation = pip || fullScreen
            model.subtitles.useNativeRendering(pip || fullScreen)
        }
        func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
            pip = true; update()
        }
        func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            pip = false; update()
        }
        func playerViewController(_ playerViewController: AVPlayerViewController, failedToStartPictureInPictureWithError error: Error) {
            pip = false; update(); model.error = "Picture in Picture could not start. " + error.localizedDescription
        }
        func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(_ playerViewController: AVPlayerViewController) -> Bool { false }
        func playerViewController(_ playerViewController: AVPlayerViewController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
            completionHandler(playerViewController.viewIfLoaded?.window != nil)
        }
        func playerViewController(_ playerViewController: AVPlayerViewController, willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            fullScreen = true; update()
        }
        func playerViewController(_ playerViewController: AVPlayerViewController, willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                guard !context.isCancelled else { return }
                self?.fullScreen = false; self?.update()
            }
        }
    }
}
