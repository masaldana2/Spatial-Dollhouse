import SwiftUI
import UIKit

struct ImageCardView: View {
    let title: String
    let image: UIImage?
    @State private var isPresentingFullscreen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            Group {
                if let image {
                    Button {
                        isPresentingFullscreen = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .frame(maxWidth: .infinity)

                            Label("Open fullscreen", systemImage: "arrow.up.left.and.arrow.down.right")
                                .labelStyle(.iconOnly)
                                .padding(8)
                                .foregroundStyle(.white)
                                .background(.black.opacity(0.55), in: Circle())
                                .padding(12)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(title) fullscreen")
                } else {
                    ContentUnavailableView(
                        "No preview yet",
                        systemImage: "square.slash",
                        description: Text("Run analysis to generate a segmentation preview.")
                    )
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 240)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .fullScreenCover(isPresented: $isPresentingFullscreen) {
            if let image {
                FullscreenImageViewer(title: title, image: image, isPresented: $isPresentingFullscreen)
            }
        }
    }
}

private struct FullscreenImageViewer: View {
    let title: String
    let image: UIImage
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ZoomableImageScrollView(image: image)
                .ignoresSafeArea()
                .background(Color.black)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") {
                            isPresented = false
                        }
                        .foregroundStyle(.white)
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

private struct ZoomableImageScrollView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 6
        scrollView.minimumZoomScale = 1
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .black

        let imageView = context.coordinator.imageView
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        scrollView.addSubview(imageView)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let imageChanged = context.coordinator.image !== image
        context.coordinator.image = image

        if imageChanged {
            context.coordinator.imageView.image = image
            scrollView.zoomScale = 1
        }

        if context.coordinator.imageView.frame.size != scrollView.bounds.size {
            context.coordinator.imageView.frame = scrollView.bounds
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var image: UIImage?
        let imageView = UIImageView()

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let boundsSize = scrollView.bounds.size
            var frameToCenter = imageView.frame

            frameToCenter.origin.x = frameToCenter.size.width < boundsSize.width
                ? (boundsSize.width - frameToCenter.size.width) / 2
                : 0
            frameToCenter.origin.y = frameToCenter.size.height < boundsSize.height
                ? (boundsSize.height - frameToCenter.size.height) / 2
                : 0

            imageView.frame = frameToCenter
        }
    }
}
