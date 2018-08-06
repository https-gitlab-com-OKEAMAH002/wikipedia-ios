// https://meta.wikimedia.org/wiki/Schema:MobileWikiAppiOSFeed

@objc public final class FeedFunnel: EventLoggingFunnel, EventLoggingStandardEventProviding {
    @objc public static let shared = FeedFunnel()
    
    private override init() {
        super.init(schema: "MobileWikiAppiOSFeed", version: 18225687)
    }
    
    private enum Action: String {
        case impression
        case openCard = "open_card"
        case dismiss
        case retain
        case refresh
        case preview
        case readStart = "read_start"
        case shareTap = "share_tap"
        case closeCard = "close_card"
    }
    
    private func event(category: EventLoggingCategory, label: EventLoggingLabel?, action: Action, measureAge: NSNumber? = nil, measurePosition: Int? = nil, measureTime: Double? = nil, measureMaxViewed: Double? = nil) -> Dictionary<String, Any> {
        let category = category.rawValue
        let action = action.rawValue
        
        var event: [String: Any] = ["category": category, "action": action, "primary_language": primaryLanguage(), "is_anon": isAnon]
        if let label = label?.rawValue {
            event["label"] = label
        }
        if let measureAge = measureAge {
            event["measure_age"] = measureAge.intValue
        }
        if let measurePosition = measurePosition {
            event["measure_position"] = measurePosition
        }
        if let measureTime = measureTime {
            event["measure_time"] = Int(round(measureTime))
        }
        if let measureMaxViewed = measureMaxViewed {
            event["measure_max_viewed"] = Int(round(measureMaxViewed))
        }
        return event
    }
    
    override public func preprocessData(_ eventData: [AnyHashable: Any]) -> [AnyHashable: Any] {
        return wholeEvent(with: eventData)
    }
    
    // MARK: - Feed

    @objc public func logFeedCardOpened(for group: WMFContentGroup?) {
        log(event(category: .feed, label: group?.eventLoggingLabel, action: .openCard, measureAge: measureAge(for: group)))
    }

    @objc public func logFeedCardDismissed(for group: WMFContentGroup?) {
        log(event(category: .feed, label: group?.eventLoggingLabel, action: .dismiss, measureAge: measureAge(for: group) ))
    }

    @objc public func logFeedCardRetained(for group: WMFContentGroup?) {
        log(event(category: .feed, label: group?.eventLoggingLabel, action: .retain, measureAge: measureAge(for: group)))
    }

    @objc public func logFeedCardPreviewed(for group: WMFContentGroup?, index: Int) {
        log(event(category: .feed, label: group?.eventLoggingLabel, action: .preview, measureAge: measureAge(for: group), measurePosition: measurePosition(for: group, index: index)))
    }

    @objc public func logFeedCardReadingStarted(for group: WMFContentGroup?, index: NSNumber?) {
        log(event(category: .feed, label: group?.eventLoggingLabel, action: .readStart, measureAge: measureAge(for: group), measurePosition: measurePosition(for: group, index: index?.intValue)))
    }

    @objc public func logFeedShareTapped(for group: WMFContentGroup?, index: NSNumber?) {
        logFeedShareTapped(for: group, index: index?.intValue)
    }

    public func logFeedShareTapped(for group: WMFContentGroup?, index: Int?) {
        log(event(category: .feed, label: group?.eventLoggingLabel, action: .shareTap, measureAge: measureAge(for: group), measurePosition: measurePosition(for: group, index: index)))
    }

    @objc public func logFeedRefreshed() {
        log(event(category: .feed, label: nil, action: .refresh))
    }

    public func logFeedImpression(for group: WMFContentGroup?) {
        log(event(category: .feed, label: group?.eventLoggingLabel, action: .impression, measureAge: measureAge(for: group)))
    }

    // MARK: Feed detail

    public func logArticleInFeedDetailPreviewed(for group: WMFContentGroup?, index: Int) {
        log(event(category: .feedDetail, label: group?.eventLoggingLabel, action: .preview, measureAge: measureAge(for: group), measurePosition: index))
    }

    public var fetchedContentGroupsInFeedController: NSFetchedResultsController<WMFContentGroup>?

    private func measureAge(for group: WMFContentGroup?) -> NSNumber? {
        guard let group = group, let fetchedContentGroupsInFeedController = fetchedContentGroupsInFeedController else {
            return nil
        }
        let measureAge: NSNumber?
        if group.appearsOncePerDay {
            measureAge = group.eventLoggingMeasureAge
        } else {
            let groups = fetchedContentGroupsInFeedController.fetchedObjects?.filter { $0.contentGroupKind == group.contentGroupKind }
            if let index = groups?.index(of: group) {
                measureAge = NSNumber(value: index)
            } else {
                measureAge = nil
            }
        }
        return measureAge
    }

    private func measurePosition(for group: WMFContentGroup?, index: Int?) -> Int? {
        guard let group = group else {
            return nil
        }
        switch group.contentGroupKind {
        case .onThisDay:
            fallthrough
        case .news:
            return nil
        default:
            return index
        }
    }
}

private extension WMFContentGroup {
    var eventLoggingMeasureAge: NSNumber? {
        if appearsOncePerDay {
            guard let date = midnightUTCDate else {
                return nil
            }
            let now = NSDate().wmf_midnightUTCDateFromLocal
            return NSNumber(integerLiteral: NSCalendar.wmf_gregorian().wmf_days(from: date, to: now))
        } else {
            return nil
        }
    }

    var appearsOncePerDay: Bool {
        switch contentGroupKind {
        case .continueReading:
            fallthrough
        case .relatedPages:
            return false
        default:
            return true
        }
    }
}
/*
 Q: what constitutes an impression? (on feed is it first time user sees it, or each time it scrolls into view?)
 A: FOR NOW: (per Chelsy) log impression if card onscreen for more than 1 second (doesn't matter if moving - may tweak later if needed)
      do same for feed education card (1 second min onscreen before logging)

 Labels:
 EventLoggingLabel const EventLoggingLabelFeaturedArticle = @"featured_article";
 EventLoggingLabel const EventLoggingLabelTopRead = @"top_read";
 EventLoggingLabel const EventLoggingLabelOnThisDay = @"on_this_day";
 EventLoggingLabel const EventLoggingLabelNews = @"news";
 EventLoggingLabel const EventLoggingLabelRelatedPages = @"related_pages";
 EventLoggingLabel const EventLoggingLabelContinueReading = @"continue_reading";
 EventLoggingLabel const EventLoggingLabelMainPage = @"main_page";
 EventLoggingLabel const EventLoggingLabelLocation = @"location";  (ok use "location" instead of "places"? ask chelsy - yes - 5.8.2 uses it when you save compass cell from feed via peek menu save)
 EventLoggingLabel const EventLoggingLabelRandom = @"random";
 EventLoggingLabel const EventLoggingLabelPictureOfTheDay = @"picture_of_the_day";
*/
