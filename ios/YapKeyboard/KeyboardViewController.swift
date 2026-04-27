import UIKit
import SwiftUI

@objc(KeyboardViewController)
final class KeyboardViewController: UIInputViewController {

    private var hostingController: UIHostingController<KeyboardView>?
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()

        let keyboardView = KeyboardView(
            advanceToNextKeyboard: { [weak self] in
                self?.advanceToNextInputMode()
            },
            insertText: { [weak self] text in
                self?.textDocumentProxy.insertText(text)
            },
            hasFullAccess: hasFullAccess
        )

        let hosting = UIHostingController(rootView: keyboardView)
        hosting.view.backgroundColor = .systemBackground
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)

        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        self.hostingController = hosting
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setHeight()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.setHeight()
        })
    }

    private func setHeight() {
        let isLandscape = view.bounds.width > view.bounds.height
        let targetHeight: CGFloat = isLandscape ? 180 : 260

        if let existing = heightConstraint {
            existing.constant = targetHeight
        } else {
            let c = view.heightAnchor.constraint(equalToConstant: targetHeight)
            c.priority = UILayoutPriority(rawValue: 999)
            c.isActive = true
            heightConstraint = c
        }
    }

    // Re-check full-access when the extension becomes active (user may have
    // just enabled it in Settings while the keyboard was already loaded).
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if hasFullAccess != hostingController?.rootView.hasFullAccess {
            hostingController?.rootView = KeyboardView(
                advanceToNextKeyboard: { [weak self] in self?.advanceToNextInputMode() },
                insertText: { [weak self] text in self?.textDocumentProxy.insertText(text) },
                hasFullAccess: hasFullAccess
            )
        }
    }
}
