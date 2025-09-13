//
//  YouTube.swift
//  Subler
//
//  Created by Are Digranes on 13/09/2025.
//

import MP42Foundation

extension String {
    func similarityScore(to comparison: String) -> Int {
        let normalize: (String) -> Set<String> = { str in
            Set(str
                .replacingOccurrences(of: "[\\p{P}\\p{S}]+", with: " ", options: .regularExpression)
                .split(separator: " ")
                .map(String.init))
        }
        
        let words1 = normalize(self)
        let words2 = normalize(comparison)
        
        guard !words2.isEmpty else { return 0 }
        
        return (words1.intersection(words2).count * 100) / max(words1.count, words2.count)
    }
}

public struct YouTube: MetadataService {
    public var languageType: LanguageType {
        return .ISO
    }
    
    public var languages: [String] {
        get {
            return MP42Languages.defaultManager.iso_639_1Languages
        }
    }
    
    public var defaultLanguage: String {
        return "en"
    }
    
    public var name: String {
        return "YouTube"
    }
    
    public func search(tvShow: String, language: String) -> [String] {
        print("TODO: search tvShow: \(tvShow) language:  \(language)")
        return []
    }
    
    public func search(tvShow: String, language: String, season: Int?, episode: Int?) -> [MetadataResult] {
        let result = listChannel(term: tvShow, language: language)
        if result.count > 0 {
            return result.map { MetadataResult(item: $0)}
        }
        return []
    }
    
    public func loadTVMetadata(_ metadata: MetadataResult, language: String) -> MetadataResult {
        print("TODO: loadTVMetadata metadata: (struct) language:  \(language)")
        return metadata
    }
    
    public func search(movie: String, language: String) -> [MetadataResult] {
        let result = getVideo(term: movie, language: language)
        if result.count > 0 {
            return result.map { MetadataResult(item: $0)}
        }
        let results = searchVideo(term: movie, language: language)
        if results.count > 0 {
            return results.map { MetadataResult(item: $0)}
        }
        return []
    }
    
    public func loadMovieMetadata(_ metadata: MetadataResult, language: String) -> MetadataResult {
        return getMissing(metadata: metadata, language: language)
    }
    
    private static let urlComponents    = URLComponents(staticString: "https://youtube.googleapis.com/")
    private static let videoPath        = "/youtube/v3/videos"
    private static let channelPath      = "/youtube/v3/channels"
    private static let searchPath       = "/youtube/v3/search"
    private static let playlistPath     = "/youtube/v3/playlistItems"
    private var apiKey: String
    
    private static var lastSearchTerm: String = ""

    init() {
        apiKey = MetadataPrefs.youTubeAPIKey
    }
    
    private func JSONRequest<T>(components: URLComponents, type: T.Type) -> T? where T : Decodable {
        guard let url = components.url else { return nil }
        do {
            guard let data = URLSession.data(from: url) else { return nil }
            return try JSONDecoder().decode(type, from: data)
        } catch {
            print(error)
            return nil
        }
    }

