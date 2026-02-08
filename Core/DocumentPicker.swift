// Core/DocumentPicker.swift

import SwiftUI
import UniformTypeIdentifiers

// Core/DocumentPicker.swift

struct DocumentPicker: UIViewControllerRepresentable {
    var allowedTypes: [UTType] // Ensure this property exists
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Pass the allowedTypes array here
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedTypes, asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }


    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            // Security scoping ensures the app can read the file immediately
            if url.startAccessingSecurityScopedResource() {
                parent.onPick(url)
            }
        }
    }
}
