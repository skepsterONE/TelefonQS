//
//  CallHistorySidebarContainerController.swift
//  Telephone
//

import AppKit
import SwiftUI

@objcMembers
final class CallHistorySidebarContainerController: NSViewController {
    private let hostingController: NSHostingController<CallHistorySidebarRootView>

    init(callHistoryViewController: CallHistoryViewController, target: AnyObject, action: Selector) {
        let actionHandler = CallHistorySidebarActionHandler(target: target, action: action)
        hostingController = NSHostingController(
            rootView: CallHistorySidebarRootView(
                callHistoryViewController: callHistoryViewController,
                actionHandler: actionHandler
            )
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: .zero)
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

private final class CallHistorySidebarActionHandler: NSObject, ObservableObject {
    weak var target: AnyObject?
    let action: Selector

    init(target: AnyObject, action: Selector) {
        self.target = target
        self.action = action
    }

    func performAction() {
        _ = target?.perform(action, with: nil)
    }
}

private struct CallHistorySidebarRootView: View {
    let callHistoryViewController: CallHistoryViewController
    @ObservedObject var actionHandler: CallHistorySidebarActionHandler

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(NSLocalizedString("Call History", comment: "Call history drawer title and toggle."))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Button(action: actionHandler.performAction) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            CallHistoryControllerRepresentable(controller: callHistoryViewController)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
        }
    }
}

private struct CallHistoryControllerRepresentable: NSViewControllerRepresentable {
    let controller: CallHistoryViewController

    func makeNSViewController(context: Context) -> CallHistoryViewController {
        controller
    }

    func updateNSViewController(_ nsViewController: CallHistoryViewController, context: Context) {
    }
}
