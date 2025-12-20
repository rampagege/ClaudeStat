import Foundation
import Mockable

@Mockable
public protocol NetworkClient: Sendable {
    func request(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: NetworkClient {
    public func request(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}
