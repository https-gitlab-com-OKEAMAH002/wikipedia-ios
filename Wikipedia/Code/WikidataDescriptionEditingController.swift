public struct WikidataAPI {
    public static let host = "www.wikidata.org"
    public static let path = "/w/api.php"
    public static let scheme = "https"

    public static var urlWithoutAPIPath: URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        return components.url
    }
}

struct WikidataAPIResult: Decodable {
    struct Error: Decodable {
        let code, info: String?
    }
    let error: Error?
    let success: Int?
}

extension WikidataAPIResult.Error: LocalizedError {
    var errorDescription: String? {
        return info
    }
}

extension WikidataAPIResult {
    var succeeded: Bool {
        return success == 1
    }
}

enum WikidataPublishingError: LocalizedError {
    case invalidArticleURL
    case apiResultNotParsedCorrectly
    case blacklistedLanguage
    case unknown
}

@objc public final class WikidataDescriptionEditingController: NSObject {
    weak var dataStore: MWKDataStore?

    @objc public init(with dataStore: MWKDataStore) {
        self.dataStore = dataStore
    }

    private let BlacklistedLanguagesKey = "WMFWikidataDescriptionEditingBlacklistedLanguagesKey"
    private var blacklistedLanguages: NSSet {
        assertMainThreadAndDataStore()
        let fallback = NSSet(set: ["en"])
        guard
            let dataStore = dataStore,
            let keyValue = dataStore.viewContext.wmf_keyValue(forKey: BlacklistedLanguagesKey),
            let value = keyValue.value as? NSSet else {
                return fallback
        }
        return value
    }

    @objc public func setBlacklistedLanguages(_ blacklistedLanguagesFromRemoteConfig: Array<String>) {
        assertMainThreadAndDataStore()
        let blacklistedLanguages = NSSet(array: blacklistedLanguagesFromRemoteConfig)
        dataStore?.viewContext.wmf_setValue(blacklistedLanguages, forKey: BlacklistedLanguagesKey)
    }

    public func isBlacklisted(_ languageCode: String) -> Bool {
        guard blacklistedLanguages.count > 0 else {
            return false
        }
        return blacklistedLanguages.contains(languageCode)
    }

    @objc(publishNewWikidataDescription:forArticleURL:completion:)
    public func publish(newWikidataDescription: String, for articleURL: URL, completion: @escaping (Error?) -> Void) {
        guard let title = articleURL.wmf_title,
        let language = articleURL.wmf_language,
        let wiki = articleURL.wmf_wiki else {
            completion(WikidataPublishingError.invalidArticleURL)
            return
        }
        publish(newWikidataDescription: newWikidataDescription, forPageWithTitle: title, language: language, wiki: wiki, completion: completion)
    }

    /// Publish new wikidata description.
    ///
    /// - Parameters:
    ///   - newWikidataDescription: new wikidata description to be published, e.g., "Capital of England and the United Kingdom".
    ///   - title: title of the page to be updated with new wikidata description, e.g., "London".
    ///   - language: language code of the page's wiki, e.g., "en".
    ///   - wiki: wiki of the page to be updated, e.g., "enwiki"
    ///   - completion: completion block called when operation is completed.
    private func publish(newWikidataDescription: String, forPageWithTitle title: String, language: String, wiki: String, completion: @escaping (Error?) -> Void) {
        guard !isBlacklisted(language) else {
            //DDLog("Attempting to publish a wikidata description in a blacklisted language; aborting")
            completion(WikidataPublishingError.blacklistedLanguage)
            return
        }
        let requestWithCSRFCompletion: (WikidataAPIResult?, URLResponse?, Bool?, Error?) -> Void = { result, response, authorized, error in
            if let error = error {
                completion(error)
            }
            guard let result = result else {
                completion(WikidataPublishingError.apiResultNotParsedCorrectly)
                return
            }

            completion(result.error)

            if let authorized = authorized, authorized, result.error == nil {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: WikidataDescriptionEditingController.DidMakeAuthorizedWikidataDescriptionEditNotification, object: nil)
                    self.madeAuthorizedWikidataDescriptionEdit = true
                }
            }
        }
        let queryParameters = ["action": "wbsetdescription",
                               "format": "json",
                               "formatversion": "2"]
        let bodyParameters = ["language": language,
                              "uselang": language,
                              "site": wiki,
                              "title": title,
                              "value": newWikidataDescription]
        let _ = Session.shared.requestWithCSRF(type: CSRFTokenJSONDecodableOperation.self, scheme: WikidataAPI.scheme, host: WikidataAPI.host, path: WikidataAPI.path, method: .post, queryParameters: queryParameters, bodyParameters: bodyParameters, bodyEncoding: .form, tokenContext: CSRFTokenOperation.TokenContext(tokenName: "token", tokenPlacement: .body, shouldPercentEncodeToken: true), completion: requestWithCSRFCompletion)
    }

    // MARK: - WMFKeyValue

    static let DidMakeAuthorizedWikidataDescriptionEditNotification = NSNotification.Name(rawValue: "WMFDidMakeAuthorizedWikidataDescriptionEdit")
    private let madeAuthorizedWikidataDescriptionEditKey = "WMFMadeAuthorizedWikidataDescriptionEditKey"
    @objc public private(set) var madeAuthorizedWikidataDescriptionEdit: Bool {
        set {
            assertMainThreadAndDataStore()
            guard madeAuthorizedWikidataDescriptionEdit != newValue else {
                return
            }
            dataStore?.viewContext.wmf_setValue(NSNumber(value: newValue), forKey: madeAuthorizedWikidataDescriptionEditKey)
            dataStore?.remoteNotificationsController.start()
        }
        get {
            assertMainThreadAndDataStore()
            guard let keyValue = dataStore?.viewContext.wmf_keyValue(forKey: madeAuthorizedWikidataDescriptionEditKey) else {
                return false
            }
            guard let value = keyValue.value as? NSNumber else {
                assertionFailure("Expected value of keyValue \(madeAuthorizedWikidataDescriptionEditKey) to be of type NSNumber")
                return false
            }
            return value.boolValue
        }
    }

    private func assertMainThreadAndDataStore() {
        assert(Thread.isMainThread)
        assert(dataStore != nil)
    }
}

public extension MWKArticle {
    @objc var isWikidataDescriptionEditable: Bool {
        guard let dataStore = dataStore, let language = self.url.wmf_language else {
            return false
        }
        return !dataStore.wikidataDescriptionEditingController.isBlacklisted(language)
    }
}
