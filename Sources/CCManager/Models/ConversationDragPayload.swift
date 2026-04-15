import Foundation
import CoreTransferable
import UniformTypeIdentifiers

struct ConversationDragPayload: Codable, Transferable {
    let sessionIds: [String]

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { (payload: ConversationDragPayload) -> String in
            payload.sessionIds.joined(separator: "\n")
        } importing: { (text: String) -> ConversationDragPayload in
            ConversationDragPayload(
                sessionIds: text.split(separator: "\n").map(String.init)
            )
        }
    }
}