    private func listChannel(term: String, language: String) -> [Item] {
        var token: String? = nil
        var completeResults: [Item] = []
        var count = 8
        
        // Search on playlist id
        if term.hasPrefix("UC") || term.hasPrefix("UU") {
            let uploadId = "UU" + term.dropFirst(2)
            var components = YouTube.urlComponents
            components.path = YouTube.playlistPath
            var matchCount = 0, topMatch = 2
            while count > 0 {
                components.queryItems = [
                    URLQueryItem(name: "part", value: "snippet"),
                    URLQueryItem(name: "playlistId", value: uploadId),
                    URLQueryItem(name: "maxResults", value: "50"),
                    URLQueryItem(name: "key", value: apiKey)
                ]
                if token != nil {
                    components.queryItems?.append(URLQueryItem(name: "pageToken", value: token))
                }
                if let results = JSONRequest(components: components, type: VideoResult.self) {
                    for result in results.items ?? [] {
                        if let title = result.snippet?.title {
                            let match = title.similarityScore(to: YouTube.lastSearchTerm)
                            print("Match: \(match), matchCount: \(matchCount), topMatch: \(topMatch), count: \(completeResults.count)")
                            if completeResults.count > 0 {
                                if match >= topMatch {
                                    completeResults.insert(result, at: completeResults.startIndex)
                                    matchCount += 1
                                } else if match > 1 {
                                    completeResults.insert(result, at: completeResults.startIndex + matchCount)
                                } else {
                                    completeResults.append(result)
                                }
                            } else {
                                if match == 100 { matchCount += 1 }
                                completeResults.append(result)
                            }
                            if match > topMatch { topMatch = match }
                        } else {
                            print("Missing title...")
                        }
                    }
                    if results.nextPageToken == nil {
                        return completeResults
                    } else {
                        token = results.nextPageToken
                    }
                }
                count -= 1
            }
            if completeResults.count > 0 {
                return completeResults
            }
        }
        
        // Search for channel
        var components = YouTube.urlComponents
        components.path = YouTube.channelPath
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails"),
            // URLQueryItem(name: "forUsername", value: term), //  Search on username
            URLQueryItem(name: "forHandle", value: term),
            URLQueryItem(name: "hl", value: language),
            URLQueryItem(name: "key", value: apiKey)
        ]
        if let results = JSONRequest(components: components, type: VideoResult.self) {
            if results.items?.count ?? 0 > 0 {
                if let uploadId = results.items?.first?.contentDetails?.relatedPlaylists?.uploads {
                    return listChannel(term: uploadId, language: language)
                }
            }
        }
        
        let result = getVideo(term: term, language: language)
        if result.count > 0 {
            if let channelId = result.first?.snippet?.channelId {
                return listChannel(term: channelId, language: language)
            }
        }

        // Perform full search if all else fails
        
        // Search is expensive so we don't request it before called a second time
        if term != YouTube.lastSearchTerm {
            YouTube.lastSearchTerm = term
            return []
        }

