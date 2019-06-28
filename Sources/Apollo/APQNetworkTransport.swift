import Foundation
import CryptoSwift

/// Wraps a NetworkTransport to perform automated persisted queries.
public final class APQNetworkTransport: NetworkTransport {
  fileprivate let version = 1
  var isEnabled: Bool = true
  let networkTransport: NetworkTransport
  
  public init(networkTransport: NetworkTransport) {
    self.networkTransport = networkTransport
  }
  
  public func send<Operation>(
    operation: Operation,
    fetchHTTPMethod: FetchHTTPMethod,
    includeQuery: Bool,
    extensions: GraphQLMap?, completionHandler: @escaping (GraphQLResponse<Operation>?, Error?) -> Void
  ) -> Cancellable where Operation : GraphQLOperation {
    var newExtensions = extensions
    if isEnabled {
      newExtensions = (newExtensions ?? [:]).merging(
        [
          "persistedQuery": [
            "version": version,
            "sha256Hash": operation.queryDocument.sha256()
          ]
        ],
        uniquingKeysWith: { $1 }
      )
    }
    
    return networkTransport.send(
      operation: operation,
      fetchHTTPMethod: fetchHTTPMethod,
      includeQuery: !isEnabled,
      extensions: newExtensions
    ) { result, error in
      guard let response = result, let errorsEntry = response.body["errors"] as? [JSONObject] else {
        completionHandler(result, error)
        return
      }
      
      let errors = errorsEntry.map(GraphQLError.init)
      self.isEnabled = !self.hasErrorCode(errors: errors, needleErrorCode: "PERSISTED_QUERY_NOT_SUPPORTED")
      
      if self.hasErrorCode(errors: errors, needleErrorCode: "PERSISTED_QUERY_NOT_FOUND") || !self.isEnabled {
        _ = self.networkTransport.send(
          operation: operation,
          fetchHTTPMethod: fetchHTTPMethod,
          includeQuery: true,
          extensions: newExtensions,
          completionHandler: completionHandler
        )
      }
    }
    
  }
  
  fileprivate func hasErrorCode(errors: [GraphQLError], needleErrorCode: String) -> Bool {
    let foundError = errors.first { error in
      guard let extensions = error.extensions,
        let errorCode = extensions["code"] as? String else {
          return false
      }
      
      return errorCode == needleErrorCode
    }
    
    return foundError != nil
  }
}


