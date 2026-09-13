/// The durable ordering preference for the contents of one portal.
public enum PortalSortOrder: String, CaseIterable, Sendable {
    case name
    case modificationDate = "modification_date"
    case creationDate = "creation_date"
}
