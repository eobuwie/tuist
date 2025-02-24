import Combine
import CombineExt
import Foundation
import RxSwift

public enum HTTPRequestDispatcherError: LocalizedError, FatalError {
    case urlSessionError(Error)
    case parseError(Error)
    case invalidResponse
    case serverSideError(Error, HTTPURLResponse)

    // MARK: - LocalizedError

    public var errorDescription: String? { description }

    // MARK: - FatalError

    public var description: String {
        switch self {
        case let .urlSessionError(error):
            if let error = error as? LocalizedError {
                return error.localizedDescription
            } else {
                return "Received a session error."
            }
        case let .parseError(error):
            if let error = error as? LocalizedError {
                return error.localizedDescription
            } else {
                return "Error parsing the network response."
            }
        case .invalidResponse: return "Received unexpected response from the network."
        case let .serverSideError(error, response):
            let url: URL = response.url!
            if let error = error as? LocalizedError {
                return """
                Error returned by the server:
                  - URL: \(url.absoluteString)
                  - Code: \(response.statusCode)
                  - Description: \(error.localizedDescription)
                """
            } else {
                return """
                Error returned by the server:
                  - URL: \(url.absoluteString)
                  - Code: \(response.statusCode)
                """
            }
        }
    }

    public var type: ErrorType {
        switch self {
        case .urlSessionError: return .bug
        case .parseError: return .abort
        case .invalidResponse: return .bug
        case .serverSideError: return .bug
        }
    }
}

public protocol HTTPRequestDispatching {
    func dispatch<T, E: Error>(resource: HTTPResource<T, E>) -> Single<(object: T, response: HTTPURLResponse)>
    func dispatch<T, E: Error>(resource: HTTPResource<T, E>) -> AnyPublisher<(object: T, response: HTTPURLResponse), Error>
}

public final class HTTPRequestDispatcher: HTTPRequestDispatching {
    let session: URLSession

    public init(session: URLSession = URLSession.shared) {
        self.session = session
    }

    public func dispatch<T, E: Error>(resource: HTTPResource<T, E>) -> Single<(object: T, response: HTTPURLResponse)> {
        Single.create { observer in
            let task = self.session.dataTask(with: resource.request(), completionHandler: { data, response, error in
                if let error = error {
                    observer(.error(HTTPRequestDispatcherError.urlSessionError(error)))
                } else if let data = data, let response = response as? HTTPURLResponse {
                    switch response.statusCode {
                    case 200 ..< 300:
                        do {
                            let object = try resource.parse(data, response)
                            observer(.success((object: object, response: response)))
                        } catch {
                            observer(.error(HTTPRequestDispatcherError.parseError(error)))
                        }
                    default: // Error
                        do {
                            let error = try resource.parseError(data, response)
                            observer(.error(HTTPRequestDispatcherError.serverSideError(error, response)))
                        } catch {
                            observer(.error(HTTPRequestDispatcherError.parseError(error)))
                        }
                    }
                } else {
                    observer(.error(HTTPRequestDispatcherError.invalidResponse))
                }
            })
            task.resume()

            return Disposables.create {
                task.cancel()
            }
        }
    }

    public func dispatch<T, E>(resource: HTTPResource<T, E>) -> AnyPublisher<(object: T, response: HTTPURLResponse), Error>
        where E: Error
    {
        AnyPublisher.create { subscriber in
            let disposable = self.dispatch(resource: resource)
                .subscribe(onSuccess: { value in
                    subscriber.send(value)
                    subscriber.send(completion: .finished)
                }, onError: { error in
                    subscriber.send(completion: .failure(error))
                })
            return AnyCancellable {
                disposable.dispose()
            }
        }
    }
}