        components = YouTube.urlComponents
        components.path = YouTube.searchPath
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "q", value: term),
            URLQueryItem(name: "maxResults", value: "50"),
            URLQueryItem(name: "safeSearch", value: "none"),
            URLQueryItem(name: "relevanceLanguage", value: language),
            URLQueryItem(name: "type", value: "channel"),
            URLQueryItem(name: "key", value: apiKey)
        ]

        guard let results = JSONRequest(components: components, type: SearchResult.self) else { return [] }

        if let channelId = results.items?.first?.id?.channelId {
            return listChannel(term: channelId, language: language)
        }

        // Hold the search term
        YouTube.lastSearchTerm = ""
        
        return []
    }
    
    private func getVideo(term: String, language: String) -> [Item] {
        if let id = getVideoId(from: term) {
            var components = YouTube.urlComponents
            components.path = YouTube.videoPath
            components.queryItems = [
                URLQueryItem(name: "part", value: "snippet,contentDetails"),
                URLQueryItem(name: "id", value: id),
                URLQueryItem(name: "hl", value: language),
                URLQueryItem(name: "key", value: apiKey)
            ]
            guard let results = JSONRequest(components: components, type: VideoResult.self) else { return [] }
            return results.items ?? []
        }
        return []
    }

    private func getVideoId(from url: String) -> String? {
        if (url.count > 10) && (url.count < 12) {
            return url
        }
        if #available(macOS 13.0, *) {
            let regex = /(\/|%3D|vi=|v=)(?P<ID>[0-9A-z-_]{11})([%#?&\/]|$)/
            if let match = url.firstMatch(of: regex) { return String(match.output.ID) }
        }
        return nil
    }
    
    private func searchVideo(term: String, language: String) -> [SearchItem] {
        // Because search is expensive only run it if repeated twice
        if term.count < 5 || term != YouTube.lastSearchTerm {
            YouTube.lastSearchTerm = term
            return []
        }
        
        var components = YouTube.urlComponents
        components.path = YouTube.searchPath
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "q", value: term),
            URLQueryItem(name: "maxResults", value: "50"),
            URLQueryItem(name: "safeSearch", value: "none"),
            URLQueryItem(name: "relevanceLanguage", value: language),
            URLQueryItem(name: "type", value: "video"),
            // URLQueryItem(name: "videoType", value: "movie"), # YouTube Movies
            URLQueryItem(name: "key", value: apiKey)
        ]
        guard let results = JSONRequest(components: components, type: SearchResult.self) else { return [] }
        return results.items ?? []
    }
    
    private func getMissing(metadata: MetadataResult, language: String) -> MetadataResult {
        if metadata[.genre] == nil {
            let results: [Item] = getVideo(term: metadata[.episodeID] as! String, language: language)
            if let item = results.first {
                metadata.updateVideo(with: item)
            }
        }
        return getChannel(metadata: metadata, language: language)
    }
    
    private func getChannel(metadata: MetadataResult, language: String) -> MetadataResult {
        guard let id = metadata[.serviceContentID] else { return metadata }
        var components = YouTube.urlComponents
        components.path = YouTube.channelPath
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails"),
            URLQueryItem(name: "id", value: (id as! String)),
            URLQueryItem(name: "hl", value: language),
            URLQueryItem(name: "key", value: apiKey)
        ]
        guard let results = JSONRequest(components: components, type: VideoResult.self) else { return metadata }
        if let item = results.items?.first {
            metadata.insertChannel(contentOf: item)
        }
        return metadata
    }

    fileprivate static let categories = [
        0: "Unknown",
        1: "Film & Animation",
        2: "Autos & Vehicles",
        10: "Music",
        15: "Pets & Animals",
        17: "Sports",
        18: "Short Movies",
        19: "Travel & Events",
        20: "Gaming",
        21: "Videoblogging",
        22: "People & Blogs",
        23: "Comedy",
        24: "Entertainment",
        25: "News & Politics",
        26: "Howto & Style",
        27: "Education",
        28: "Science & Technology",
        29: "Nonprofits & Activism",
        30: "Movies",
        31: "Anime/Animation",
        32: "Action/Adventure",
        33: "Classics",
        34: "Comedy",
        35: "Documentary",
        36: "Drama",
        37: "Family",
        38: "Foreign",
        39: "Horror",
        40: "Sci-Fi/Fantasy",
        41: "Thriller",
        42: "Shorts",
        43: "Shows",
        44: "Trailers"
    ]
    
    // MARK: JSON structs
    
    private struct DataWrapper<T>: Codable where T : Codable  {
        let data: T
    }
    
    private struct VideoResult: Codable {
        let kind: String
        let etag: String
        let nextPageToken: String?
        let pageInfo: PageInfo?
        let items: [Item]?
    }

    private struct SearchResult: Codable {
        let kind: String
        let etag: String
        let nextPageToken: String?
        let regionCode: String?
        let pageInfo: PageInfo?
        let items: [SearchItem]?
    }

    private struct PageInfo: Codable {
        let totalResults: Int
        let resultsPerPage: Int
    }
    
    fileprivate struct Item: Codable {
        let kind: String
        let etag: String
        let id: String?
        let snippet: Snippet?
        let contentDetails: ContentDetails?
        let status: Status_?
        let statistics: Statistics?
        let paidProductPlacementDetails: PaidProductPlacementDetails?
        let player: Player?
        let topicDetails: TopicDetails?
        let recordingDetails: RecordingDetails?
        let fileDetails: FileDetails?
        let processingDetails: ProcessingDetails?
        let suggestions: Suggestions?
        let liveStreamingDetails: LiveStreamingDetails?
        let localizations: Localizations?
    }

    fileprivate struct SearchItem: Codable {
        let kind: String
        let etag: String
        let id: SearchId?
        let snippet: Snippet?
    }

    fileprivate struct SearchId: Codable {
        let kind: String
        let videoId: String?
        let channelId: String?
    }
    
    fileprivate struct Snippet: Codable {
        let publishedAt: String?
        let channelId: String?
        let title: String?
        let description: String?
        let customUrl: String?
        let thumbnails: Thumbnails?
        let channelTitle: String?
        let playlistId: String?
        let position: Int?
        let tags: [String]?
        let categoryId: String?
        let liveBroadcastContent: String?
        let defaultLanguage: String?
        let localized: Localized?
        let defaultAudioLanguage: String?
        let country: String?
        let resourceId: ResourceId?
        let videoOwnerChannelTitle: String?
        let videoOwnerChannelId: String?
        let publishTime: String?
    }

    fileprivate struct ContentDetails: Codable {
        let duration: String?
        let dimension: String?
        let definition: String?
        let caption: String?
        let licensedContent: Bool?
        let contentRating: ContentRating?
        let regionRestriction: RegionRestriction?
        let projection: String?
        let relatedPlaylists: RelatedPlaylists?
        let hasCustomThumbnail: Bool?
    }
    
    fileprivate struct RegionRestriction: Codable {
        let allowed: [String]?
        let blocked: [String]?
    }

    fileprivate struct Thumbnails: Codable {
        let `default`: Thumbnail?
        let medium: Thumbnail?
        let high: Thumbnail?
        let standard: Thumbnail?
        let maxres: Thumbnail?
        var maxUrl: URL? {
            get {
                let urlString = maxres?.url ?? standard?.url ?? high?.url ?? medium?.url ?? `default`?.url ?? ""
                return URL(string: urlString)
            }
        }
        var maxSize: ArtworkSize {
            get {
                let w = maxres?.width ?? standard?.width ?? high?.width ?? medium?.width ?? `default`?.width ?? 0
                let h = maxres?.height ?? standard?.height ?? high?.height ?? medium?.height ?? `default`?.height ?? 0
                if w > h { return .rectangle }
                if w < h { return .vertical }
                return .square
            }
        }
        var maxWidth: Int {
            get {
                return maxres?.width ?? standard?.width ?? high?.width ?? medium?.width ?? `default`?.width ?? 0
            }
        }
        var maxHeight: Int {
            get {
                return maxres?.height ?? standard?.height ?? high?.height ?? medium?.height ?? `default`?.height ?? 0
            }
        }
        var maxYTSize: ArtworkSize {
            get {
                if maxres != nil { return .maxres }
                if standard != nil { return .standard }
                if high != nil { return .high }
                if medium != nil { return .medium }
                return .`default`
            }
        }

        func addArtwork(type: ArtworkType, title: String = "YouTube") -> Artwork? {
            return Artwork(url: maxUrl!, thumbURL: URL(string: (medium?.url ?? `default`?.url) ?? "")!, service: "\(title) [\(maxWidth)x\(maxHeight)]", type: type, size: maxSize)
        }
    }
    
    fileprivate struct Localized: Codable {
        let title: String?
        let description: String?
    }
    
    fileprivate struct ResourceId: Codable {
        let kind: String?
        let videoId: String?
    }
    
    fileprivate struct ContentRating: Codable {
        let ytRating: String?
        let acbRating: String?
        let agcomRating: String?
        let anatelRating: String?
        let bbfcRating: String?
        let bfvcRating: String?
        let bmukkRating: String?
        let catvRating: String?
        let catvfrRating: String?
        let cbfcRating: String?
        let cccRating: String?
        let cceRating: String?
        let chfilmRating: String?
        let chvrsRating: String?
        let cicfRating: String?
        let cnaRating: String?
        let cncRating: String?
        let csaRating: String?
        let cscfRating: String?
        let czfilmRating: String?
        let djctqRating: String?
        let djctqRatingReasons: [String?]?
        let ecbmctRating: String?
        let eefilmRating: String?
        let egfilmRating: String?
        let eirinRating: String?
        let fcbmRating: String?
        let fcoRating: String?
        let fmocRating: String?
        let fpbRating: String?
        let fpbRatingReasons: [String?]?
        let fskRating: String?
        let grfilmRating: String?
        let icaaRating: String?
        let ifcoRating: String?
        let ilfilmRating: String?
        let incaaRating: String?
        let kfcbRating: String?
        let kijkwijzerRating: String?
        let kmrbRating: String?
        let lsfRating: String?
        let mccaaRating: String?
        let mccypRating: String?
        let mcstRating: String?
        let mdaRating: String?
        let medietilsynetRating: String?
        let mekuRating: String?
        let mibacRating: String?
        let mocRating: String?
        let moctwRating: String?
        let mpaaRating: String?
        let mpaatRating: String?
        let mtrcbRating: String?
        let nbcRating: String?
        let nbcolRating: String?
        let nfrcRating: String?
        let nfvcbRating: String?
        let nkclvRating: String?
        let oflcRating: String?
        let pefilmRating: String?
        let rcnofRating: String?
        let resorteviolenciaRating: String?
        let rtcRating: String?
        let rteRating: String?
        let russiaRating: String?
        let skfilmRating: String?
        let smaisRating: String?
        let smsaRating: String?
        let tvpgRating: String?
    }
    
    fileprivate struct Thumbnail: Codable {
        let url: String?
        let width: Int?
        let height: Int?
    }
    
    fileprivate struct RelatedPlaylists: Codable {
        let likes: String?
        let uploads: String?
    }

    fileprivate struct Status_: Codable {
        let uploadStatus: String?
        let failureReason: String?
        let rejectionReason: String?
        let privacyStatus: String?
        let publishAt: String?
        let license: String?
        let embeddable: Bool?
        let publicStatsViewable: Bool?
        let madeForKids: Bool?
        let selfDeclaredMadeForKids: Bool?
        let containsSyntheticMedia: Bool?
    }

    fileprivate struct Statistics: Codable {
        let viewCount: String?
        let likeCount: String?
        let dislikeCount: String?
        let favoriteCount: String?
        let commentCount: String?
    }
    
    fileprivate struct PaidProductPlacementDetails: Codable {
        let hasPaidProductPlacement: Bool?
    }
    
    fileprivate struct Player: Codable {
        let embedHtml: String?
        let embedHeight: Int?
        let embedWidth: Int?
    }

    fileprivate struct TopicDetails: Codable {
        let topicIds: [String]?
        let relevantTopicIds: [String]?
        let topicCategories: [String]?
    }

    fileprivate struct RecordingDetails: Codable {
        let recordingDate: String?
    }

    fileprivate struct FileDetails: Codable {
        let fileName: String?
        let fileSize: UInt64?
        let fileType: String?
        let container: String?
        let videoStreams: [VideoStream]?
        let audioStreams: [AudioStream]?
        let durationMs: UInt64?
        let bitrateBps: UInt64?
        let creationTime: String?
    }

    fileprivate struct VideoStream: Codable {
        let widthPixels: UInt?
        let heightPixels: UInt?
        let frameRateFps: Double?
        let aspectRatio: Double?
        let codec: String?
        let bitrateBps: UInt64?
        let rotation: String?
        let vendor: String?
    }

    fileprivate struct AudioStream: Codable {
        let channelCount: UInt?
        let codec: String?
        let bitrateBps: UInt64?
        let vendor: String?
    }

    fileprivate struct ProcessingDetails: Codable {
        let processingStatus: String?
        let processingProgress: ProcessingProgress?
        let processingFailureReason: String?
        let fileDetailsAvailability: String?
        let processingIssuesAvailability: String?
        let tagSuggestionsAvailability: String?
        let editorSuggestionsAvailability: String?
        let thumbnailsAvailability: String?
    }

    fileprivate struct ProcessingProgress: Codable {
        let partsTotal: UInt?
        let partsProcessed: UInt?
        let timeLeftMs: UInt?
    }

    fileprivate struct Suggestions: Codable {
        let processingIssues: [String]?
        let processingErrors: [String]?
        let processingWarnings: [String]?
        let processingHints: [String]?
        let tagSuggestions: [TagSuggestion]?
        let editorSuggestions: [String]?
    }

    fileprivate struct TagSuggestion: Codable {
        let tag: String?
        let categoryRestricts: [String]?
    }

    fileprivate struct LiveStreamingDetails: Codable {
        let actualStartTime: String?
        let actualEndTime: String?
        let scheduledStartTime: String?
        let scheduledEndTime: String?
        let concurrentViewers: UInt?
        let activeLiveChatId: String?
    }

    fileprivate struct Localizations: Codable {
        let title: String?
        let description: String?
    }

}

