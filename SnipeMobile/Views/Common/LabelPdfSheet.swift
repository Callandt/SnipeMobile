//
//  LabelPdfSheet.swift
//  SnipeMobile
//

import SwiftUI
import QuickLook
import UIKit

enum LabelPdfSupport {
    static func writeTemporaryPdf(_ data: Data, preferredName: String = "labels") -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(preferredName)-\(UUID().uuidString).pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func print(pdfURL: URL) {
        guard UIPrintInteractionController.canPrint(pdfURL) else { return }
        let printInfo = UIPrintInfo.printInfo()
        printInfo.outputType = .general
        printInfo.jobName = L10n.string("asset_labels")
        let controller = UIPrintInteractionController.shared
        controller.printInfo = printInfo
        controller.printingItem = pdfURL
        controller.present(animated: true, completionHandler: nil)
    }
}

struct LabelPdfSheet: View {
    let pdfURL: URL
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            LabelPdfPreview(url: pdfURL)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(L10n.string("asset_labels"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.string("done")) { dismiss() }
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            LabelPdfSupport.print(pdfURL: pdfURL)
                        } label: {
                            Image(systemName: "printer")
                        }
                        .accessibilityLabel(L10n.string("print"))

                        Button {
                            showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(L10n.string("share"))
                    }
                }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [pdfURL])
        }
    }
}

private struct LabelPdfPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