private extension MetadataResult {

    convenience init(item: YouTube.Item) {
        self.init()
        self.mediaKind = .tvShow
        if let title = item.snippet?.title {
            self[.name] = title
        }
        self[.seriesName] = item.snippet?.channelTitle
        self[.serviceContentID] = item.snippet?.channelId
        self[.serviceAdditionalContentID] = item.id
        if let videoId = item.snippet?.resourceId?.videoId {
            self[.episodeID] = videoId
        } else {
            self[.episodeID] = item.id
        }
        if let category = item.snippet?.categoryId {
            self[.genre] = YouTube.categories[Int(category) ?? 0]
        }
        self[.description] = item.snippet?.description
        self[.releaseDate] = item.snippet?.publishedAt
        if let rawDate = item.snippet?.publishedAt {
            if let date = ISO8601DateFormatter().date(from: rawDate) {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy"
                self[.season] = Int(dateFormatter.string(from: date))
                let calendar = Calendar.current
                let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date)
                self[.episodeNumber] = dayOfYear
            }
        }
        if let artwork = item.snippet?.thumbnails?.addArtwork(type: .episode, title: "Video") {
            self.remoteArtworks.append(artwork)
        }
    }

    convenience init(item: YouTube.SearchItem) {
        self.init()
        self.mediaKind = .tvShow
        self[.seriesName] = item.snippet?.channelTitle
        self[.serviceContentID] = item.snippet?.channelId
        self[.name] = item.snippet?.title
        self[.episodeID] = item.id?.videoId
        self[.description] = item.snippet?.description
        self[.releaseDate] = item.snippet?.publishedAt
        if let rawDate = item.snippet?.publishedAt {
            if let date = ISO8601DateFormatter().date(from: rawDate) {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy"
                self[.season] = Int(dateFormatter.string(from: date))
                let calendar = Calendar.current
                let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date)
                self[.episodeNumber] = dayOfYear
            }
        }
        if let artwork = item.snippet?.thumbnails?.addArtwork(type: .poster, title: "Video") {
            self.remoteArtworks.append(artwork)
        }
    }

    func updateVideo(with item: YouTube.Item) {
        if let category = Int(item.snippet?.categoryId ?? "0") {
            self[.genre] = YouTube.categories[category]
        }
        self[.name] = item.snippet?.title
        if let artwork = item.snippet?.thumbnails?.addArtwork(type: .episode, title: "Video") {
            self.remoteArtworks.append(artwork)
        }
    }
    
    func insertChannel(contentOf item: YouTube.Item) {
        self[.seriesDescription] = item.snippet?.description
        self[.studio] = item.snippet?.customUrl
        if let artwork = item.snippet?.thumbnails?.addArtwork(type: .poster, title: "Channel") {
            self.remoteArtworks.append(artwork)
        }
    }
}
